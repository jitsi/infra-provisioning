#!/bin/bash

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

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


[ -z $AZ_REGION ] && AZ_REGION=$EC2_REGION

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

ROUTE_TABLE_NAME="Route Table ${VCN_NAME}"
route_table_details=$(oci network route-table list --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --vcn-id "${vcn_id}" --display-name "${ROUTE_TABLE_NAME}" --all)
route_table_id="$(echo "$route_table_details" | jq -r '.data[0].id')"
main_route_table_rules=$(echo "$route_table_details" | jq -r '.data[0]."route-rules"')
existing_table_rules="$main_route_table_rules"

###Update the Private Route Table rules
PRIVATE_ROUTE_TABLE_NAME="Private Route Table ${VCN_NAME}"
private_route_table_details=$(oci network route-table list --region "$ORACLE_REGION" --compartment-id "${COMPARTMENT_OCID}" --vcn-id "${vcn_id}" --display-name "${PRIVATE_ROUTE_TABLE_NAME}" --all)
private_route_table_id="$(echo "$private_route_table_details" | jq -r '.data[0].id')"
private_route_table_rules=$(echo "$private_route_table_details" | jq -r '.data[0]."route-rules"')
existing_private_table_rules="$private_route_table_rules"


function check_add_cidr () {
    drg=$1
    cidr=$2
    rules="$3"


    ###Update the Route Table rules
    drg_route_rule='[
    {
    "network_entity_id": "'$drg'",
    "destination": "'$cidr'",
    "destination_type": "CIDR_BLOCK"
    }
    ]'

    check_drg_rule=$(echo "$rules" | jq -r ".[] | select(.destination==\"${cidr}\") | .destination")
    if [ -z "$check_drg_rule" ]; then
        echo "Will update the route table $table"
        new_route_table_rules=$(echo "$rules" | jq -r '. |= . + '"$drg_route_rule"'')
    else
        echo "The route table already has a rule with destination $AWS_VPC_CIDR"
        new_route_table_rules="$rules"
    fi
}

for cidr in $CIDRS; do

    echo "Check route tables for CIDR: $cidr"

    # main route
    check_add_cidr $drg_ocid $cidr "$main_route_table_rules"
    main_route_table_rules="$new_route_table_rules"

    # # private routes
    check_add_cidr $drg_ocid $cidr "$private_route_table_rules"
    private_route_table_rules="$new_route_table_rules"
done

if [[ "$existing_route_table_rules" != "$main_route_table_rules" ]]; then
    echo "NEW MAIN ROUTE TABLE $main_route_table_rules"
    oci network route-table update --region "$ORACLE_REGION" --rt-id="${route_table_id}" --route-rules="${main_route_table_rules}" --force
else
    echo "MAIN ROUTE TABLE UNCHANGED"
fi

if [[ "$existing_private_table_rules" != "$private_route_table_rules" ]]; then
    echo "NEW PRIVATE ROUTE TABLE $private_route_table_rules"
    oci network route-table update --region "$ORACLE_REGION" --rt-id="${private_route_table_id}" --route-rules="${private_route_table_rules}" --force
else
    echo "PRIVATE ROUTE TABLE UNCHANGED"
fi