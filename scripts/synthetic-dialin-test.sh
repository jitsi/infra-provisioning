#!/bin/bash

set +x

# make sure NVM is setup correctly
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

echo "## starting synthetic-dialin-test.sh"

if [ -z "$BASE_URL" ]; then
    echo "## No BASE_URL found. Exiting..."
    exit 2
fi

if [ -z "$SELENIUM_HUB_URL" ]; then
    echo "## No SELENIUM_HUB_URL found. Exiting..."
    exit 2
fi

if [ -z "$ENVIRONMENT" ]; then
  echo "## No ENVIRONMENT found. Exiting..."
  exit 2
fi

. $LOCAL_PATH/../clouds/all.sh
. $LOCAL_PATH/../clouds/oracle.sh
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

VAULT_KEY="$ENVIRONMENT/asap/dial-in-tests"

# login to vault to fetch the keypair
. $LOCAL_PATH/vault-login.sh

KEYPAIR_PATH="./keypair.json"
# fetch the keypair from vault
set +x
vault kv get -format=json -mount=secret $VAULT_KEY | jq -r '.data.data' > $KEYPAIR_PATH

JAAS_JWT_KID="$(jq -r '.key_id' $KEYPAIR_PATH)"
JAAS_SIGNING_KEY_FILE=$(realpath "./jaas.key")

echo "Using JAAS_SIGNING_KEY_FILE: $JAAS_SIGNING_KEY_FILE"

jq -r '.private_key' $KEYPAIR_PATH | sed 's/\\n/\n/g' > $JAAS_SIGNING_KEY_FILE
rm $KEYPAIR_PATH

[ -z "$CLOUDWATCH_NAMESPACE" ] && CLOUDWATCH_NAMESPACE="Video"
[ -z "$CLOUDWATCH_DIMENSIONS" ] && CLOUDWATCH_DIMENSIONS="Environment=${ENVIRONMENT}"
[ -z "$CLOUDWATCH_REGION" ] && CLOUDWATCH_REGION="us-west-2"

SUCCESS=0

TEST_OUTPUT_LOG_US="test_log_US.txt"
TEST_OUTPUT_LOG_EU="test_log_EU.txt"
ACCOUNT_ID_US="2916850"
ACCOUNT_ID_EU="2697050"

function doTest {
  ACC_ID=$1
  API_KEY=$2
  RULE_ID=$3
  ADDR=$4
  REF_IP=$5
  LOG_FILE=$6

  REMOTE_RESOURCE_PATH='/usr/share/jitsi-meet-torture/resources' \
    GRID_HOST_URL=${SELENIUM_HUB_URL} \
    HEADLESS=true \
    DIAL_IN_REST_URL="https://api.voximplant.com/platform_api/StartScenarios/?account_id=${ACC_ID}&api_key=${API_KEY}&reference_ip=${REF_IP}&rule_id=${RULE_ID}&script_custom_data=%7B%22pin%22%3A%22{0}%22%7D" \
    JWT_PRIVATE_KEY_PATH=$JAAS_SIGNING_KEY_FILE \
    JWT_KID=$JAAS_JWT_KID \
    BASE_URL=https://${ADDR}/$(echo "$JAAS_JWT_KID" | cut -f1 -d"/")/ \
  npm run test-grid-single tests/specs/alone/dialInAudio.spec.ts | tee -a ${LOG_FILE}

  return ${PIPESTATUS[0]}
}

function getRegionalIP {
  REGION=$1
  dig +short "$ENVIRONMENT-$REGION-haproxy.$ORACLE_DNS_ZONE_NAME" | tail -1
}

cd ../jitsi-meet
CURRENT_COMMIT=$(git log -1 --format="%H")
echo "jitsi-meet commit is at ${CURRENT_COMMIT}"

rm -rf test-results1 test-results2
rm -f $TEST_OUTPUT_LOG_US
rm -f $TEST_OUTPUT_LOG_EU

nvm install
nvm use

