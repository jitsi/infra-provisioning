#!/bin/bash

# usage: ENVIRONMENT=env ORACLE_REGION=us-phoenix-1 scripts/link-ops-drgs-oracle.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

echo "## link-ops-drgs-oracle.sh: beginning"

if [ -z "$ENVIRONMENT" ]; then
  echo "## no ENVIRONMENT found, exiting..."
  exit 1
fi

[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "## no ORACLE_REGION found, exiting..."
  exit 1
fi

if [ -z "$OPS_ENVIRONMENTS" ]; then
  echo "## no OPS_ENVIRONMENTS provided or found. Exiting .."
  exit 1
elif [ "$OPS_ENVIRONMENTS" == "ALL" ]; then
    OPS_ENVIRONMENTS=$(ls $LOCAL_PATH/../sites/)
    echo -e "## connecting $ENVIRONMENT in $ORACLE_REGION to all other environments:\n$OPS_ENVIRONMENTS"
else
    echo -e "## connecting $ENVIRONMENT in $ORACLE_REGION to OPS_ENVIRONMENTS:\n$OPS_ENVIRONMENTS"
fi

# load oracle variables
. $LOCAL_PATH/../clouds/all.sh

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

if [ -z "$COMPARTMENT_OCID" ]; then
  echo "## no COMPARTMENT_OCID found, exiting..."
  exit 1
fi

set -x
CIDRS="10.0.0.0/8"
OPS_COMPARTMENT_OCID="$COMPARTMENT_OCID"

[ -z "$VCN_NAME_ROOT" ] && VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"
vcn_details=$(oci network vcn list --region "$ORACLE_REGION" --compartment-id "${OPS_COMPARTMENT_OCID}" --display-name "${VCN_NAME}" --all)
vcn_id="$(echo "$vcn_details" | jq -r '.data[0].id')"

## get Dynamic Routing Gateway
DRG_NAME="DRG ${VCN_NAME_ROOT}"
drg_details=$(oci network drg list --region "$ORACLE_REGION" --compartment-id "${OPS_COMPARTMENT_OCID}" --all)
drg_ocid=$(echo "$drg_details" | jq -r ".data[] | select(.\"display-name\"==\"${DRG_NAME}\") | .id")

if [ -z "$drg_ocid" ]; then
    echo -e "## ERROR: ops DRG not found in VCN $VCN_NAME, you probably want to run:\n> ENVIRONMENT=$ENVIRONMENT ORACLE_REGION=$ORACLE_REGION scripts/create-drg-oracle.sh"
    exit 1
fi

## List the existing remote peering connections
EXISTING_PEERING_CONNECTIONS=$(oci network remote-peering-connection list --region $ORACLE_REGION --compartment-id $COMPARTMENT_OCID --drg-id "${drg_ocid}")

## Build list of existing peered items
EXISTING_PEER_CLOUDS="$(echo "$EXISTING_PEERING_CONNECTIONS" | jq -r '.data[]|select(."peering-status" == "PEERED")|."display-name"')"
LOCAL_CLOUD="$ENVIRONMENT-$ORACLE_REGION"

for PEER_ENVIRONMENT in $OPS_ENVIRONMENTS; do
    if [ "$ENVIRONMENT" == "$PEER_ENVIRONMENT" ]; then
      continue
    fi
    . $LOCAL_PATH/../sites/$PEER_ENVIRONMENT/stack-env.sh 
    PEER_COMPARTMENT_OCID="$COMPARTMENT_OCID"
    OPS_DRG_PEER_REGIONS="$DRG_PEER_REGIONS"
    for R in $OPS_DRG_PEER_REGIONS; do
        SKIP_EXISTING=false
        PEER_CLOUD="$PEER_ENVIRONMENT-$R"
        PEER_VCN_NAME="$R-$PEER_ENVIRONMENT"
        for EC in $EXISTING_PEER_CLOUDS; do
            if [[ "$PEER_CLOUD" == "$EC" ]]; then
                SKIP_EXISTING=true
            fi
        done
        if $SKIP_EXISTING; then
            echo "## skipping existing peered region $PEER_ENVIRONMENT $R"
        else
            echo "## checking for existing peer connection waiting to be connected $PEER_ENVIRONMENT $R"
            # find existing DRG in other region
            PEER_DRG_NAME="DRG ${PEER_VCN_NAME}"
            peer_drg_details=$(oci network drg list --region "$R" --compartment-id "${PEER_COMPARTMENT_OCID}" --all)
            peer_drg_ocid=$(echo "$peer_drg_details" | jq -r ".data[] | select(.\"display-name\"==\"${PEER_DRG_NAME}\") | .id")
            if [ -z "$peer_drg_ocid" ]; then
                echo "## skipping $R in $PEER_ENVIRONMENT as no DRG was found"
            else
                # found existing DRG, so make a local peer connection
                LOCAL_PEER_CONNECTION=$(echo "$EXISTING_PEERING_CONNECTIONS" | jq ".data[]|select(.\"display-name\" == \"$PEER_CLOUD\")")
                if [ -z "$LOCAL_PEER_CONNECTION" ]; then
                    echo "## creating new local peer connection for region $R in region $ORACLE_REGION"
                    LOCAL_PEER_CONNECTION=$(oci network remote-peering-connection create --display-name "${PEER_CLOUD}" --region $ORACLE_REGION --compartment-id $OPS_COMPARTMENT_OCID --drg-id "${drg_ocid}" --wait-for-state "AVAILABLE" | jq '.data')
                fi

                # now find remote peer connection
                EXISTING_REMOTE_CONNECTIONS=$(oci network remote-peering-connection list --region $R --compartment-id $PEER_COMPARTMENT_OCID --drg-id "${peer_drg_ocid}")
                REMOTE_PEER_CONNECTION=$(echo "$EXISTING_REMOTE_CONNECTIONS" | jq ".data[]|select(.\"display-name\" == \"$LOCAL_CLOUD\")")
                if [ -z "$REMOTE_PEER_CONNECTION" ]; then
                    echo "## creating new remote peer connection for local region $ORACLE_REGION in region $R"
                    REMOTE_PEER_CONNECTION=$(oci network remote-peering-connection create --display-name "$LOCAL_CLOUD" --region $R --compartment-id $PEER_COMPARTMENT_OCID --drg-id "${peer_drg_ocid}" --wait-for-state "AVAILABLE" | jq '.data')
                fi
                LOCAL_CONNECTION_OCID=$(echo "$LOCAL_PEER_CONNECTION" | jq -r ".id")
                REMOTE_CONNECTION_OCID=$(echo "$REMOTE_PEER_CONNECTION" | jq -r ".id")

                # now link remote and local peer
                echo "## linking remote region $PEER_ENVIRONMENT $R with local region $ENVIRONMENT $ORACLE_REGION"
                oci network remote-peering-connection connect --region $ORACLE_REGION --remote-peering-connection-id $LOCAL_CONNECTION_OCID --peer-id $REMOTE_CONNECTION_OCID --peer-region-name $R
            fi
        fi
    done
done
