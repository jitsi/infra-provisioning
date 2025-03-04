#!/usr/bin/env bash

# make sure NVM is setup correctly
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

#set -x #echo on

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))
[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

# load oracle cloud defaults
[ -e $LOCAL_PATH/../clouds/oracle.sh ] && . $LOCAL_PATH/../clouds/oracle.sh

#default cloud if not set
[ -z $CLOUD_NAME ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh

SHARD=$2
if [ -z "$SHARD" ]; then
  echo "No SHARD found. Exiting..."
  exit 204
fi

#jenkins build number, we get it from jenkins
[ -z $BUILD_NUMBER ] && BUILD_NUMBER='N/A'

VAULT_KEY="$ENVIRONMENT/asap/validation-tests"

# login to vault to fetch the keypair
. $LOCAL_PATH/vault-login.sh

KEYPAIR_PATH="./keypair.json"
# fetch the keypair from vault
set +x
vault kv get -format=json -mount=secret $VAULT_KEY | jq -r '.data.data' > $KEYPAIR_PATH

JAAS_JWT_KID="$(jq -r '.key_id' $KEYPAIR_PATH)"
JAAS_WH_SHARED_SECRET="$(jq -r '.webhook_shared_secret' $KEYPAIR_PATH)"

JAAS_SIGNING_KEY_FILE=$(realpath "./jaas.key")

echo "Using JAAS_SIGNING_KEY_FILE: $JAAS_SIGNING_KEY_FILE"

jq -r '.private_key' $KEYPAIR_PATH | sed 's/\\n/\n/g' > $JAAS_SIGNING_KEY_FILE
rm $KEYPAIR_PATH

#https://web-cdn.jitsi.net/meet8x8com_4570.1272/
#https://web-cdn.jitsi.net/meetjitsi_4628.1277/
#https://web-cdn.jitsi.net/4679/
#set -x
# Extracts the jitsi-meet-web version used from the base.html file on the shard.
# Thew results can be:
# - https://web-cdn.jitsi.net/meet8x8com_4570.1272/ for 8x8 deployments
# - https://web-cdn.jitsi.net/meetjitsi_4628.1277/ for meet.jit.si
# - https://web-cdn.jitsi.net/4679/ for those without branding as beta.meet.jit.si
#
function getJitsiMeetTag() {
  SHARD_NAME=$1

  BASE_HTML=$(curl --silent --insecure https://${DOMAIN}/${SHARD_NAME}/base.html)
  WEB_FULL_VER=$(echo $BASE_HTML | sed 's|.*web-cdn.jitsi.net/||' | sed "s|.*${DOMAIN}/v1/_cdn/||" | sed 's|/".*||')
  WEB_VER=$(echo $WEB_FULL_VER | sed 's|.*_|| ' | sed 's|\..*||')

  echo "${WEB_VER}";
}

# generate a token if a client key file is defined
if [ -n "$ASAP_CLIENT_SIGNING_KEY_FILE" ]; then
  export JWT_ACCESS_TOKEN=$($LOCAL_PATH/generate-client-token.sh | tail -1)
fi

#first we set the shard state to "testing"
$LOCAL_PATH/set_shard_tested.py $ENVIRONMENT $SHARD testing $BUILD_NUMBER

#clean up results from any previous tests
rm -rf test-results
mkdir test-results

export TMPDIR=$(mktemp -d)
function cleanup() {
  rm -rf $TMPDIR
}
trap cleanup EXIT

set -x

pushd "$TMPDIR"

git clone https://github.com/jitsi/jitsi-meet.git

JITSI_MEET_BRANCH="$(getJitsiMeetTag $SHARD)"

pushd jitsi-meet

if [ -z "${TORTURE_BRANCH}" ]; then
  # Check if the release branch exists
  if git show-ref --verify --quiet "refs/heads/release-${JITSI_MEET_BRANCH}"; then
    echo "Branch '${JITSI_MEET_BRANCH}' exists. Checking out..."
    git checkout ${JITSI_MEET_BRANCH}
  else
    git checkout tags/${JITSI_MEET_BRANCH}
  fi
else
  git checkout "${TORTURE_BRANCH}"
fi
set +x
if [ -n "$JAAS_JWT_KID" ]; then
  export IFRAME_TENANT="$(echo "${JAAS_JWT_KID}" | cut -d'/' -f1)"
  export JWT_PRIVATE_KEY_PATH=$JAAS_SIGNING_KEY_FILE
  export JWT_KID="${JAAS_JWT_KID}"
  export WEBHOOKS_PROXY_URL="${WEBHOOKS_PROXY_URL}?tenant=${IFRAME_TENANT}"
  export WEBHOOKS_PROXY_SHARED_SECRET="${JAAS_WH_SHARED_SECRET}"
fi

nvm install
nvm use

node -v
npm -v
echo "Start npm install"
npm install
echo "Done npm install"
HEADLESS=true \
 GRID_HOST_URL="${GRID_URL}" \
 REMOTE_RESOURCE_PATH="/usr/share/jitsi-meet-torture/resources" \
 ALLOW_INSECURE_CERTS=true \
 BASE_URL="https://${DOMAIN}/70r7ur5/" \
 MAX_INSTANCES=4 \
 ROOM_NAME_SUFFIX="${SHARD}" \
 npm run test-grid
SUCCESS=$?
echo "Done testing"

popd
popd

mv $TMPDIR/jitsi-meet/test-results ../test-results/${SHARD}

if [[ $SUCCESS == 0 ]]; then
  $LOCAL_PATH/set_shard_tested.py $ENVIRONMENT $SHARD passed $BUILD_NUMBER
else
  $LOCAL_PATH/set_shard_tested.py $ENVIRONMENT $SHARD failed $BUILD_NUMBER
  echo "Torture test ansible run failed."
  exit 1
fi
