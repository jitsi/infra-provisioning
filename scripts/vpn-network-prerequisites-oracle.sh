#!/bin/bash
set -x #echo on

# We need an envirnment "all"
if [ -z "$ENVIRONMENT" ]; then
  echo "No Environment provided or found. Exiting .."
  exit 202
fi

if [ -z "$CLOUD_NAME" ]; then
  echo "No CLOUD_NAME found.  Exiting..."
  exit 203
fi

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 204
fi

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$AWS_VPC_CIDR" ] && AWS_VPC_CIDR="$DEFAULT_VPC_CIDR"

[ -z "$VCN_NAME_ROOT" ] && VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"
vcn_details=$(oci network vcn list --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --display-name "${VCN_NAME}" --all)
vcn_id="$(echo "$vcn_details" | jq -r '.data[0].id')"

###Get Or Create Dynamic Routing Gateway
DRG_NAME="DRG ${VCN_NAME_ROOT}"
drg_details=$(oci network drg list --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --all)
drg_ocid=$(echo "$drg_details" | jq -r ".data[] | select(.\"display-name\"==\"${DRG_NAME}\") | .id")

if [ -z "$drg_ocid" ]; then
  echo "Will create a DRG named $DRG_NAME "
  drg_details=$(oci network drg create --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --display-name "${DRG_NAME}" --wait-for-state AVAILABLE)
  drg_ocid=$(echo "$drg_details" | jq -r ".data.id")
else
  echo "DRG $DRG_NAME is already created"
fi

###Attach the specified DRG to the specified VCN if is not already attached
DRG_ATTACHMENT_NAME="DRG ATTACHMENT ${VCN_NAME_ROOT}"
drg_attachment_details=$(oci network drg-attachment list --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --all)
drg_attachment_ocid=$(echo "$drg_attachment_details" | jq -r ".data[] | select(.\"display-name\"==\"${DRG_ATTACHMENT_NAME}\") | .id")

if [ -z "$drg_attachment_ocid" ]; then
  echo "Will attach the DRG $DRG_NAME to the VCN $VCN_NAME"
  oci network drg-attachment create --region "$ORACLE_REGION" --drg-id "$drg_ocid" --vcn-id "$vcn_id" --display-name "${DRG_ATTACHMENT_NAME}" --wait-for-state ATTACHED
else
  echo "DRG $DRG_NAME is already attached to the VCN $VCN_NAME"
fi

###Update the Route Table rules
drg_route_rule='[
{
  "network_entity_id": "'$drg_ocid'",
  "destination": "'$AWS_VPC_CIDR'",
  "destination_type": "CIDR_BLOCK"
}
]'

ROUTE_TABLE_NAME="Route Table ${VCN_NAME}"
route_table_details=$(oci network route-table list --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --vcn-id "${vcn_id}" --display-name "${ROUTE_TABLE_NAME}" --all)
route_table_id="$(echo "$route_table_details" | jq -r '.data[0].id')"

existing_route_table_rules=$(echo "$route_table_details" | jq -r '.data[0]."route-rules"')

check_drg_rule=$(echo "$existing_route_table_rules" | jq -r ".[] | select(.destination==\"${AWS_VPC_CIDR}\") | .destination")
if [ -z "$check_drg_rule" ]; then
  echo "Will update the route table"
  new_route_table_rules=$(echo "$existing_route_table_rules" | jq -r '. |= . + '"$drg_route_rule"'')
  oci network route-table update --region "$ORACLE_REGION" --rt-id="${route_table_id}" --route-rules="${new_route_table_rules}" --force
else
  echo "The route table already has a rule with destination $AWS_VPC_CIDR"
fi

###Update the Private Route Table rules
PRIVATE_ROUTE_TABLE_NAME="Private Route Table ${VCN_NAME}"
private_route_table_details=$(oci network route-table list --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --vcn-id "${vcn_id}" --display-name "${PRIVATE_ROUTE_TABLE_NAME}" --all)
private_route_table_id="$(echo "$private_route_table_details" | jq -r '.data[0].id')"

existing_private_route_table_rules=$(echo "$private_route_table_details" | jq -r '.data[0]."route-rules"')

check_drg_rule=$(echo "$existing_private_route_table_rules" | jq -r ".[] | select(.destination==\"${AWS_VPC_CIDR}\") | .destination")
if [ -z "$check_drg_rule" ]; then
  echo "Will update the private route table"
  new_private_route_table_rules=$(echo "$existing_private_route_table_rules" | jq -r '. |= . + '"$drg_route_rule"'')
  oci network route-table update --region "$ORACLE_REGION" --rt-id="${private_route_table_id}" --route-rules="${new_private_route_table_rules}" --force
