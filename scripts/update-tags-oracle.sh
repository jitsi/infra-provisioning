#!/bin/bash

# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

# e.g. $LOCAL_PATH/terraform/wavefront-proxy
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z $ENVIRONMENT ]; then
  echo "No ENVIRONMENT provided or found. Exiting..."
  exit 201
fi

[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

if [ -z "$COMPARTMENT_OCID" ]; then
  echo "No COMPARTMENT_OCID found. Exiting..."
  exit 205
fi

[ -z "$AVAILABILITY_DOMAINS" ] && AVAILABILITY_DOMAINS=$(oci iam availability-domain list --region=$ORACLE_REGION | jq -r .data[].name )
if [ -z "$AVAILABILITY_DOMAINS" ]; then
  echo "No AVAILABILITY_DOMAINS found.  Exiting..."
  exit 206
fi

OLD_TAG_NAMESPACE="eghtjitsi-$ENVIRONMENT"

# FIRST TAG PUBLIC IPS

skipped_ips_ocid=()
TOTAL_IPS=0
SKIPPED_IPS=0
PUBLIC_IPS=$(oci network public-ip list --region "$ORACLE_REGION" --compartment-id "$COMPARTMENT_OCID" --scope REGION --lifetime RESERVED --all --query 'data[].id'| jq '.[]|select(.|startswith("ocid1.publicip"))' | jq --slurp 'join(" ")' | jq -r .)
for ip_ocid in $PUBLIC_IPS; do
    TOTAL_IPS=$((TOTAL_IPS+1))
    reserved_public_ip_details=$(oci network public-ip get --region "$ORACLE_REGION" --public-ip-id "$ip_ocid")
    reserved_public_ip_name=$(echo $reserved_public_ip_details | jq -r '.data["display-name"]')
    etag_reserved_public_ip=$(echo "$reserved_public_ip_details" | jq -r '.etag')

    old_defined_tags=$(echo $reserved_public_ip_details | jq '.data["defined-tags"]')
    new_count=$(echo $old_defined_tags | jq -r ".$TAG_NAMESPACE|length")
    if [ "$new_count" -gt 0 ]; then
        echo "Skipping the public ip $reserved_public_ip_name, ocid $ip_ocid, as it has already new tags..."
        skipped_ips_ocid+=("$ip_ocid")
        SKIPPED_IPS=$((SKIPPED_IPS+1))
    else
        old_namespace_tags=$(echo $old_defined_tags | jq ".\"$OLD_TAG_NAMESPACE\"")
        new_defined_tags=$(echo $old_defined_tags "{\"$TAG_NAMESPACE\":$old_namespace_tags}" | jq -s add)
        echo "Setting defined tags $new_defined_tags to reserved public ip: $reserved_public_ip_name"
        oci network public-ip update --region "$ORACLE_REGION" --public-ip-id $ip_ocid --if-match "$etag_reserved_public_ip" --defined-tags "$(echo "$new_defined_tags" | tr -d '\n')" --force

        if [ $? -gt 0 ]; then
            echo "Error while updating the public ip $reserved_public_ip_name. Exiting..."
            exit 210
        fi
    fi
done

echo "Skipped from processing the following ips: ${skipped_ips_ocid[@]}, please review them if needed"
echo "Finished running the script, found $TOTAL_IPS, skipped $SKIPPED_IPS"

# loop through existing running instances in compartment and region
INSTANCE_FILE="./instances-${ORACLE_REGION}.json"
oci compute instance list --lifecycle-state RUNNING --all --compartment-id $COMPARTMENT_OCID --region $ORACLE_REGION > $INSTANCE_FILE
if [ $? -eq 0 ]; then
  # do stuff with json
  INSTANCE_COUNT=$(cat $INSTANCE_FILE | jq -r ".data|length")
  SKIPPED_COUNT=0
  UPDATE_COUNT=0
  if [[ $INSTANCE_COUNT -gt 0 ]]; then
    echo "Found $INSTANCE_COUNT instances in compartment, checking defined tags"
    for i in `seq 0 $((INSTANCE_COUNT-1))`; do
      INSTANCE_DETAILS=$(cat $INSTANCE_FILE | jq ".data[$i]")
      INSTANCE_ID=$(echo $INSTANCE_DETAILS | jq -r ".id")
      EXISTING_TAGS=$(echo "$INSTANCE_DETAILS" | jq --sort-keys -c ".\"defined-tags\"")
      OLD_TAGS=$(echo $EXISTING_TAGS | jq --sort-keys -c ".\"$OLD_TAG_NAMESPACE\"")
      if [[ "$OLD_TAGS" != "null" ]]; then
        NEW_TAGS="{\"jitsi\":$OLD_TAGS}"
        FULL_TAGS=$(echo $NEW_TAGS $EXISTING_TAGS| jq --sort-keys -c -s '.[0] * .[1]')

        # apply tags to instance if they have changed
        if [[ "$EXISTING_TAGS" == "$FULL_TAGS" ]]; then
          echo "Tags already match, skipping $INSTANCE_ID"

          SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
        else
          echo "Updating tags on $INSTANCE_ID to $FULL_TAGS"
          oci compute instance update --region $ORACLE_REGION --instance-id $INSTANCE_ID --defined-tags "$FULL_TAGS" --force

          UPDATE_COUNT="$(( UPDATE_COUNT + 1 ))"
        fi
      else
        SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
        echo "Skipping $INSTANCE_ID, no defined-tags with old namespace $OLD_TAG_NAMESPACE found in $EXISTING_TAGS"
      fi
    done
    echo "Updated $UPDATE_COUNT skipped $SKIPPED_COUNT out of $INSTANCE_COUNT instances"
  else
    echo "Found 0 instances in compartment"
  fi
else
  echo "Failed to get instance list, no retagging of instances possible"
fi

# loop through existing block storage in compartment


for AD in $AVAILABILITY_DOMAINS; do
  # oracle field time-created has format "time-created": "2020-09-14T11:38:05.339000+00:00"
  BV_FILE="./boot-volumes-${ORACLE_REGION}-${AD}.json"

  oci bv boot-volume list --all --region "$ORACLE_REGION" --compartment-id "$COMPARTMENT_OCID" --availability-domain "$AD" > $BV_FILE
  if [ $? -eq 0 ]; then
    # do stuff with json
    BV_COUNT=$(cat $BV_FILE | jq -r ".data|length")
    SKIPPED_COUNT=0
    UPDATE_COUNT=0
    if [[ $BV_COUNT -gt 0 ]]; then
      echo "Found $BV_COUNT boot volumes in AD $AD, checking defined tags"
      for i in `seq 0 $((BV_COUNT-1))`; do
        BV_DETAILS=$(cat $BV_FILE | jq ".data[$i]")
        BV_ID=$(echo $BV_DETAILS | jq -r ".id")
        EXISTING_TAGS=$(echo "$BV_DETAILS" | jq --sort-keys -c ".\"defined-tags\"")
        OLD_TAGS=$(echo $EXISTING_TAGS | jq --sort-keys -c ".\"$OLD_TAG_NAMESPACE\"")
        if [[ "$OLD_TAGS" != "null" ]]; then
          NEW_TAGS="{\"jitsi\":$OLD_TAGS}"
          FULL_TAGS=$(echo $NEW_TAGS $EXISTING_TAGS| jq --sort-keys -c -s '.[0] * .[1]')

          # apply tags to volume if they have changed
          if [[ "$EXISTING_TAGS" == "$FULL_TAGS" ]]; then
            echo "Tags already match, skipping $BV_ID"

            SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
          else
            echo "Updating tags on $BV_ID to $FULL_TAGS"
            oci bv boot-volume update --region $ORACLE_REGION --boot-volume-id "$BV_ID" --defined-tags "$FULL_TAGS" --force

            UPDATE_COUNT="$(( UPDATE_COUNT + 1 ))"
          fi
        else
          SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
          echo "Skipping $BV_ID, no defined-tags with old namespace $OLD_TAG_NAMESPACE found in $EXISTING_TAGS"
        fi
      done
      echo "Updated $UPDATE_COUNT skipped $SKIPPED_COUNT out of $BV_COUNT volumnes"
    else
      echo "Found 0 volumes in compartment"
    fi
  else
    echo "Failed to get volume list in AD $AD, no retagging of volumes possible"
  fi
  rm $BV_FILE
done

# loop through existing VNICs in compartment

VNIC_FILE="./vnics-${ORACLE_REGION}.json"
oci compute instance list-vnics --all --region "$ORACLE_REGION" --compartment-id "$COMPARTMENT_OCID" > $VNIC_FILE
if [ $? -eq 0 ]; then
  # do stuff with json
  VNIC_COUNT=$(cat $VNIC_FILE | jq -r ".data|length")
  SKIPPED_COUNT=0
  UPDATE_COUNT=0
  if [[ $VNIC_COUNT -gt 0 ]]; then
    echo "Found $VNIC_COUNT vnics in compartment, checking defined tags"
    for i in `seq 0 $((VNIC_COUNT-1))`; do
      VNIC_DETAILS=$(cat $VNIC_FILE | jq ".data[$i]")
      VNIC_ID=$(echo $VNIC_DETAILS | jq -r ".id")
      EXISTING_TAGS=$(echo "$VNIC_DETAILS" | jq --sort-keys -c ".\"defined-tags\"")
      OLD_TAGS=$(echo $EXISTING_TAGS | jq --sort-keys -c ".\"$OLD_TAG_NAMESPACE\"")
      if [[ "$OLD_TAGS" != "null" ]]; then
        NEW_TAGS="{\"jitsi\":$OLD_TAGS}"
        FULL_TAGS=$(echo $NEW_TAGS $EXISTING_TAGS| jq --sort-keys -c -s '.[0] * .[1]')

        # apply tags to vnic if they have changed
        if [[ "$EXISTING_TAGS" == "$FULL_TAGS" ]]; then
          echo "Tags already match, skipping $VNIC_ID"

          SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
        else
          echo "Updating tags on $VNIC_ID to $FULL_TAGS"
          oci network vnic update --region $ORACLE_REGION --vnic-id $VNIC_ID --defined-tags "$FULL_TAGS" --force

          UPDATE_COUNT="$(( UPDATE_COUNT + 1 ))"
        fi
      else
        SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
        echo "Skipping $VNIC_ID, no defined-tags with old namespace $OLD_TAG_NAMESPACE found in $EXISTING_TAGS"
      fi
    done
    echo "Updated $UPDATE_COUNT skipped $SKIPPED_COUNT out of $VNIC_COUNT vnics"
  else
    echo "Found 0 vnics in compartment"
  fi
else
  echo "Failed to get vnic list, no retagging of vnics possible"
fi

# loop through existing buckets in compartment (no tags found, TODO: add tags on buckets)

# loop though existing instance pools

POOL_FILE="./instance-pools-${ORACLE_REGION}.json"
oci compute-management instance-pool list --all --region "$ORACLE_REGION" --compartment-id "$COMPARTMENT_OCID" > $POOL_FILE
if [ $? -eq 0 ]; then
  # do stuff with json
  POOL_COUNT=$(cat $POOL_FILE | jq -r ".data|length")
  SKIPPED_COUNT=0
  UPDATE_COUNT=0
  if [[ $POOL_COUNT -gt 0 ]]; then
    echo "Found $POOL_COUNT pools in compartment, checking defined tags"
    for i in `seq 0 $((POOL_COUNT-1))`; do
      POOL_DETAILS=$(cat $POOL_FILE | jq ".data[$i]")
      POOL_ID=$(echo $POOL_DETAILS | jq -r ".id")
      EXISTING_TAGS=$(echo "$POOL_DETAILS" | jq --sort-keys -c ".\"defined-tags\"")
      OLD_TAGS=$(echo $EXISTING_TAGS | jq --sort-keys -c ".\"$OLD_TAG_NAMESPACE\"")
      if [[ "$OLD_TAGS" != "null" ]]; then
        NEW_TAGS="{\"jitsi\":$OLD_TAGS}"
        FULL_TAGS=$(echo $NEW_TAGS $EXISTING_TAGS| jq --sort-keys -c -s '.[0] * .[1]')

        # apply tags to pool if they have changed
        if [[ "$EXISTING_TAGS" == "$FULL_TAGS" ]]; then
          echo "Tags already match, skipping $POOL_ID"

          SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
        else
          echo "Updating tags on $POOL_ID to $FULL_TAGS"
          oci compute-management instance-pool update --region $ORACLE_REGION --instance-pool-id $POOL_ID --defined-tags "$FULL_TAGS" --force

          UPDATE_COUNT="$(( UPDATE_COUNT + 1 ))"
        fi
      else
        SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
        echo "Skipping $POOL_ID, no defined-tags with old namespace $OLD_TAG_NAMESPACE found in $EXISTING_TAGS"
      fi
    done
    echo "Updated $UPDATE_COUNT skipped $SKIPPED_COUNT out of $POOL_COUNT pools"
  else
    echo "Found 0 pools in compartment"
  fi
else
  echo "Failed to get pool list, no retagging of pools possible"
fi

# loop through existing load balancers

LB_FILE="./load-balancers-${ORACLE_REGION}.json"
oci lb load-balancer list --all --region "$ORACLE_REGION" --compartment-id "$COMPARTMENT_OCID" > $LB_FILE
if [ $? -eq 0 ]; then
  # do stuff with json
  LB_COUNT=$(cat $LB_FILE | jq -r ".data|length")
  SKIPPED_COUNT=0
  UPDATE_COUNT=0
  if [[ $LB_COUNT -gt 0 ]]; then
    echo "Found $LB_COUNT load balancers in compartment, checking defined tags"
    for i in `seq 0 $((LB_COUNT-1))`; do
      LB_DETAILS=$(cat $LB_FILE | jq ".data[$i]")
      LB_ID=$(echo $LB_DETAILS | jq -r ".id")
      EXISTING_TAGS=$(echo "$LB_DETAILS" | jq --sort-keys -c ".\"defined-tags\"")
      OLD_TAGS=$(echo $EXISTING_TAGS | jq --sort-keys -c ".\"$OLD_TAG_NAMESPACE\"")
      if [[ "$OLD_TAGS" != "null" ]]; then
        NEW_TAGS="{\"jitsi\":$OLD_TAGS}"
        FULL_TAGS=$(echo $NEW_TAGS $EXISTING_TAGS| jq --sort-keys -c -s '.[0] * .[1]')

        # apply tags to lb if they have changed
        if [[ "$EXISTING_TAGS" == "$FULL_TAGS" ]]; then
          echo "Tags already match, skipping $LB_ID"

          SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
        else
          echo "Updating tags on $LB_ID to $FULL_TAGS"
          oci lb load-balancer update --region $ORACLE_REGION --load-balancer-id $LB_ID --defined-tags "$FULL_TAGS" --force

          UPDATE_COUNT="$(( UPDATE_COUNT + 1 ))"
        fi
      else
        SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
        echo "Skipping $LB_ID, no defined-tags with old namespace $OLD_TAG_NAMESPACE found in $EXISTING_TAGS"
      fi
    done
    echo "Updated $UPDATE_COUNT skipped $SKIPPED_COUNT out of $LB_COUNT load balancers"
  else
    echo "Found 0 load balancers in compartment"
  fi
else
  echo "Failed to get load balancer list, no retagging of load balancers possible"
fi

# loop through instance configurations

IC_FILE="./instance-configurations-${ORACLE_REGION}.json"
oci compute-management instance-configuration list --all --region "$ORACLE_REGION" --compartment-id "$COMPARTMENT_OCID" > $IC_FILE
if [ $? -eq 0 ]; then
  # do stuff with json
  IC_COUNT=$(cat $IC_FILE | jq -r ".data|length")
  SKIPPED_COUNT=0
  UPDATE_COUNT=0
  if [[ $IC_COUNT -gt 0 ]]; then
    echo "Found $IC_COUNT instance configurations in compartment, checking defined tags"
    for i in `seq 0 $((IC_COUNT-1))`; do
      IC_DETAILS=$(cat $IC_FILE | jq ".data[$i]")
      IC_ID=$(echo $IC_DETAILS | jq -r ".id")
      EXISTING_TAGS=$(echo "$IC_DETAILS" | jq --sort-keys -c ".\"defined-tags\"")
      OLD_TAGS=$(echo $EXISTING_TAGS | jq --sort-keys -c ".\"$OLD_TAG_NAMESPACE\"")
      if [[ "$OLD_TAGS" != "null" ]]; then
        NEW_TAGS="{\"jitsi\":$OLD_TAGS}"
        FULL_TAGS=$(echo $NEW_TAGS $EXISTING_TAGS| jq --sort-keys -c -s '.[0] * .[1]')

        # apply tags to lb if they have changed
        if [[ "$EXISTING_TAGS" == "$FULL_TAGS" ]]; then
          echo "Tags already match, skipping $IC_ID"

          SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
        else
          echo "Updating tags on $IC_ID to $FULL_TAGS"
          oci compute-management instance-configuration update --region $ORACLE_REGION --instance-configuration-id $IC_ID --defined-tags "$FULL_TAGS" --force

          UPDATE_COUNT="$(( UPDATE_COUNT + 1 ))"
        fi
      else
        SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
        echo "Skipping $IC_ID, no defined-tags with old namespace $OLD_TAG_NAMESPACE found in $EXISTING_TAGS"
      fi
    done
    echo "Updated $UPDATE_COUNT skipped $SKIPPED_COUNT out of $IC_COUNT instance configurations"
  else
    echo "Found 0 instance configurations in compartment"
  fi
else
  echo "Failed to get instance configuration list, no retagging of instance configurations possible"
fi