echo "node version:$(node -v)"
echo "npm version:$(npm -v)"

npm install

echo "------------------------------------------------------------------------"
echo "--------TESTING in US vox account (team-us@jitsi.org)-------------------"
echo "------------------------------------------------------------------------"
echo ""
doTest "$ACCOUNT_ID_US" "${VOX_API_KEY_US}" "400932" "$DOMAIN" "$(getRegionalIP "us-phoenix-1")" $TEST_OUTPUT_LOG_US
SUCCESS=$?
mv test-results test-results1

# Only actually fail on two consecutive failures
if [[ $SUCCESS -ne 0 ]]; then
  echo "Waiting for 60 seconds..."
  sleep 60
  doTest "$ACCOUNT_ID_US" "${VOX_API_KEY_US}" "400932" "$DOMAIN" "$(getRegionalIP "us-phoenix-1")" $TEST_OUTPUT_LOG_US
  SUCCESS=$?
  mv test-results test-results2
fi

if [[ $SUCCESS == 0 ]]; then
  FAILED_VALUE=0
else
  FAILED_VALUE=1
  echo "------------------------------------------------------------------------"
  echo "--------FAILURE in US vox account (team-us@jitsi.org)-------------------"
  echo "------------------------------------------------------------------------"
  echo ""
fi

# Now let's test EU if US is successful
if [[ $FAILED_VALUE == 0 ]]; then
    echo "------------------------------------------------------------------------"
    echo "-----------TESTING in EU vox account (team@jitsi.org)-------------------"
    echo "------------------------------------------------------------------------"
    echo ""
    doTest "$ACCOUNT_ID_EU" "${VOX_API_KEY_EU}" "3460923" "frankfurt.$DOMAIN" "$(getRegionalIP "eu-frankfurt-1")" $TEST_OUTPUT_LOG_EU
    SUCCESS=$?
    rm -rf test-results1
    mv test-results test-results1

    # Only actually fail on two consecutive failures
    if [[ $SUCCESS -ne 0 ]]; then
	    echo "Waiting for 90 seconds..."
        sleep 90
        doTest "$ACCOUNT_ID_EU" "${VOX_API_KEY_EU}" "3460923" "frankfurt.$DOMAIN" "$(getRegionalIP "eu-frankfurt-1")" $TEST_OUTPUT_LOG_EU
        SUCCESS=$?
        mv test-results test-results2
    fi

    if [[ $SUCCESS == 0 ]]; then
        FAILED_VALUE=0
    else
        FAILED_VALUE=1

        echo "------------------------------------------------------------------------"
        echo "-----------FAILURE in EU vox account (team@jitsi.org)-------------------"
        echo "------------------------------------------------------------------------"
        echo ""
    fi
fi

rm $JAAS_SIGNING_KEY_FILE

if grep -q "java.lang.AssertionError: Error sending REST request:Read timed out" ${TEST_OUTPUT_LOG_US} || grep -q "java.lang.AssertionError: Error sending REST request:Read timed out" ${TEST_OUTPUT_LOG_EU}; then
  # We want to skip any random failures to access REST API to page, if two consequative happen we will page
  # So we skip this ... but the test will still fail and we will see it in Slack
  FAILED_VALUE=1
fi

# uncomment to disable paging; or set ENABLE_PAGE to default to "false" in the jenkins job configuraiton
# ENABLE_PAGE="false"

# emit metrics to statsd on telegraf to send to prometheus
if [[ "$ENABLE_PAGE" != "true" ]]; then
  echo "PAGING DISABLED - emitting negative 1"
  echo -n "jitsi.jigasi.dialin.test.failure:-1|g|#test_env:prod-8x8" | nc -4u -w1 ops-prod-jenkins-internal.oracle.infra.jitsi.net 8125
else
  echo "here we page"
  echo -n "jitsi.jigasi.dialin.test.failure:${FAILED_VALUE}|g|#test_env:prod-8x8" | nc -4u -w1 ops-prod-jenkins-internal.oracle.infra.jitsi.net 8125
