

function should_assign_eip() {
  use_eip=$(curl -s curl http://169.254.169.254/opc/v1/instance/ | jq '."definedTags" | to_entries[] | select((.key | startswith("eghtjitsi")) or (.key == "jitsi")) |.value."use_eip"' -r)

  if [ ! -z "$use_eip" ] && [ "$use_eip" == 'true' ]; then
    echo "Will assign a reserved public ip to the instance"
    return 0
  else
    echo "The instance has an ephemeral public ip assigned"
    return 1
  fi
}

function switch_to_secondary_vnic() {
  status_code=0
  echo "Configure secondary NIC with routing"
  sudo /usr/local/bin/secondary_vnic_all_configure_oracle.sh -c || status_code=1

  if [ $status_code -gt 0 ]; then
    return $status_code
  fi

  echo "Detect secondary NIC"
  SECONDARY_VNIC_DEVICE="$(ip addr | egrep '^[0-9]' | egrep -v 'lo|docker' | tail -1 | awk '{print $2}')"
  SECONDARY_VNIC_DEVICE="${SECONDARY_VNIC_DEVICE::-1}"
  SECONDARY_VNIC_DEVICE="$(echo $SECONDARY_VNIC_DEVICE | cut -d'@' -f1)"

  echo "Switch default routes to NIC2"
  export NIC1_ROUTE_1=$(ip route show | grep default -m 1)
  sudo ip route delete $NIC1_ROUTE_1 || status_code=1

  if [ $status_code -gt 0 ]; then
    return $status_code
  fi

  # 
  export NIC1_ROUTE_2=$(ip route show | grep default -m 1)
  if [ ! -z "$NIC1_ROUTE_2" ]; then
    sudo ip route delete $NIC1_ROUTE_2 || status_code=1
  fi

  if [ $status_code -gt 0 ]; then
    return $status_code
  fi

  export NIC2_ROUTE="default via "$(ip route show | grep $SECONDARY_VNIC_DEVICE | awk '{ print substr($1,1,index($1,"/")-2)1 " " $2 " " $3}')
  sudo ip route add $NIC2_ROUTE || status_code=1
  return $status_code
}

function switch_to_primary_vnic() {
  status_code=0
  echo "Switch default route back to NIC1"

  sudo ip route delete $NIC2_ROUTE || status_code=1

  if [ $status_code -gt 0 ]; then
    return $status_code
  fi

  sudo ip route add $NIC1_ROUTE_1 || status_code=1

  if [ $status_code -gt 0 ]; then
    return $status_code
  fi

  if [ ! -z "$NIC1_ROUTE_2" ]; then
    sudo ip route add $NIC1_ROUTE_2 || status_code=1

    if [ $status_code -gt 0 ]; then
      return $status_code
    fi
  fi
  echo "Delete secondary NIC routing to avoid routing issues in the future"
  sudo /usr/local/bin/secondary_vnic_all_configure_oracle.sh -d || status_code=1
  return $status_code
}

function assign_reserved_public_ip() {
  [ -z "$PUBLIC_IP_ROLE" ] && PUBLIC_IP_ROLE="JVB"

  vnic_id=$(curl -s curl http://169.254.169.254/opc/v1/vnics/ | jq .[0].vnicId -r)
  vnic_details_result=$(oci network vnic get --vnic-id "$vnic_id" --auth instance_principal)
  if [ $? -eq 0 ]; then
    public_ip=$(echo "$vnic_details_result" | jq -r '.data["public-ip"]')

    private_ip=$(echo "$vnic_details_result" | jq -r '.data["private-ip"]')
    subnet_id=$(echo "$vnic_details_result" | jq -r '.data["subnet-id"]')
    private_ip_details=$(oci network private-ip list --subnet-id "$subnet_id" --ip-address "$private_ip" --auth instance_principal)
    private_ip_ocid=$(echo "$private_ip_details" | jq -r '.data[0] | .id')

    echo "Public ip is: $public_ip"

    if [ -z "$public_ip" ] || [ "$public_ip" == "null" ]; then
      echo "Search for a reserved public ip"
      compartment_id=$(echo "$vnic_details_result" | jq -r '.data["compartment-id"]')
      tag_namespace="jitsi"
      reserved_ips=$(oci network public-ip list --compartment-id "$compartment_id" --scope REGION --lifetime RESERVED --all --query 'data[?"defined-tags".'\"$tag_namespace\"'."shard-role" == `'$PUBLIC_IP_ROLE'`]' --auth instance_principal)

      reserved_unasigned_ips_count=$(echo "$reserved_ips" | jq '[.[] | select(."lifecycle-state" == "AVAILABLE")] | length' -r)
      if [ "$reserved_unasigned_ips_count" == 0 ]; then
        echo "No AVAILABLE and UNASIGNED reserved IPs. Exiting.."
        return 1
      fi
      random_ip_index=$(((RANDOM % reserved_unasigned_ips_count)))
      reserved_public_ip=$(echo "$reserved_ips" | jq --arg index "$random_ip_index" '[.[] | select(."lifecycle-state" == "AVAILABLE")][$index|tonumber] | ."ip-address"' -r)
      reserved_public_ip_ocid=$(echo "$reserved_ips" | jq --arg index "$random_ip_index" '[.[] | select(."lifecycle-state" == "AVAILABLE")][$index|tonumber] | ."id"' -r)

      reserved_public_ip_details=$(oci network public-ip get --public-ip-address "$reserved_public_ip" --auth instance_principal)
      reserved_public_ip_state=$(echo "$reserved_public_ip_details" | jq -r '.data["lifecycle-state"]')
      if [ "$reserved_public_ip_state" == "ASSIGNED" ]; then
        echo "Public ip $reserved_public_ip was assigned in the meantime to another instance"
        return 1
      fi

      etag_reserved_public_ip=$(echo "$reserved_public_ip_details" | jq -r '.etag')

      echo "Found unasigned public ip: $reserved_public_ip"

      echo "Assign public ip $reserved_public_ip to private ip: $private_ip"
      oci network public-ip update --public-ip-id "$reserved_public_ip_ocid" --private-ip-id "$private_ip_ocid" --wait-for-state ASSIGNED --if-match "$etag_reserved_public_ip" --max-wait-seconds 180 --auth instance_principal
      if [ "$?" -gt 0 ]; then
        echo "Failed assigning public ip to private ip"
        return 1
      else
        echo "Successfully assigned public ip: $reserved_public_ip to private ip $private_ip"
        return 0
      fi
    else
      echo "Public ip $public_ip already assigned"
      return 0
    fi
  else
    echo "Failed to determine IP status, waiting before retry"
    sleep 1
    return 1
  fi
}

function assign_ephemeral_public_ip() {
  vnic_id=$(curl -s curl http://169.254.169.254/opc/v1/vnics/ | jq .[0].vnicId -r)
  vnic_details_result=$(oci network vnic get --vnic-id "$vnic_id" --auth instance_principal)
  compartment_id=$(echo "$vnic_details_result" | jq -r '.data["compartment-id"]')
  public_ip=$(echo "$vnic_details_result" | jq -r '.data["public-ip"]')

  private_ip=$(echo "$vnic_details_result" | jq -r '.data["private-ip"]')
  subnet_id=$(echo "$vnic_details_result" | jq -r '.data["subnet-id"]')
  private_ip_details=$(oci network private-ip list --subnet-id "$subnet_id" --ip-address "$private_ip" --auth instance_principal)
  private_ip_ocid=$(echo "$private_ip_details" | jq -r '.data[0] | .id')

  echo "Public ip is: $public_ip"

  if [ -z "$public_ip" ] || [ "$public_ip" == "null" ]; then
    echo "Create and assign ephemeral public ip"
    oci network public-ip create --compartment-id "$compartment_id" --lifetime EPHEMERAL --private-ip-id "$private_ip_ocid" --wait-for-state ASSIGNED --auth instance_principal
    if [ "$?" -gt 0 ]; then
      echo "Failed assigning ephemeral public ip to private ip"
      return 1
    else
      echo "Successfully assigned ephemeral public ip to private ip $private_ip"
      return 0
    fi
  else
    echo "Public ip $public_ip already assigned"
    return 0
  fi
}

function check_secondary_ip() {
  local counter=1
  local ip_status=1

  while [ $counter -le 2 ]; do
    local my_private_ip=$(curl -s curl http://169.254.169.254/opc/v1/vnics/ | jq .[1].privateIp -r)

    if [ -z "$my_private_ip" ] || [ "$my_private_ip" == "null" ]; then
      sleep 30
      ((counter++))
    else
      ip_status=0
      break
    fi
  done

  if [ $ip_status -eq 1 ]; then
    echo "Secondary private IP still not available status: $ip_status" >$tmp_msg_file
    return 1
  else
    return 0
  fi
}

eip_assign() {
  [ -z "$PROVISION_COMMAND" ] && PROVISION_COMMAND="default_provision"

  EIP_EXIT_CODE=0
  (retry check_secondary_ip) || EIP_EXIT_CODE=1

  if [ $EIP_EXIT_CODE -eq 0 ]; then
      switch_to_secondary_vnic || EIP_EXIT_CODE=1
  fi

  if [ $EIP_EXIT_CODE -eq 0 ]; then
      (retry assign_reserved_public_ip 15 || retry assign_ephemeral_public_ip) || EIP_EXIT_CODE=1
      switch_to_primary_vnic || EIP_EXIT_CODE=1
  else
      switch_to_primary_vnic || EIP_EXIT_CODE=1
  fi

  if [ $EIP_EXIT_CODE -eq 0 ]; then
      (retry add_ip_tags && retry $PROVISION_COMMAND) || EIP_EXIT_CODE=1
  fi
  return $EIP_EXIT_CODE
}

function eip_main() {
  EXIT_CODE=0

  [ -z "$PROVISION_COMMAND" ] && PROVISION_COMMAND="default_provision"
  [ -z "$CLEAN_CREDENTIALS" ] && CLEAN_CREDENTIALS="true"

  if [ $EXIT_CODE -eq 0 ]; then
    if should_assign_eip; then
      eip_assign || EXIT_CODE=1
    else
        # we should not assign eip, therefore we assume we already have a public ip
        (retry check_private_ip && retry add_ip_tags && retry $PROVISION_COMMAND) || EXIT_CODE=1
    fi
  else
    echo "Failed to get private IP, no further provisioning possible.  This instance requires manual intervention"
  fi

  return $EXIT_CODE
}
# end of postinstall-eip-lib, this space intentionally left blank
