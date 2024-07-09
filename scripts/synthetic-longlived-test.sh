#!/bin/bash
set -x

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

echo "## starting synthetic-longlived-test.sh"

if [ -z "$BASE_URL" ]; then
    echo "## No BASE_URL found. Exiting..."
    exit 2
fi

if [ -z "$SELENIUM_HUB_URL" ]; then
    echo "## No SELENIUM_HUB_URL found. Exiting..."
    exit 2
fi

[ -z "$TEST_DURATION_MINUTES" ] && TEST_DURATION_MINUTES=5

if [ -z "$ENVIRONMENT" ]; then
  echo "## No ENVIRONMENT found. Exiting..."
  exit 2
fi

. $LOCAL_PATH/../clouds/all.sh
. $LOCAL_PATH/../clouds/oracle.sh
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

if [ -z "$TORTURE_GITHUB_USER" ]; then
  echo "## No TORTURE_GITHUB_USER found. Exiting..."
  exit 2
fi
  
if [ -z "$TORTURE_GITHUB_TOKEN" ]; then
  echo "## No TORTURE_GITHUB_TOKEN found. Exiting..."
  exit 2
fi

if [ -z "$WAVEFRONT_PROXY_URL" ]; then
  echo "## No WAVEFRONT_PROXY_URL found. Exiting..."
  exit 2
fi

if [ -x "$LOCAL_PATH/generate-client-token.sh" ]; then
  # generate a token if a client key file is defined
  if [ -n "$ASAP_CLIENT_SIGNING_KEY_FILE" ]; then
    TOKEN=$($LOCAL_PATH/generate-client-token.sh | tail -1)
  fi
fi

[ -z "$CLOUDWATCH_NAMESPACE" ] && CLOUDWATCH_NAMESPACE="Video"
[ -z "$CLOUDWATCH_DIMENSIONS" ] && CLOUDWATCH_DIMENSIONS="Environment=${ENVIRONMENT}"
[ -z "$CLOUDWATCH_REGION" ] && CLOUDWATCH_REGION="us-west-2"
  
SUCCESS=0

function doTest {
    set -x
    TENANT_URL=$1
    DURATION_MINUTES=$2

	((REPORT_ID=REPORT_ID+1))

	EXTRA_MVN_TARGETS=""

    if [[ $REPORT_ID == 1 ]]; then
        EXTRA_MVN_TARGETS="clean"
    fi
    [ -n "$REGIONAL_IP" ] && RESOLVER_PARAM="-DhostResolverRules=\"MAP $DOMAIN $REGIONAL_IP\"" || RESOLVER_PARAM=
	#set +x
    mvn -U ${EXTRA_MVN_TARGETS} test \
        -Djitsi-meet.instance.url="${TENANT_URL}" \
        -Dlonglived.duration=$DURATION_MINUTES \
        -Djitsi-meet.tests.toRun="SetupConference,LongLivedTest,DisposeConference" \
        -Dweb.participant1.isRemote=true \
        -Dweb.participant2.isRemote=true \
        -Dchrome.enable.headless=true \
        $RESOLVER_PARAM \
        -Dbrowser.owner=chrome -Dbrowser.second.participant=chrome \
        -Dremote.address="${SELENIUM_HUB_URL}" \
        -Dremote.resource.path=/usr/share/jitsi-meet-torture \
        -Dtest.report.directory=target/report${REPORT_ID} \
        -Dwdm.gitHubTokenName=$TORTURE_GITHUB_USER \
        -Dwdm.gitHubTokenSecret=$TORTURE_GITHUB_TOKEN \
        -Dorg.jitsi.token=$TOKEN
}

function pickRegion {
  [ -z "$BUILD_NUMBER" ] && BUILD_NUMBER=1
  [ -z "$SYNTHETIC_CLOUDS" ] && SYNTHETIC_CLOUDS="$RELEASE_CLOUDS"
  REGION_COUNT=$(echo $SYNTHETIC_CLOUDS | wc -w)
  REGION_INDEX=$(($BUILD_NUMBER % $REGION_COUNT + 1))
  SYNTHETIC_CLOUD=$(echo $SYNTHETIC_CLOUDS | cut -d' ' -f$REGION_INDEX)
  . $LOCAL_PATH/../clouds/$SYNTHETIC_CLOUD.sh
  echo $ORACLE_REGION
}

function getRegionalIP {
  REGION=$1
  dig +short "$ENVIRONMENT-$REGION-haproxy.$ORACLE_DNS_ZONE_NAME" | tail -1
}

# determine region
[ -n "$ORACLE_REGION" ] && SYNTHETIC_REGION="$ORACLE_REGION" || SYNTHETIC_REGION=`pickRegion`

[ -n "$SYNTHETIC_REGION" ] && REGIONAL_IP=`getRegionalIP $SYNTHETIC_REGION`

cd ../jitsi-meet-torture
CURRENT_COMMIT=$(git log -1 --format="%H")
echo "jitsi-meet-torture commit is at ${CURRENT_COMMIT}"

set +x
echo "------------------------------------------------------------------------------"
echo "- CONFERENCE WEB TEST AT ${BASE_URL} for ${TEST_DURATION_MINUTES} minutes"
echo "- Region: $SYNTHETIC_REGION ($REGIONAL_IP)"
echo "------------------------------------------------------------------------------"
echo ""

doTest "${BASE_URL}" $TEST_DURATION_MINUTES
SUCCESS=$?

# Only actually fail on two consecuative failures
if [[ $SUCCESS -ne 0 ]]; then
    sleep 15
    doTest "${BASE_URL}" $TEST_DURATION_MINUTES
    SUCCESS=$?
fi

if [[ $SUCCESS == 0 ]]; then
    CLOUDWATCH_VALUE=0
    set +x
    echo "------------------------------------------------------------------------"
    echo "- CONFERENCE WEB TEST SUCCESS"
    echo "------------------------------------------------------------------------"
    echo ""
else
    CLOUDWATCH_VALUE=1
    set +x
    echo "------------------------------------------------------------------------"
    echo "- CONFERENCE WEB TEST FAILURE"
    echo "------------------------------------------------------------------------"
    echo ""
fi

echo "jitsi_longlived_test_failure $CLOUDWATCH_VALUE source=jenkins-internal.jitsi.net environment=$ENVIRONMENT region=$CLOUDWATCH_REGION cloud=aws" | curl -s --data @- $WAVEFRONT_PROXY_URL

if [[ $SUCCESS == 0 ]]; then
	exit 0
fi

# no second failure skip
if [ ! -d target/report2 ] ; then
  exit 0;
fi

CURRENT_CONSOLE_LOG="${JENKINS_HOME}/jobs/${JOB_NAME}/builds/${BUILD_NUMBER}/log"

set +x
echo "------------------------------------------------------------------------"
echo "------------------------  FAILURE  -------------------------------------"
echo "------------------------------------------------------------------------"
echo ""

exit $SUCCESS