fi

if [[ $SUCCESS == 0 ]]; then
  exit 0
fi

# no second failure skip
if [ ! -d test-results2 ] ; then
  exit 0;
fi

echo "------------------------------------------------------------------------"
echo "-----------------------FAILURE CAUSE------------------------------------"
echo "------------------------------------------------------------------------"
echo ""

function print_shutdown_instructions() {
  echo "Check the voximplant log which is that jigasi (search for 'username = ') and ssh and check its logs."
  echo "You can also check the calls of that jigasi here https://manage.voximplant.com/application/4252352/calls"
  echo "by selecting for rules 'confmap-prod' and for a number like 'prod-8x8_us-west-2_19_102' and if all"
  echo "latest calls or most of them you see had Failed, then put that jigasi in graceful shutdown so it is"
  echo "not used anymore by executing /usr/share/jigasi/graceful_shutdown.sh as root."
  echo "The script will continue its execution till there are no conferences (can be few hours) and there will"
  echo "be a dump so we can check it later."
  echo ""
  echo "If anything goes wrong with the steps above page damencho."
}

function print_vox_log() {
  LOG_FILE=$1

  if [ ! -f $LOG_FILE ]; then
      return;
  fi

  ACC_ID=$2
  API_KEY=$3

  echo ""
  HISTORY_ID=`cat ${LOG_FILE} | grep dial-in.test.call_session_history_id | cut -d ":" -f2-`
  for id in $HISTORY_ID; do
    echo "Voximplant log START ********* $id"
      LOG_FILE_URL=`curl --silent "https://api.voximplant.com/platform_api/GetCallHistory/?account_id=${ACC_ID}&call_session_history_id=${id}&api_key=${API_KEY}" | jq --raw-output '.result[0].log_file_url'`
      curl -s $LOG_FILE_URL;
      echo "Voximplant log END *************************************************************"
  done
}

function checkLogs() {
  LOG_FILE=$1

  if [ ! -f $LOG_FILE ]; then
      return;
  fi

  ACC_ID=$2
  API_KEY=$3

  if grep -q dial-in.test.no-pin ${LOG_FILE}; then
    echo "No pin was found for the conference."
      echo "Page Cluj or ask in meeting HQ room in VOD - it can be a deployment of the conference mapper at this moment".
  elif grep -q dial-in.test.restAPI.request.fail ${LOG_FILE}; then
    echo "Executing voximplant REST API fails, the failure code is visible in the console log above."
      echo "Check voximplant status page https://status.voximplant.com/ for outage of the API."
      echo "If problem persists after retrying in few minutes - send an email to support@voximplant.com and notify NOC they have a direct contact to page vox."
  elif grep -q dial-in.test.jigasi.participant.no.join.for ${LOG_FILE}; then
    echo "Jigasi did not join the call for some reason look at the voximplant log below:"
    echo "- it can be conference mapper returning error, then page Cluj"
      echo "- it can be the password service/(conference check url), then page Cluj ^"
      echo "- it can be the jigasi selector. If jigasi selector is returning 504 or other error means there is no healthy jigasi or we cannot choose any, page Aaron."
    echo ""
    echo "- or it can be that jigasi instance having problems"
    print_shutdown_instructions
  elif grep -q dial-in.test.jigasi.participant.no.audio.after.join.for ${LOG_FILE}; then
    echo "Problem establishing the jingle call media path."
      print_shutdown_instructions
  else
    echo "We haven't seen this, if retry is not fixing the problem and you cannot figure it out, page damencho."
  fi

  print_vox_log $LOG_FILE $ACC_ID $API_KEY
}

checkLogs $TEST_OUTPUT_LOG_US $ACCOUNT_ID_US $VOX_API_KEY_US
checkLogs $TEST_OUTPUT_LOG_EU $ACCOUNT_ID_EU $VOX_API_KEY_EU

echo ""
echo "------------------------------------------------------------------------"
echo "------------------------------------------------------------------------"

exit $SUCCESS

