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

[ -f ./sites/$ENVIRONMENT/test-expectations.json ] && export EXPECTATIONS=$(realpath ./sites/$ENVIRONMENT/test-expectations.json)

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

# The 8x8 meeting-settings e2e spec (sourced from the jitsi-meet-branding repo) only runs in
# the 8x8 environments, where the test accounts and the settings backend exist.
RUN_MEET_SETTINGS=false
case "$ENVIRONMENT" in
  stage-8x8|prod-8x8) RUN_MEET_SETTINGS=true ;;
esac

# Location of the checked-out jitsi-meet-branding repo (checked out by the Jenkins job next to
# infra-provisioning); override with BRANDING_PATH for local runs.
[ -z "$BRANDING_PATH" ] && BRANDING_PATH="$LOCAL_PATH/../../jitsi-meet-branding"

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

# Pull the 8x8 meeting-settings test credentials out of the same vault keypair (under a
# "meet_settings" object). Only needed for the 8x8 environments; disable the spec if absent.
if [ "$RUN_MEET_SETTINGS" = "true" ]; then
  export SSO_URL="$(jq -r '.meet_settings.sso_url // empty' $KEYPAIR_PATH)"
  export JITSI_TOKEN_SERVICE_URL="$(jq -r '.meet_settings.jitsi_token_service_url // empty' $KEYPAIR_PATH)"
  export ASAP_TOKEN="$(jq -r '.meet_settings.asap_token // empty' $KEYPAIR_PATH)"
  export ASAP_COOKIE="$(jq -r '.meet_settings.asap_cookie // empty' $KEYPAIR_PATH)"
  export SETTINGS_USERNAME_1="$(jq -r '.meet_settings.users[0].username // empty' $KEYPAIR_PATH)"
  export SETTINGS_PASSWORD_1="$(jq -r '.meet_settings.users[0].password // empty' $KEYPAIR_PATH)"
  export SETTINGS_USERNAME_2="$(jq -r '.meet_settings.users[1].username // empty' $KEYPAIR_PATH)"
  export SETTINGS_PASSWORD_2="$(jq -r '.meet_settings.users[1].password // empty' $KEYPAIR_PATH)"
  export SETTINGS_USERNAME_3="$(jq -r '.meet_settings.users[2].username // empty' $KEYPAIR_PATH)"
  export SETTINGS_PASSWORD_3="$(jq -r '.meet_settings.users[2].password // empty' $KEYPAIR_PATH)"

  if [ -z "$SSO_URL" ] || [ -z "$ASAP_TOKEN" ] || [ -z "$SETTINGS_USERNAME_1" ]; then
    echo "No meet_settings credentials in vault keypair for $ENVIRONMENT; skipping meeting-settings spec"
    RUN_MEET_SETTINGS=false
  fi
fi

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

function getRegionalIP {
  REGION=$1
  dig +short "$ENVIRONMENT-$REGION-haproxy.$ORACLE_DNS_ZONE_NAME" | tail -1
}

TESTS_TENANT="70r7ur5"

# generate a token if a client key file is defined
if [ -n "$ASAP_CLIENT_SIGNING_KEY_FILE" ]; then
  export JWT_ACCESS_TOKEN=$($LOCAL_PATH/generate-client-token.sh ${TESTS_TENANT} | tail -1)
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

#set -x

pushd "$TMPDIR"

git clone https://github.com/jitsi/jitsi-meet.git

JITSI_MEET_BRANCH="$(getJitsiMeetTag $SHARD)"

pushd jitsi-meet

if [ -z "${TORTURE_BRANCH}" ]; then
  # Check if the release branch exists
  if git show-ref --verify --quiet "refs/remotes/origin/release-${JITSI_MEET_BRANCH}"; then
    echo "Branch '${JITSI_MEET_BRANCH}' exists. Checking out..."
    git checkout "release-${JITSI_MEET_BRANCH}"
  else
    git checkout tags/${JITSI_MEET_BRANCH}
  fi
