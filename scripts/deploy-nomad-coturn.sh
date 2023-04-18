#!/bin/bash

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

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

[ -z "$ENCRYPTED_COTURN_CREDENTIALS_FILE" ] && ENCRYPTED_COTURN_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/coturn.yml"
TURNRELAY_PASSWORD_VARIABLE="coturn_secret"

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export NOMAD_VAR_coturn_auth_secret="$(ansible-vault view $ENCRYPTED_COTURN_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${TURNRELAY_PASSWORD_VARIABLE}" -)"

set -x

[ -z "$CERTIFICATE_NAME" ] && CERTIFICATE_NAME="star_jitsi_net-2023-08-19"
export NOMAD_VAR_ssl_cert_name="$CERTIFICATE_NAME"

[ -z "$DESIRED_CAPACITY" ] && DESIRED_CAPACITY=2
export NOMAD_VAR_coturn_count="$DESIRED_CAPACITY"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

#[ -z "$GRAFANA_HOSTNAME" ] && GRAFANA_HOSTNAME="$ENVIRONMENT-grafana.$TOP_LEVEL_DNS_ZONE_NAME"

#export NOMAD_VAR_grafana_hostname="$GRAFANA_HOSTNAME"
JOB_NAME="coturn-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/coturn.hcl" | nomad job run -var="dc=$NOMAD_DC" -
