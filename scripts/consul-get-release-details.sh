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

# per-release record (JSON) stored at release time
KV_KEY="releases/$ENVIRONMENT/$RELEASE_NUMBER/details"

[ -z "$OCI_LOCAL_REGION" ] && OCI_LOCAL_REGION="us-phoenix-1"
OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"
CONSUL_OCI_HOST="$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME"

OCI_CONSUL_URL="https://$CONSUL_OCI_HOST"
KV_JSON="$(curl -s $OCI_CONSUL_URL/v1/kv/$KV_KEY)"
if [[ $? -ne 0 ]]; then
    echo "## consul-get-release-details: failed to get release details from consul"
    exit 1
fi

# absent key -> consul returns an empty body; emit nothing and succeed so the
# caller can fall back (the details are optional metadata).
if [ -z "$KV_JSON" ] || [ "$KV_JSON" == "null" ]; then
    exit 0
fi

# the stored value is the JSON record, base64-encoded in the consul KV response
echo "$KV_JSON" | jq -r '.[0].Value' | base64 -d
