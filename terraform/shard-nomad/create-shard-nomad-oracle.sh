#!/usr/bin/env bash
set -x
unset SSH_USER

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ROLE" ] && ROLE="core"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

[ -z "$SIGNAL_VERSION" ] && [ ! -z "$JICOFO_VERSION" ] && [ ! -z "$JITSI_MEET_VERSION" ] && SIGNAL_VERSION="${JICOFO_VERSION}-${JITSI_MEET_VERSION}"
[ -z "$SIGNAL_VERSION" ] && SIGNAL_VERSION='latest'

[ -z "$RELEASE_NUMBER" ] && RELEASE_NUMBER=0

[ -z "$VISITORS_ENABLED" ] && VISITORS_ENABLED="false"

#Default shard base name to environment name
[ -z "$SHARD_BASE" ] && SHARD_BASE=$ENVIRONMENT

#shard name ends up like: lonely-us-phoenix-1-s3
[ -z "$SHARD_NAME" ] && export SHARD_NAME="${SHARD_BASE}-${ORACLE_REGION}-s${SHARD_NUMBER}"

[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

CLOUD_NAME="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$NOMAD_LB_HOSTNAME" ] && NOMAD_LB_HOSTNAME="$ENVIRONMENT-$ORACLE_REGION-nomad-pool-$NOMAD_POOL_TYPE.$ORACLE_DNS_ZONE_NAME"

NOMAD_LB_IP=$(dig +short "$NOMAD_LB_HOSTNAME")

if [ $? -gt 0 ]; then
  echo "No Nomad LB IP found from $NOMAD_LB_HOSTNAME, exiting"
  exit 204
fi


RESOURCE_NAME_ROOT="$SHARD_NAME"

[ -z "$ALARM_PAGERDUTY_TOPIC_NAME" ] && ALARM_PAGERDUTY_TOPIC_NAME="${ENVIRONMENT}-PagerDutyTopic"
[ -z "$ALARM_EMAIL_TOPIC_NAME" ] && ALARM_EMAIL_TOPIC_NAME="${ENVIRONMENT}-topic"

[ -z "$ENABLE_PAGERDUTY_ALARMS" ] && ENABLE_PAGERDUTY_ALARMS="false"
[ -z "$ALARM_PAGERDUTY_ENABLED" ] && ALARM_PAGERDUTY_ENABLED="$ENABLE_PAGERDUTY_ALARMS"

# leave alarms disabled until shard is fully up
[ -z "$ALARM_INITIAL_ENABLED" ] && ALARM_INITIAL_ENABLED="false"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/shards/$SHARD_NAME/terraform.tfstate"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_CLI_ARGS=""
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="$LOCAL_PATH"
fi
#The —reconfigure option disregards any existing configuration, preventing migration of any existing state
terraform $TF_GLOBALS_CHDIR init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_STATE_KEY" \
  -backend-config="region=$ORACLE_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_ENDPOINT" \
  -reconfigure $TF_POST_PARAMS

[ -z "$ACTION" ] && ACTION="apply"

if [[ "$ACTION" == "apply" ]]; then
  ACTION_POST_PARAMS="-auto-approve"
fi
if [[ "$ACTION" == "import" ]]; then
  ACTION_POST_PARAMS="$1 $2"
fi

terraform $TF_GLOBALS_CHDIR $ACTION \
  -var="environment=$ENVIRONMENT" \
  -var="domain=$DOMAIN" \
  -var="release_number=$RELEASE_NUMBER" \
  -var="nomad_lb_ip=$NOMAD_LB_IP" \
  -var="shard=$SHARD_NAME" \
  -var="cloud_name=$CLOUD_NAME" \
  -var="name=$SHARD_NAME" \
  -var="oracle_region=$ORACLE_REGION" \
  -var="role=$ROLE" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="resource_name_root=$RESOURCE_NAME_ROOT" \
  -var="alarm_pagerduty_topic_name=$ALARM_PAGERDUTY_TOPIC_NAME" \
  -var="alarm_email_topic_name=$ALARM_EMAIL_TOPIC_NAME" \
  -var="alarm_pagerduty_is_enabled=$ALARM_PAGERDUTY_ENABLED" \
  -var="alarm_is_enabled=$ALARM_INITIAL_ENABLED" \
  -var="environment_type=$ENVIRONMENT_TYPE" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS

RET=$?

exit $RET
