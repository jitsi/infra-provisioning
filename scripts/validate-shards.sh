#!/bin/bash
set -x

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

run_check_validate() {
    IN_ENVIRONMENT=$1
    SHARD=$2
    echo "VALIDATING $IN_ENVIRONMENT SHARD $SHARD"
    TEST_ID="${BUILD_TAG}-$SHARD" SHARD="$SHARD" BUILD_NUMBER="$BUILD_NUMBER" $LOCAL_PATH/validate-shard.sh $ANSIBLE_SSH_USER
    VALIDATE_SUCCESS=$?
    echo "run_check_validate return $VALIDATE_SUCCESS"
    echo $VALIDATE_SUCCESS > $TORTURE_PATH/validate-result-$SHARD
    exit $VALIDATE_SUCCESS
}

[ -z $TEST_ID ] && TEST_ID='standalone'

#jenkins build number, we get it from jenkins
[ -z $BUILD_NUMBER ] && BUILD_NUMBER='N/A'

[ -z "$TORTURE_PATH" ] && TORTURE_PATH="../test-results-$TEST_ID"

[ -d "$TORTURE_PATH" ] || mkdir -p $TORTURE_PATH

#clean up results from any previous tests
rm -rf $TORTURE_PATH/*


IN_ENVIRONMENT=$1
IN_SHARDS=$2
[ -z "$IN_SHARDS" ] && IN_SHARDS=$SHARDS

[ -z "BUILD_TAG" ] && BUILD_TAG="standalone"

if [  -z "$3" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$3
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi


#do something
ALL_PASSED=true
for s in $IN_SHARDS; do
  run_check_validate $IN_ENVIRONMENT $s 2>&1 > $TORTURE_PATH/validate-output-$s
  success=$?
  cat $TORTURE_PATH/validate-output-$s
  if [ "$success" -eq 0 ]; then
    echo "Wait successful $s $success"
    if [ -e "$TORTURE_PATH/validate-result-$s" ]; then
      VALIDATE_RESULT=$(cat $TORTURE_PATH/validate-result-$s)
      if [ "$VALIDATE_RESULT" -eq 0 ]; then
        #FINALLY SUCCESSFUL
        echo "SUCCESS VALIDATING SHARD $s"
      else
        echo "FAILED VALIDATING SHARD $s, failed tests"
        ALL_PASSED=false
      fi
    fi
  else
    echo "FAILED VALIDATING SHARD $s, process failed"
    ALL_PASSED=false
  fi
done

if $ALL_PASSED; then
  exit 0
else
  exit 1
fi

#cleanup
#rm validate-*
