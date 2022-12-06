#!/usr/bin/env bash
set -x

# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

# e.g. ../all/bin/terraform/wavefront-proxy
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z $ENVIRONMENT ]; then
  echo "No ENVIRONMENT provided or found. Exiting..."
  exit 201
fi

[ -e "../all/clouds/oracle.sh" ] && . ../all/clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "../all/clouds/${ORACLE_CLOUD_NAME}.sh" ] && . ../all/clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$OLD_SHARD_ROLE" ] && OLD_SHARD_ROLE="null"
[ -z "$NEW_SHARD_ROLE" ] && NEW_SHARD_ROLE="JVB"

ips_with_old_shard_role=$(oci network public-ip list --region "$ORACLE_REGION" --compartment-id "$COMPARTMENT_OCID" --scope REGION --lifetime RESERVED --all --query 'data[?"defined-tags".'\"$TAG_NAMESPACE\"'."shard-role" == `'$OLD_SHARD_ROLE'`].id' | jq '.[]' | jq --slurp 'join(" ")' | jq -r .)

skipped_ips_ocid=()
for reserved_ip in ${ips_with_old_shard_role[@]}; do
  reserved_public_ip_details=$(oci network public-ip get --region "$ORACLE_REGION" --public-ip-id "$reserved_ip")
  reserved_public_ip_name=$(echo $reserved_public_ip_details | jq -r '.data["display-name"]')
  etag_reserved_public_ip=$(echo "$reserved_public_ip_details" | jq -r '.etag')

  old_defined_tags=$(echo $reserved_public_ip_details | jq '.data["defined-tags"]')
  if [ "$old_defined_tags" != "{}" ]; then
    echo "Skipping the public ip $reserved_public_ip_name, ocid $reserved_ip, as it has already tags $old_defined_tags..."
    skipped_ips_ocid+=("$reserved_ip")
  else
    new_defined_tags="{\"$TAG_NAMESPACE\" : { \"environment\":\"$ENVIRONMENT\", \"shard-role\":\"$NEW_SHARD_ROLE\"}}"
    echo "Setting defined tags $new_defined_tags to reserved public ip: $reserved_public_ip_name"
    oci network public-ip update --region "$ORACLE_REGION" --public-ip-id $reserved_ip --if-match "$etag_reserved_public_ip" --defined-tags "$new_defined_tags" --force

    if [ $? -gt 0 ]; then
      echo "Error while updating the public ip $reserved_public_ip_name. Exiting..."
      exit 210
    fi
  fi
done

echo "Skipped from processing the following ips: ${skipped_ips_ocid[@]}, please review them if needed"
echo "Finished running the script"

all_ips_count=$(oci network public-ip list --region "$ORACLE_REGION" --compartment-id "$COMPARTMENT_OCID" --scope REGION --lifetime RESERVED --all --query 'data[].id' | jq length)
jvb_ips_count=$(oci network public-ip list --region "$ORACLE_REGION" --compartment-id "$COMPARTMENT_OCID" --scope REGION --lifetime RESERVED --all --query 'data[?"defined-tags".'\"$TAG_NAMESPACE\"'."shard-role" == `JVB`].id' | jq length)
coturn_ips_count=$(oci network public-ip list --region "$ORACLE_REGION" --compartment-id "$COMPARTMENT_OCID" --scope REGION --lifetime RESERVED --all --query 'data[?"defined-tags".'\"$TAG_NAMESPACE\"'."shard-role" == `coturn`].id' | jq length)

echo "Finished running the script. Now we have $coturn_ips_count Coturn reserved public ips and $jvb_ips_count JVB reserved public ips, out of $all_ips_count reserved public ips"
