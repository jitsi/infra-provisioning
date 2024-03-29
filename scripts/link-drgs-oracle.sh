#!/bin/bash

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#set -x #echo on

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 204
fi

if [ -z "$DRG_PEER_REGIONS" ]; then
  echo "No DRG_PEER_REGIONS found.  Exiting..."
  exit 204
fi

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

# TRANSIT_GATEWAY_ROUTES=$(CLOUD_NAME="$CLOUD_NAME" ROUTE_TYPES="vpc,peering" $LOCAL_PATH/describe-transit-gateway-routes.sh)
# CIDRS=$(echo $TRANSIT_GATEWAY_ROUTES | jq -r ".cidrs[]")

CIDRS="10.0.0.0/8"

[ -z "$VCN_NAME_ROOT" ] && VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"
vcn_details=$(oci network vcn list --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --display-name "${VCN_NAME}" --all)
vcn_id="$(echo "$vcn_details" | jq -r '.data[0].id')"

###Get Or Create Dynamic Routing Gateway
DRG_NAME="DRG ${VCN_NAME_ROOT}"
drg_details=$(oci network drg list --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --all)
drg_ocid=$(echo "$drg_details" | jq -r ".data[] | select(.\"display-name\"==\"${DRG_NAME}\") | .id")

## List the existing remote peering connections

EXISTING_PEERING_CONNECTIONS=$(oci network remote-peering-connection list --region $ORACLE_REGION --compartment-id $COMPARTMENT_OCID --drg-id "${drg_ocid}")

## Build list of existing peered regions
EXISTING_PEER_NAMES=$(echo "$EXISTING_PEERING_CONNECTIONS" | jq -r '.data[]|select(."peering-status" == "PEERED")|."display-name"')
LOCAL_CLOUD="$ENVIRONMENT-$ORACLE_REGION"

#set -x

for R in $DRG_PEER_REGIONS; do
    if [[ "$R" == "$ORACLE_REGION" ]]; then
        echo "Skipping peer check for local region $R"
    else
        SKIP_EXISTING=false
        for EN in $EXISTING_PEER_NAMES; do
            if [[ "$ENVIRONMENT-$R" == "$EN" ]]; then
                SKIP_EXISTING=true
            fi
        done
        if $SKIP_EXISTING; then
            echo "Skipping existing peered vcn: $R"
        else
            echo "Checking for existing peer connection waiting to be connected"
            PEER_CLOUD="$ENVIRONMENT-$R"
            PEER_VCN_NAME="$R-$ENVIRONMENT"

            # find existing DRG in other region
            PEER_DRG_NAME="DRG ${PEER_VCN_NAME}"
            peer_drg_details=$(oci network drg list --region "$R" --compartment-id "${COMPARTMENT_OCID}" --all)
            peer_drg_ocid=$(echo "$peer_drg_details" | jq -r ".data[] | select(.\"display-name\"==\"${PEER_DRG_NAME}\") | .id")
            if [ -z "$peer_drg_ocid" ]; then
                echo "Skipping as no DRG was found in peer region $R"
            else
                # found existing DRG, so make a local peer connection
                LOCAL_PEER_CONNECTION=$(echo "$EXISTING_PEERING_CONNECTIONS" | jq ".data[]|select(.\"display-name\" == \"$PEER_CLOUD\")")
                if [ -z "$LOCAL_PEER_CONNECTION" ]; then
                    echo "Creating new local peer connection for region $R in region $ORACLE_REGION"
                    LOCAL_PEER_CONNECTION=$(oci network remote-peering-connection create --display-name "${PEER_CLOUD}" --region $ORACLE_REGION --compartment-id $COMPARTMENT_OCID --drg-id "${drg_ocid}" --wait-for-state "AVAILABLE" | jq '.data')
                fi

                # now find remote peer connection
                EXISTING_REMOTE_CONNECTIONS=$(oci network remote-peering-connection list --region $R --compartment-id $COMPARTMENT_OCID --drg-id "${peer_drg_ocid}")
                REMOTE_PEER_CONNECTION=$(echo "$EXISTING_REMOTE_CONNECTIONS" | jq ".data[]|select(.\"display-name\" == \"$LOCAL_CLOUD\")")
                if [ -z "$REMOTE_PEER_CONNECTION" ]; then
                    echo "Creating new remote peer connection for local region $ORACLE_REGION in region $R"
                    REMOTE_PEER_CONNECTION=$(oci network remote-peering-connection create --display-name "$LOCAL_CLOUD" --region $R --compartment-id $COMPARTMENT_OCID --drg-id "${peer_drg_ocid}" --wait-for-state "AVAILABLE" | jq '.data')
                fi
                LOCAL_CONNECTION_OCID=$(echo "$LOCAL_PEER_CONNECTION" | jq -r ".id")
                REMOTE_CONNECTION_OCID=$(echo "$REMOTE_PEER_CONNECTION" | jq -r ".id")

                # now link remote and local peer
                echo "Linking remote region $R with local region $ORACLE_REGION"
                oci network remote-peering-connection connect --region $ORACLE_REGION --remote-peering-connection-id $LOCAL_CONNECTION_OCID --peer-id $REMOTE_CONNECTION_OCID --peer-region-name $R
            fi
        fi
    fi
done
