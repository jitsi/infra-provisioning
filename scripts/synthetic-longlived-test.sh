#!/bin/bash
set -x

SUCCESS=0

# Extracts the jitsi-meet-web version used from the base.html file on the shard.
# The results can be:
# - https://web-cdn.jitsi.net/meet8x8com_4570.1272/ for 8x8 deployments
#
# with jitsi-meet-web version we check all available meta packages from the newest
# to the latest for that web version and when we find that one
# we use the meta version to construct the tag to use for jitsi-meet-torture
function getJitsiMeetTortureTag {
  BASE_HTML=$(curl --silent --insecure https://8x8.vc/base.html)
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

#echo "Checking for jitsi-meet version used by 8x8.vc to match it for jitsi-meet-torture"	
#TORTURE_BRANCH=$(getJitsiMeetTortureTag)
# 2022-10-11 damencho: move to master will skip problem communicating with chrome instance and will clean up timers, so 
# we don't fail on last check
TORTURE_BRANCH="master"
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
        -DISABLEDremote.address="http://jitsi-grid.infra.jitsi.net:4444/wd/hub" \
        -Dremote.address="http://torture-test-us-phoenix-1-selenium-grid-prod.oracle.infra.jitsi.net:4444/wd/hub" \
        -Dremote.resource.path=/usr/share/jitsi-meet-torture \
        -Dtest.report.directory=target/report${REPORT_ID} \
        -Dwdm.gitHubTokenName=jitsi-jenkins \
        -Dwdm.gitHubTokenSecret=0efeda3d6a5dfa3feeeb5c42ef878c02614e0064
}

cd jitsi-meet-torture
# clean all local branches
git branch | grep -vx '* master' | xargs -r -n 1 git branch -D || true
# update
git fetch
git reset --hard origin/$TORTURE_BRANCH

TEST_BASE="https://8x8.vc/w3b70r7ur3/"
TEST_DURATION_MINUTES=5

set +x
echo "------------------------------------------------------------------------------"
echo "- CONFERENCE WEB TEST AT ${TEST_BASE} for ${TEST_DURATION_MINUTES} minutes"
echo "------------------------------------------------------------------------------"
echo ""

doTest "${TEST_BASE}" $TEST_DURATION_MINUTES
SUCCESS=$?

# Only actually fail on two consecuative failures
if [[ $SUCCESS -ne 0 ]]; then
    sleep 15
    doTest "${TEST_BASE}" $TEST_DURATION_MINUTES
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

CLOUDWATCH_NAMESPACE="Video"
CLOUDWATCH_DIMENSIONS="Environment=prod-8x8"

AWS_DEFAULT_REGION="us-west-2" aws cloudwatch put-metric-data --namespace $CLOUDWATCH_NAMESPACE --metric-name "jitsi_longlived_test_failure" --dimensions $CLOUDWATCH_DIMENSIONS --value $CLOUDWATCH_VALUE --unit Count
echo "jitsi.jitsi_longlived_test_failure $CLOUDWATCH_VALUE source=jenkins-internal.jitsi.net environment=prod-8x8 region=us-west-2 cloud=aws" | curl -s --data @- http://all-us-west-2-aws1-wf-proxy.infra.jitsi.net:2878

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
echo "-----------------------FAILURE CAUSE------------------------------------"
echo "------------------------------------------------------------------------"
echo ""

#function print_shutdown_instructions() {
#	echo "Check the voximplant log which is that jigasi (search for 'username = ') and ssh and check its logs"    
#    echo "You can also check the calls of that jigasi here https://manage.voximplant.com/application/4252352/calls by selecting for "
#    echo "rules 'confmap-prod' and for number let's say 'prod-8x8_us-west-2_19_102' and if all latest calls or most of them you see had Failed"
#    echo "put that jigasi in graceful shutdown so it is not used anymore by executing /usr/share/jigasi/graceful_shutdown.sh as root."
#    echo "The script will continue its execution till there are no conferences (can be few hours) and there will be a dump so we can check it later"
#    echo ""
#    echo "If anything goes wrong with the steps above page damencho."
#
#}
#function print_vox_log() {
#	echo ""
#	echo "Voximplant log START ***********************************************************"
#    LOG_FILE_URL=`cat ${CURRENT_CONSOLE_LOG} | grep dial-in.test.logUrl | cut -d ":" -f2-`
#	curl -s $LOG_FILE_URL || true
#	echo "Voximplant log END *************************************************************"
#}
#
#if grep -q dial-in.test.no-pin ${CURRENT_CONSOLE_LOG}; then
#	echo "No pin was found for the conference."
#    echo "Page Cluj or ask in meeting HQ room in VOD - it can be a deployment of the conference mapper at this moment".
#elif grep -q dial-in.test.restAPI.request.fail ${CURRENT_CONSOLE_LOG}; then
#	echo "Executing voximplant REST API fails, the failure code is visible in the console log above."
#    echo "Check voximplant status page https://status.voximplant.com/ for outage of the API."
#    echo "If problem persists after retrying in few minutes - send an email to support@voximplant.com and notify NOC they have a direct contact to page vox."
#elif grep -q dial-in.test.jigasi.participant.no.join.for ${CURRENT_CONSOLE_LOG}; then
#	echo "Jigasi did not join the call for some reason look at the voximplant log below:"
#	echo "- it can be conference mapper returning error, then page Cluj"
#    echo "- it can be the password service/(conference check url), then page Cluj ^"
#    echo "- it can be the jigasi selector. If jigasi selector is returning 503 or other error means there is no healthy jigasi or we cannot choose any, page Aaron."
#	echo ""
#	echo "- or it can be that jigasi instance having problems"
#	print_shutdown_instructions
#    print_vox_log
#elif grep -q dial-in.test.jigasi.participant.no.audio.after.join.for ${CURRENT_CONSOLE_LOG}; then
#	echo "Problem establishing the jingle call media path."
#    print_shutdown_instructions
#    print_vox_log
#else
#	echo "We haven't seen this, if retry is not fixing the problem and you cannot figure it out, page damencho."
#fi
#
echo "TO DO: LOOK AT LOG"
echo ""
echo "------------------------------------------------------------------------"
echo "------------------------------------------------------------------------"

exit $SUCCESS
