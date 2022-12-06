#!/usr/bin/env bash
set -x

# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

[ -z "$BUCKET_NAMESPACE" ] && export BUCKET_NAMESPACE="fr4eeztjonbe"

function create_bucket_if_not_present() {
  local bucket_name=$1
  local bucket_region=$2
  local bucket_compartment_ocid=$3
  local emit_object_events=$4
  local versioning_enabled=$5

  local existing_bucket_id=$(oci os bucket get --region $bucket_region -bn $bucket_name -ns $BUCKET_NAMESPACE | jq -r .data.id)
  if [ -z "$existing_bucket_id" ] || [ "$existing_bucket_id" == "null" ]; then
    echo "Creating bucket $bucket_name..."

    oci os bucket create --region $bucket_region --name $bucket_name -c $bucket_compartment_ocid -ns $BUCKET_NAMESPACE --object-events-enabled $emit_object_events --versioning $versioning_enabled

    if [ $? -gt 0 ]; then
      echo "Error while creating bucket $bucket_name. Exiting..."
      exit 210
    fi
  else
    echo "Bucket $bucket_name already exists and has id $existing_bucket_id. Skipping its creation."
  fi
}

function create_lifecycle_policy_if_not_present() {
  local bucket_name=$1
  local bucket_region=$2
  local policy_name=$3
  local time_amount=$4
  local time_unit=$5

  local policy_enabled=$(oci os object-lifecycle-policy get --region "$bucket_region" -bn "$bucket_name" -ns $BUCKET_NAMESPACE | jq '[.data.items[] | select(."name" == "'"$policy_name"'")][0] | ."is-enabled"' -r)

  if [ -z "$policy_enabled" ] || [ "$policy_enabled" == "null" ]; then
    echo "Creating lifecycle policy $policy_name..."

    policy_items='[{
            "action": "DELETE",
            "isEnabled": true,
            "name": "'"$policy_name"'",
            "timeAmount": '$time_amount',
            "timeUnit": "'"$time_unit"'"
            }]'
    oci os object-lifecycle-policy put --region "$bucket_region" --bucket-name "$bucket_name" -ns $BUCKET_NAMESPACE --items "$policy_items" --force

    if [ $? -gt 0 ]; then
      echo "Error while creating lifecycle policy $policy_name. Exiting..."
      exit 210
    fi
  else
    echo "Lifecycle policy $policy_name already exists and it is enabled $policy_enabled. Skipping its creation."
  fi
}

if [ -z $ENVIRONMENT ]; then
  echo "No ENVIRONMENT provided or found. Exiting..."
  exit 201
fi

[ -e "../all/clouds/oracle.sh" ] && . ../all/clouds/oracle.sh

# Get the compartment, which is the same for all regions in this env
DEFAULT_ORACLE_CLOUD_NAME="$DEFAULT_ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "../all/clouds/${DEFAULT_ORACLE_CLOUD_NAME}.sh" ] && . ../all/clouds/${DEFAULT_ORACLE_CLOUD_NAME}.sh

# e.g. 'us-phoenix-1 eu-amsterdam-1'
if [ -z "$ORACLE_REGIONS" ]; then
  echo "No ORACLE_REGIONS found. Exiting..."
  exit 203
fi

if [ -z "$COMPARTMENT_OCID" ]; then
  echo "No COMPARTMENT_OCID found. Exiting..."
  exit 203
fi

for ORACLE_REGION in $ORACLE_REGIONS; do
  # We create this bucket with emit object events until we deploy a failed recording recovery service
  BUCKET_NAME="failed-recordings-$ENVIRONMENT-$ORACLE_REGION"
  POLICY_NAME="failed-recordings-$ENVIRONMENT-$ORACLE_REGION-policy"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID false Disabled
  create_lifecycle_policy_if_not_present $BUCKET_NAME $ORACLE_REGION $POLICY_NAME 60 DAYS

  BUCKET_NAME="dropbox-failed-recordings-$ENVIRONMENT-$ORACLE_REGION"
  POLICY_NAME="dropbox-failed-recordings-$ENVIRONMENT-$ORACLE_REGION-policy"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID false Disabled
  create_lifecycle_policy_if_not_present $BUCKET_NAME $ORACLE_REGION $POLICY_NAME 1 DAYS

  BUCKET_NAME="images-$ENVIRONMENT"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID false Disabled

  BUCKET_NAME="jvb-images-$ENVIRONMENT"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID false Disabled

  BUCKET_NAME="jvb-bucket-$ENVIRONMENT"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID false Disabled

  BUCKET_NAME="dump-logs-$ENVIRONMENT"
  POLICY_NAME="dump-logs-$ENVIRONMENT-policy"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID true Disabled
  create_lifecycle_policy_if_not_present $BUCKET_NAME $ORACLE_REGION $POLICY_NAME 60 DAYS

  BUCKET_NAME="jvb-dump-logs-$ENVIRONMENT"
  POLICY_NAME="jvb-dump-logs-$ENVIRONMENT-policy"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID true Disabled
  create_lifecycle_policy_if_not_present $BUCKET_NAME $ORACLE_REGION $POLICY_NAME 60 DAYS

  BUCKET_NAME="tf-state-$ENVIRONMENT"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID false Enabled

  BUCKET_NAME="vpaas-recordings-$ENVIRONMENT-$ORACLE_REGION"
  POLICY_NAME="vpaas-recordings-$ENVIRONMENT-$ORACLE_REGION-policy"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID false Disabled
  create_lifecycle_policy_if_not_present $BUCKET_NAME $ORACLE_REGION $POLICY_NAME 1 DAYS

  BUCKET_NAME="vpaas-failed-recordings-$ENVIRONMENT-$ORACLE_REGION"
  POLICY_NAME="vpaas-failed-recordings-$ENVIRONMENT-$ORACLE_REGION-policy"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID false Disabled
  create_lifecycle_policy_if_not_present $BUCKET_NAME $ORACLE_REGION $POLICY_NAME 1 DAYS

  BUCKET_NAME="vpaas-segments-$ENVIRONMENT-$ORACLE_REGION"
  POLICY_NAME="vpaas-segments-$ENVIRONMENT-$ORACLE_REGION-policy"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID false Disabled
  create_lifecycle_policy_if_not_present $BUCKET_NAME $ORACLE_REGION $POLICY_NAME 1 DAYS

  BUCKET_NAME="vpaas-screenshots-$ENVIRONMENT-$ORACLE_REGION"
  POLICY_NAME="vpaas-screenshots-$ENVIRONMENT-$ORACLE_REGION-policy"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID false Disabled
  create_lifecycle_policy_if_not_present $BUCKET_NAME $ORACLE_REGION $POLICY_NAME 1 DAYS

  BUCKET_NAME="iperf-logs-$ENVIRONMENT"
  create_bucket_if_not_present $BUCKET_NAME $ORACLE_REGION $COMPARTMENT_OCID true Disabled
done
