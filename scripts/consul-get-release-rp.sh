#!/bin/bash

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 1
fi

if [ -z "$RELEASE_NUMBER" ]; then
    echo "No RELEASE_NUMBER set, exiting"
    exit 1
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh

# per-release key where the RP ticket was stored at release time
KV_KEY="releases/$ENVIRONMENT/$RELEASE_NUMBER/rp"

[ -z "$OCI_LOCAL_REGION" ] && OCI_LOCAL_REGION="us-phoenix-1"
OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"
CONSUL_OCI_HOST="$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME"

OCI_CONSUL_URL="https://$CONSUL_OCI_HOST"
KV_JSON="$(curl -s $OCI_CONSUL_URL/v1/kv/$KV_KEY)"
if [[ $? -ne 0 ]]; then
    echo "## consul-get-release-rp: failed to get release RP from consul"
    exit 1
fi

# absent key -> consul returns an empty body; emit nothing and succeed so the
# caller can fall back (the RP is optional metadata).
if [ -z "$KV_JSON" ] || [ "$KV_JSON" == "null" ]; then
    exit 0
fi

RP_VALUE="$(echo $KV_JSON | jq -r '.[0].Value' | base64 -d)"

echo $RP_VALUE
