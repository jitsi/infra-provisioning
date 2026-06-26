#!/bin/bash

[ -e ./stack-env.sh ] && . ./stack-env.sh

echo "## starting consul-set-release-rp.sh"

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 1
fi

if [ -z "$RELEASE_NUMBER" ]; then
    echo "No RELEASE_NUMBER set, exiting"
    exit 1
fi

if [ -z "$RP_TICKET" ]; then
    echo "No RP_TICKET set, exiting"
    exit 1
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh

# value pushed into the key value store: the RP ticket for this release
RELEASE_VALUE="$RP_TICKET"

# per-release key so the RP can be recovered later (e.g. at set-release-ga time).
# Written to the default datacenter of the OCI consul — the same single place
# consul-get-release-rp.sh reads from, so no multi-DC fan-out is needed.
KV_KEY="releases/$ENVIRONMENT/$RELEASE_NUMBER/rp"

[ -z "$OCI_LOCAL_REGION" ] && OCI_LOCAL_REGION="us-phoenix-1"
OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"
CONSUL_OCI_HOST="$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME"

OCI_CONSUL_URL="https://$CONSUL_OCI_HOST"
echo "## consul-set-release-rp: OCI_CONSUL_URL: $OCI_CONSUL_URL"

curl -sf -d"$RELEASE_VALUE" -X PUT "$OCI_CONSUL_URL/v1/kv/$KV_KEY"
if [[ $? -ne 0 ]]; then
    echo "## consul-set-release-rp: failed to set release RP in consul"
    exit 1
fi

exit 0
