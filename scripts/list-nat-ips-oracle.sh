#!/bin/bash

ENVIRONMENT="${1:-$ENVIRONMENT}"

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT provided. Pass as \$1 or set ENVIRONMENT env var."
  exit 1
fi

. clouds/oracle.sh
[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

if [ -z "$COMPARTMENT_OCID" ]; then
  echo "No COMPARTMENT_OCID found in sites/$ENVIRONMENT/stack-env.sh"
  exit 2
fi

REGIONS="$ORACLE_IMAGE_REGIONS"

for r in $REGIONS; do
    oci network nat-gateway list --compartment-id "$COMPARTMENT_OCID" --region "$r" --all 2>/dev/null \
      | jq -r --arg region "$r" '.data[] | [$region, .["nat-ip"], .["display-name"]] | @tsv'
done
