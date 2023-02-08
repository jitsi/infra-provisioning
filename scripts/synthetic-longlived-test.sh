#!/bin/bash
set -x

echo "## starting synthetic-longlived-test.sh"

if [ -z "$BASE_URL" ]; then
    echo "## No BASE_URL found. Exiting..."
    exit 2
fi

TEST_BASE_URL=${BASE_URL}$(od -vN "16" -An -tx1 /dev/urandom | tr -d " \n"; echo)

if [ -z "$SELENIUM_HUB_URL" ]; then
    echo "## No SELENIUM_HUB_URL found. Exiting..."
    exit 2
fi

[ -z "$TEST_DURATION_MINUTES" ] && TEST_DURATION_MINUTES=5

if [ -z "$ENVIRONMENT" ]; then
  echo "## No ENVIRONMENT found. Exiting..."
  exit 2
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

[ -z "$TORTURE_TEST_REPO" ] && TORTURE_TEST_REPO=git@github.com:jitsi/jitsi-meet-torture.git
[ -z "$TORTURE_TEST_BRANCH" ] && TORTURE_TEST_BRANCH=master

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

[ -z "$CLOUDWATCH_NAMESPACE" ] && CLOUDWATCH_NAMESPACE="Video"
[ -z "$CLOUDWATCH_DIMENSIONS" ] && CLOUDWATCH_DIMENSIONS="Environment=${ENVIRONMENT}"
[ -z "$CLOUDWATCH_REGION" ] && CLOUDWATCH_REGION="us-west-2"
  
SUCCESS=0

# Extracts the jitsi-meet-web version used from the base.html file on the shard.
#
# with jitsi-meet-web version we check all available meta packages from the newest
# to the latest for that web version and when we find that one we use the meta
# version to construct the tag to use for jitsi-meet-torture
function getJitsiMeetTortureTag {
  BASE_HTML=$(curl --silent --insecure ${BASE_URL}/base.html)
  WEB_FULL_VER=$(echo $BASE_HTML | sed 's|.*web-cdn.jitsi.net/||' | sed 's|/".*||')
  WEB_VER=$(echo $WEB_FULL_VER | sed 's|.*_|| ' | sed 's|\..*||')

  set +x -a 	
  JITSI_MEET_VERSIONS=$(apt-cache madison jitsi-meet| sort -r | awk '{print $3;}' | cut -d'-' -f1,2,3)
  for item in $JITSI_MEET_VERSIONS
  do
      current_ver=$(apt-cache show jitsi-meet=$item | grep '^Depends:'  | cut -f2- -d: | cut -f2 -d,)
      if grep -q ".${WEB_VER}-1" <<< "$current_ver"; then
          #jitsi-meet-web version ${WEB_VER} is in jitsi-meet (meta) $item
          BUILD_NUM=$(echo $item | sed -n "s/[0-9]*\.[0-9]*\.\([0-9]*\)-1/\1/p")
          #"The tag is jitsi-meet_${BUILD_NUM}"
          echo "jitsi-meet_${BUILD_NUM}";
          break
      fi
  done
  set -x +a
  [ -z "$BUILD_NUM" ] && echo "master";
}

echo "End checking versions"

function doTest {
    TENANT_URL=$1
    DURATION_MINUTES=$2

	((REPORT_ID=REPORT_ID+1))

	EXTRA_MVN_TARGETS=""

    if [[ $REPORT_ID == 1 ]]; then
        EXTRA_MVN_TARGETS="clean"
    fi
    
	set +x
    mvn -U ${EXTRA_MVN_TARGETS} test \
        -Djitsi-meet.instance.url="${TENANT_URL}" \
        -Dlonglived.duration=$DURATION_MINUTES \
        -Djitsi-meet.tests.toRun="SetupConference,LongLivedTest,DisposeConference" \
        -Dweb.participant1.isRemote=true \
        -Dweb.participant2.isRemote=true \
        -Dchrome.enable.headless=true \
        -Dbrowser.owner=chrome -Dbrowser.second.participant=chrome \
        -Dremote.address="${SELENIUM_HUB_URL}" \
        -Dremote.resource.path=/usr/share/jitsi-meet-torture \
        -Dtest.report.directory=target/report${REPORT_ID} \
        -Dwdm.gitHubTokenName=$TORTURE_GITHUB_USER \
        -Dwdm.gitHubTokenSecret=$TORTURE_GITHUB_TOKEN
}

cd jitsi-meet-torture
# clean all local branches
git branch | grep -vx '* master' | xargs -r -n 1 git branch -D || true
# update
git fetch
git reset --hard origin/$TORTURE_TEST_BRANCH

set +x
echo "------------------------------------------------------------------------------"
echo "- CONFERENCE WEB TEST AT ${TEST_BASE_URL} for ${TEST_DURATION_MINUTES} minutes"
echo "------------------------------------------------------------------------------"
echo ""

doTest "${TEST_BASE_URL}" $TEST_DURATION_MINUTES
SUCCESS=$?

# Only actually fail on two consecuative failures
if [[ $SUCCESS -ne 0 ]]; then
    sleep 15
    doTest "${TEST_BASE_URL}" $TEST_DURATION_MINUTES
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

aws cloudwatch put-metric-data --namespace $CLOUDWATCH_NAMESPACE --metric-name "jitsi_longlived_test_failure" --dimensions $CLOUDWATCH_DIMENSIONS --value $CLOUDWATCH_VALUE --unit Count
echo "jitsi.jitsi_longlived_test_failure $CLOUDWATCH_VALUE source=jenkins-internal.jitsi.net environment=$ENVIRONMENT region=$CLOUDWATCH_REGION cloud=aws" | curl -s --data @- $WAVEFRONT_PROXY_URL

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
