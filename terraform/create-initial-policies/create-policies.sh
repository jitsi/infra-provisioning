set -x #echo on

# e.g. terraform/compartment/
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#pull in cloud-specific variables, e.g. tenancy
. $LOCAL_PATH/../../../clouds/oracle.sh

if [ -z "$COMPARTMENT_NAME" ]; then
  echo "No COMPARTMENT_NAME found.  Exiting..."
  exit 1
fi

if [ -z "$COMPARTMENT_OCID" ]; then
  echo "No COMPARTMENT_OCID found.  Exiting..."
  exit 2
fi

DYNAMIC_GROUP_NAME="$COMPARTMENT_NAME-dynamic-group"
POLICY_NAME="$COMPARTMENT_NAME-policy"

rm -f terraform.tfstate


TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="$LOCAL_PATH"
fi

# The —reconfigure option disregards any existing configuration, preventing migration of any existing state
terraform $TF_GLOBALS_CHDIR init $TF_POST_PARAMS

[ -z "$ACTION" ] && ACTION="apply"

if [[ "$ACTION" == "apply" ]]; then
  ACTION_POST_PARAMS="-auto-approve"
fi
if [[ "$ACTION" == "import" ]]; then
  ACTION_POST_PARAMS="$1 $2"
fi

terraform $TF_GLOBALS_CHDIR $ACTION \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_name=$COMPARTMENT_NAME" \
  -var="dynamic_group_name=$DYNAMIC_GROUP_NAME" \
  -var="compartment_id=$COMPARTMENT_OCID" \
  -var="policy_name=$POLICY_NAME" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