else
  echo "The private route table already has a rule with destination $AWS_VPC_CIDR"
fi

###Define security rules
tcp_bgp_rule='[
  {
    "source": "0.0.0.0/0",
    "protocol": "6",
    "isStateless": false,
    "tcpOptions": {
      "destinationPortRange": {
        "max": 179,
        "min": 179
      }
    }
  }
]'

tcp_ikevpn_rule='[
  {
    "source": "0.0.0.0/0",
    "protocol": "6",
    "isStateless": false,
    "tcpOptions": {
      "destinationPortRange": {
        "max": 4500,
        "min": 4500
      }
    }
  }
]'

udp_ikevpn_rule='[
  {
    "source": "0.0.0.0/0",
    "protocol": "17",
    "isStateless": false,
    "udpOptions": {
      "destinationPortRange": {
        "max": 4500,
        "min": 4500
      }
    }
  }
]'

tcp_ike_rule='[
  {
    "source": "0.0.0.0/0",
    "protocol": "6",
    "isStateless": false,
    "tcpOptions": {
      "destinationPortRange": {
        "max": 500,
        "min": 500
      }
    }
  }
]'

udp_ike_rule='[
  {
    "source": "0.0.0.0/0",
    "protocol": "17",
    "isStateless": false,
    "udpOptions": {
      "destinationPortRange": {
        "max": 500,
        "min": 500
      }
    }
  }
]'

esp_rule='[
  {
    "source": "0.0.0.0/0",
    "protocol": "50",
    "isStateless": false
  }
]'

###Update Public Security List
PUBLIC_SECURITY_LIST_NAME="${VCN_NAME_ROOT}-PublicSecurityList"
public_security_list_details=$(oci network security-list list --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --vcn-id "${vcn_id}" --display-name "${PUBLIC_SECURITY_LIST_NAME}" --all)
public_security_list_id="$(echo "$public_security_list_details" | jq -r '.data[0].id')"
public_ingress_rules=$(echo "$public_security_list_details" | jq -r '.data[0]."ingress-security-rules"')
new_public_ingress_rules=$public_ingress_rules

check_tcp_bgp_rule=$(echo "$new_public_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"6\") | select(.\"tcp-options\".\"destination-port-range\".\"max\" == 179) | .source")
if [ -z "$check_tcp_bgp_rule" ]; then
  echo "Add new rule for BGP in the Public Security List"
  new_public_ingress_rules=$(echo "$new_public_ingress_rules" | jq -r '. |= . + '"$tcp_bgp_rule"'')
else
  echo "The rule for BGP already exists in the Public Security List"
fi

check_udp_ike_rule=$(echo "$new_public_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"17\") | select(.\"udp-options\".\"destination-port-range\".\"max\" == 500) | .source")
if [ -z "$check_udp_ike_rule" ]; then
  echo "Add new rule for IKE UDP in the Public Security List"
  new_public_ingress_rules=$(echo "$new_public_ingress_rules" | jq -r '. |= . + '"$udp_ike_rule"'')
else
  echo "The rule for IKE UDP already exists in the Public Security List"
fi

check_tcp_ike_rule=$(echo "$new_public_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"6\") | select(.\"tcp-options\".\"destination-port-range\".\"max\" == 500) | .source")
if [ -z "$check_tcp_ike_rule" ]; then
  echo "Add new rule for IKE TCP in the Public Security List"
  new_public_ingress_rules=$(echo "$new_public_ingress_rules" | jq -r '. |= . + '"$tcp_ike_rule"'')
else
  echo "The rule for IKE TCP already exists in the Public Security List"
fi

check_udp_ikevpn_rule=$(echo "$new_public_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"17\") | select(.\"udp-options\".\"destination-port-range\".\"max\" == 4500) | .source")
if [ -z "$check_udp_ikevpn_rule" ]; then
  echo "Add new rule for IKE VPN UDP in the Public Security List"
  new_public_ingress_rules=$(echo "$new_public_ingress_rules" | jq -r '. |= . + '"$udp_ikevpn_rule"'')
else
  echo "The rule for IKE VPN UDP already exists in the Public Security List"
fi

check_tcp_ikevpn_rule=$(echo "$new_public_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"6\") | select(.\"tcp-options\".\"destination-port-range\".\"max\" == 4500) | .source")
if [ -z "$check_tcp_ikevpn_rule" ]; then
  echo "Add new rule for IKE VPN TCP in the Public Security List"
  new_public_ingress_rules=$(echo "$new_public_ingress_rules" | jq -r '. |= . + '"$tcp_ikevpn_rule"'')
else
  echo "The rule for IKE VPN TCP already exists in the Public Security List"
