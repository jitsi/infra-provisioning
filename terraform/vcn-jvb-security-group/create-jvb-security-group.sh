#!/bin/bash
if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

# e.g. /terraform/standalone
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

#set -x

# Create Security Groups
[ -z "$NAME_ROOT" ] && NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"

S3_STATE_BASE="$ENVIRONMENT/vcn-jvb-security-group"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="${S3_STATE_BASE}/terraform.tfstate"


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
  [ -z "$IMPORT_LOOKUP_FLAG" ] && IMPORT_LOOKUP_FLAG="true"
  if [ "$IMPORT_LOOKUP_FLAG" == "true" ]; then
    SECURITY_GROUP_OCID="$(oci network nsg list --compartment-id $COMPARTMENT_OCID --all --region $ORACLE_REGION --display-name $NAME_ROOT-JVBSecurityGroup | jq -r '.data[].id')"
    if [[ "$SECURITY_GROUP_OCID" == "null" ]]; then
        echo "No security group found, not automatically providing import parameters"
    else
        ACTION_POST_PARAMS="oci_core_network_security_group.jvb_network_security_group $SECURITY_GROUP_OCID"
        terraform $TF_GLOBALS_CHDIR $ACTION \
            -var="oracle_region=$ORACLE_REGION"\
            -var="tenancy_ocid=$TENANCY_OCID"\
            -var="compartment_ocid=$COMPARTMENT_OCID"\
            -var="environment=$ENVIRONMENT"\
            -var="vcn_name=$VCN_NAME"\
            -var="resource_name_root=$NAME_ROOT"\
            $ACTION_POST_PARAMS $TF_POST_PARAMS

        SECURITY_GROUP_RULES="$(oci network nsg rules list --nsg-id $SECURITY_GROUP_OCID --region $ORACLE_REGION)"
        if [[ $? -eq 0 ]]; then
            GROUP_LENGTH="$(echo "$SECURITY_GROUP_RULES" | jq -r '.data | length')"
            for i in $(seq 0 $(($GROUP_LENGTH - 1))); do
                echo "Rule $i: $(echo "$SECURITY_GROUP_RULES" | jq ".data[$i]")"
                RULE_ID="$(echo "$SECURITY_GROUP_RULES" | jq -r ".data[$i].id")"
                RULE_TYPE=
                EGRESS_RULE_ID="$(echo "$SECURITY_GROUP_RULES" | jq ".data[$i]" | jq -s '.[]|select(.direction == "EGRESS" and .destination == "0.0.0.0/0") | .id')"
                if [ -n "$EGRESS_RULE_ID" ]; then
                    RULE_TYPE="egress"
                fi
                HTTPS_RULE_ID="$(echo "$SECURITY_GROUP_RULES" | jq ".data[$i]" | jq -s '.[]|select(.direction == "INGRESS" and .source == "0.0.0.0/0" and ."tcp-options"."destination-port-range".max == 443) | .id')"
                if [ -n "$HTTPS_RULE_ID" ]; then
                    RULE_TYPE="https"
                fi

                MEDIA_RULE_ID="$(echo "$SECURITY_GROUP_RULES" | jq ".data[$i]" | jq -s '.[]|select(.direction == "INGRESS" and .source == "0.0.0.0/0" and ."udp-options"."destination-port-range".max == 10000) | .id')"
                if [ -n "$MEDIA_RULE_ID" ]; then
                    RULE_TYPE="media"
                fi

                SSH_RULE_ID="$(echo "$SECURITY_GROUP_RULES" | jq ".data[$i]" | jq -s '.[]|select(.direction == "INGRESS" and .source == "0.0.0.0/0" and ."tcp-options"."destination-port-range".max == 22) | .id')"
                if [ -n "$SSH_RULE_ID" ]; then
                    RULE_TYPE="ssh"
                fi

                if [ -n "$RULE_TYPE" ]; then
                    ACTION_POST_PARAMS="oci_core_network_security_group_security_rule.jvb_network_security_group_security_rule_$RULE_TYPE networkSecurityGroups/$SECURITY_GROUP_OCID/securityRules/$RULE_ID"

                    terraform $TF_GLOBALS_CHDIR $ACTION \
                        -var="oracle_region=$ORACLE_REGION"\
                        -var="tenancy_ocid=$TENANCY_OCID"\
                        -var="compartment_ocid=$COMPARTMENT_OCID"\
                        -var="environment=$ENVIRONMENT"\
                        -var="vcn_name=$VCN_NAME"\
                        -var="resource_name_root=$NAME_ROOT"\
                        $ACTION_POST_PARAMS $TF_POST_PARAMS
                else
                    echo "Found rule $RULE_ID with no known type, skipping"
                fi
            done
        else
            echo "No security group rules found, not automatically providing import parameters"
        fi
    fi
  else
    ACTION_POST_PARAMS="$1 $2"
  fi
else
  terraform $TF_GLOBALS_CHDIR $ACTION \
    -var="oracle_region=$ORACLE_REGION"\
    -var="tenancy_ocid=$TENANCY_OCID"\
    -var="compartment_ocid=$COMPARTMENT_OCID"\
    -var="environment=$ENVIRONMENT"\
    -var="vcn_name=$VCN_NAME"\
    -var="resource_name_root=$NAME_ROOT"\
    $ACTION_POST_PARAMS $TF_POST_PARAMS
fi
