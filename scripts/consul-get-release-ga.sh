#!/bin/bash

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 1
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh

# string path where value is stored, combined with 
KV_KEY="releases/$ENVIRONMENT/live"

[ -z "$OCI_LOCAL_REGION" ] && OCI_LOCAL_REGION="us-phoenix-1"
OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"
CONSUL_OCI_HOST="$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME"

OCI_CONSUL_URL="https://$CONSUL_OCI_HOST"
KV_JSON="$(curl -s $OCI_CONSUL_URL/v1/kv/$KV_KEY)"
if [[ $? -ne 0 ]]; then
    echo "## consul-get-release-ga: failed to get release from consul"
    exit 1
fi
RELEASE_VALUE="$(echo $KV_JSON | jq -r '.[0].Value' | base64 -d)"

# now remove 'release-' from the beginning of the string
RELEASE_NUMBER="${RELEASE_VALUE:8}"

echo $RELEASE_NUMBER