fi

check_esp_rule=$(echo "$new_public_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"50\") | .source")
if [ -z "$check_esp_rule" ]; then
  echo "Add new rule for ESP in the Public Security List"
  new_public_ingress_rules=$(echo "$new_public_ingress_rules" | jq -r '. |= . + '"$esp_rule"'')
else
  echo "The rule for ESP already exists in the Public Security List"
fi

if [ "$new_public_ingress_rules" != "$public_ingress_rules" ]; then
  echo "Updating Public Security List"
  oci network security-list update --region "$ORACLE_REGION" --security-list-id "$public_security_list_id" --ingress-security-rules "$new_public_ingress_rules" --force
else
  echo "No updates to the Public Security List"
fi

###Update Private Security List
PRIVATE_SECURITY_LIST_NAME="${VCN_NAME_ROOT}-PrivateSecurityList"
private_security_list_details=$(oci network security-list list --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --vcn-id "${vcn_id}" --display-name "${PRIVATE_SECURITY_LIST_NAME}" --all)
private_security_list_id="$(echo "$private_security_list_details" | jq -r '.data[0].id')"
private_ingress_rules=$(echo "$private_security_list_details" | jq -r '.data[0]."ingress-security-rules"')
new_private_ingress_rules=$private_ingress_rules

check_tcp_bgp_rule=$(echo "$new_private_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"6\") | select(.\"tcp-options\".\"destination-port-range\".\"max\" == 179) | .source")
if [ -z "$check_tcp_bgp_rule" ]; then
  echo "Add new rule for BGP in the Private Security List"
  new_private_ingress_rules=$(echo "$new_private_ingress_rules" | jq -r '. |= . + '"$tcp_bgp_rule"'')
else
  echo "The rule for BGP already exists in the Private Security List"
fi

check_udp_ike_rule=$(echo "$new_private_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"17\") | select(.\"udp-options\".\"destination-port-range\".\"max\" == 500) | .source")
if [ -z "$check_udp_ike_rule" ]; then
  echo "Add new rule for IKE UDP in the Private Security List"
  new_private_ingress_rules=$(echo "$new_private_ingress_rules" | jq -r '. |= . + '"$udp_ike_rule"'')
else
  echo "The rule for IKE UDP already exists in the Private Security List"
fi

check_tcp_ike_rule=$(echo "$new_private_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"6\") | select(.\"tcp-options\".\"destination-port-range\".\"max\" == 500) | .source")
if [ -z "$check_tcp_ike_rule" ]; then
  echo "Add new rule for IKE TCP in the Private Security List"
  new_private_ingress_rules=$(echo "$new_private_ingress_rules" | jq -r '. |= . + '"$tcp_ike_rule"'')
else
  echo "The rule for IKE TCP already exists in the Private Security List"
fi

check_udp_ikevpn_rule=$(echo "$new_private_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"17\") | select(.\"udp-options\".\"destination-port-range\".\"max\" == 4500) | .source")
if [ -z "$check_udp_ikevpn_rule" ]; then
  echo "Add new rule for IKE VPN UDP in the Private Security List"
  new_private_ingress_rules=$(echo "$new_private_ingress_rules" | jq -r '. |= . + '"$udp_ikevpn_rule"'')
else
  echo "The rule for IKE VPN UDP already exists in the Private Security List"
fi

check_tcp_ikevpn_rule=$(echo "$new_private_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"6\") | select(.\"tcp-options\".\"destination-port-range\".\"max\" == 4500) | .source")
if [ -z "$check_tcp_ikevpn_rule" ]; then
  echo "Add new rule for IKE TCP in the Private Security List"
  new_private_ingress_rules=$(echo "$new_private_ingress_rules" | jq -r '. |= . + '"$tcp_ikevpn_rule"'')
else
  echo "The rule for IKE VPN TCP already exists in the Private Security List"
fi

check_esp_rule=$(echo "$new_private_ingress_rules" | jq -r ".[] | select(.source == \"0.0.0.0/0\") | select(.protocol == \"50\") | .source")
if [ -z "$check_esp_rule" ]; then
  echo "Add new rule for ESP in the Private Security List"
  new_private_ingress_rules=$(echo "$new_private_ingress_rules" | jq -r '. |= . + '"$esp_rule"'')
else
  echo "The rule for ESP already exists in the Private Security List"
fi

if [ "$new_private_ingress_rules" != "$private_ingress_rules" ]; then
  echo "Updating Private Security List"
  oci network security-list update --region "$ORACLE_REGION" --security-list-id "$private_security_list_id" --ingress-security-rules "$new_private_ingress_rules" --force
else
  echo "No updates to the Private Security List"
fi
