#!/bin/bash

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$ENCRYPTED_OPS_REPO_CREDENTIALS_FILE" ] && ENCRYPTED_OPS_REPO_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/ops-repo.yml"
OPS_REPO_HTPASSWD_USERS_VARIABLE="ops_repo_htpasswd_users"
OPS_REPO_HOSTNAME_VARIABLE="ops_repo_hostname"

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export NOMAD_VAR_ops_repo_username="$(ansible-vault view $ENCRYPTED_OPS_REPO_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OPS_REPO_HTPASSWD_USERS_VARIABLE}[0].username" -)"
export NOMAD_VAR_ops_repo_password="$(ansible-vault view $ENCRYPTED_OPS_REPO_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OPS_REPO_HTPASSWD_USERS_VARIABLE}[0].password" -)"
export NOMAD_VAR_ops_repo_hostname="$(ansible-vault view $ENCRYPTED_OPS_REPO_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OPS_REPO_HOSTNAME_VARIABLE}" -)"
set -x


[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$ORACLE_REGION"

if [ -z "$NOMAD_ADDR" ]; then
    NOMAD_IPS="$(DATACENTER="$ENVIRONMENT-$LOCAL_REGION" OCI_DATACENTERS="$ENVIRONMENT-$LOCAL_REGION" ENVIRONMENT="$ENVIRONMENT" FILTER_ENVIRONMENT="false" SHARD='' RELEASE_NUMBER='' SERVICE="nomad-servers" DISPLAY="addresses" $LOCAL_PATH/consul-search.sh ubuntu)"
    if [ -n "$NOMAD_IPS" ]; then
        NOMAD_IP="$(echo $NOMAD_IPS | cut -d ' ' -f1)"
        export NOMAD_ADDR="http://$NOMAD_IP:4646"
    else
        echo "No NOMAD_IPS for in environment $ENVIRONMENT in consul"
        exit 5
    fi
fi

if [ -z "$NOMAD_ADDR" ]; then
    echo "Failed to set NOMAD_ADDR, exiting"
    exit 5
fi

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="ops-repo-$ORACLE_REGION"

export NOMAD_VAR_oracle_s3_namespace="$ORACLE_S3_NAMESPACE"
export NOMAD_VAR_oracle_region="$ORACLE_REGION"


sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/ops-repo.hcl" | nomad job run -var="dc=$NOMAD_DC" -
