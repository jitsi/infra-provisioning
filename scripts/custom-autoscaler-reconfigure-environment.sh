#!/bin/bash

set -x

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# reconfigures all relevant groups in an environment
# meant to be run after a new shard is created

[ -z "$AUTOSCALER_RECONFIGURATION_TRIGGER_ENABLED" ] && AUTOSCALER_RECONFIGURATION_TRIGGER_ENABLED="true"

# check if environment is meant to have reconfiguration enabled
if [[ "$AUTOSCALER_RECONFIGURATION_TRIGGER_ENABLED" != "true" ]]; then
    echo "Reconfiguration disabled for environment $ENVIRONMENT"
    echo "Set AUTOSCALER_RECONFIGURATION_TRIGGER_ENABLED=\"true\" to enable this"
    echo "Skipping gracefully."
    exit 0
fi

# first pull list of relevant groups: jvb, jibri and jigasi that have the reconfiguration flag enabled

JVB_GROUPS=$(GROUP_RECONFIGURATION_ENABLED="true" GROUP_TYPE="JVB" $LOCAL_PATH/custom-autoscaler-list-groups.sh)
JIBRI_GROUPS=$(GROUP_RECONFIGURATION_ENABLED="true" GROUP_TYPE="jibri" $LOCAL_PATH/custom-autoscaler-list-groups.sh)
JIGASI_GROUPS=$(GROUP_RECONFIGURATION_ENABLED="true" GROUP_TYPE="jigasi" $LOCAL_PATH/custom-autoscaler-list-groups.sh)

echo "JVBS: $JVB_GROUPS"
echo "JIBRIS: $JIBRI_GROUPS"
echo "JIGASIS: $JIGASI_GROUPS"

OVERALL_SUCCESS=true

for group in $JVB_GROUPS; do
    echo "Reconfiguring JVB group $group"
    GROUP_NAME="$group" $LOCAL_PATH/custom-autoscaler-reconfigure-group.sh
    if [ $? -gt 0 ]; then
        OVERALL_SUCCESS=false
        echo "Failed reconfigure JVB group $group"
    fi
done

for group in $JIBRI_GROUPS; do
    echo "Reconfiguring jibri group $group"
    GROUP_NAME="$group" $LOCAL_PATH/custom-autoscaler-reconfigure-group.sh
    if [ $? -gt 0 ]; then
        OVERALL_SUCCESS=false
        echo "Failed reconfigure jibri group $group"
    fi
done

for group in $JIGASI_GROUPS; do
    echo "Reconfiguring jigasi group $group"
    GROUP_NAME="$group" $LOCAL_PATH/custom-autoscaler-reconfigure-group.sh
    if [ $? -gt 0 ]; then
        OVERALL_SUCCESS=false
        echo "Failed reconfigure jigasi group $group"
    fi
done

if $OVERALL_SUCCESS; then
    echo "Reconfiguration success"
    exit 0
else
    echo "Reconfiguration had errors"
    exit 12
fi