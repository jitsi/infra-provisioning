#!/bin/bash

. clouds/oracle.sh

COMPARTMENTS="$(oci iam compartment list | jq -r '.data[].id')"

REGIONS="$ORACLE_IMAGE_REGIONS"

for c in $COMPARTMENTS; do
    echo $c
    for r in $REGIONS; do
        NSGS="$(oci network nsg list --compartment-id $c --region $r | jq -r '.data[].id')"
        for id in $NSGS; do
            echo $id
            oci network nsg rules list --nsg-id $id --region $r
        done
    done
done