else
  git checkout "${TORTURE_BRANCH}"
fi

if [ -n "$JAAS_JWT_KID" ]; then
  export IFRAME_TENANT="$(echo "${JAAS_JWT_KID}" | cut -d'/' -f1)"
  export JWT_PRIVATE_KEY_PATH=$JAAS_SIGNING_KEY_FILE
  export JWT_KID="${JAAS_JWT_KID}"
  export WEBHOOKS_PROXY_URL="${WEBHOOKS_PROXY_URL}"
  export WEBHOOKS_PROXY_SHARED_SECRET="${JAAS_WH_SHARED_SECRET}"
fi

nvm install
nvm use

node -v
npm -v
echo "Start npm install"
npm install
echo "Done npm install"

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

SHARD_REGION=$(ENVIRONMENT="$ENVIRONMENT" SHARD="$SHARD" $LOCAL_PATH/shard.sh shard_region)
# presume any shards with no region in the name are in the local region
[ -z "$SHARD_REGION" ] && SHARD_REGION="$LOCAL_REGION"

[ -e $LOCAL_PATH/../clouds/${SHARD_REGION}-${ENVIRONMENT}-oracle.sh ] && . $LOCAL_PATH/../clouds/${SHARD_REGION}-${ENVIRONMENT}-oracle.sh

if [ -n "${VOX_ACCOUNT_ID}" ]; then
  REF_IP="$(getRegionalIP "${JIGASI_DIAL_OUT_REGION}")"
  export DIAL_IN_REST_URL="https://api.voximplant.com/platform_api/StartScenarios/?account_id=${VOX_ACCOUNT_ID}&api_key=${VOX_API_KEY}&reference_ip=${REF_IP}&rule_id=${VOX_HEALTH_CHECK_IN_RULE_ID}&script_custom_data=%7B%22pin%22%3A%22{0}%22%7D"
  export DIAL_OUT_URL="${VOX_DIAL_OUT_URL}"
  export SIP_JIBRI_DIAL_OUT_URL="${VIDEO_DIAL_OUT_URL}"
  export YTUBE_TEST_STREAM_KEY="${TEST_YTUBE_TEST_STREAM_KEY}"
  export YTUBE_TEST_BROADCAST_ID="${TEST_YTUBE_TEST_BROADCAST_ID}"
fi

# For the 8x8 environments, add the meeting-settings spec from the branding repo so the grid
# run below includes it. The spec maps onto tests/specs/8x8/ and resolves the jitsi-meet test
# framework via its relative imports.
if [ "$RUN_MEET_SETTINGS" = "true" ]; then
  if [ -d "$BRANDING_PATH/meet-8x8-com/tests/specs" ]; then
    echo "Adding 8x8 meeting-settings spec from $BRANDING_PATH"
    cp -a "$BRANDING_PATH/meet-8x8-com/tests/specs/." tests/specs/

    # Settings page differs per environment type (stage -> pilot, prod -> prod); the spec
    # derives the API hosts from it.
    if [ "$ENVIRONMENT_TYPE" = "stage" ]; then
      export MEETING_SETTINGS_PAGE="https://settings-pilot.8x8.vc"
    else
      export MEETING_SETTINGS_PAGE="https://settings.8x8.vc"
    fi

    # Fetch the SSO + Jitsi tokens for the three test users into the environment.
    if ! . "$BRANDING_PATH/meet-8x8-com/tests/fetch-settings-test-tokens.sh"; then
      echo "Failed to fetch meeting-settings test tokens"
      exit 1
    fi
  else
    echo "Branding tests not found at $BRANDING_PATH; skipping meeting-settings spec"
  fi
fi

HEADLESS=true \
 GRID_HOST_URL="${GRID_URL}" \
 REMOTE_RESOURCE_PATH="/usr/share/jitsi-meet-torture/resources" \
 ALLOW_INSECURE_CERTS=true \
 BASE_URL="https://${DOMAIN}/${TESTS_TENANT}/" \
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
