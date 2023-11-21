#!/bin/bash

#set -x
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

if [ -z "$JOB_NAME" ]; then
    echo "No JOB_NAME set, exiting"
    exit 2
fi

JOB_PATH="$LOCAL_PATH/../jenkins/jobs"
if [[ "$JOB_NAME" == "ALL" ]]; then
    echo "JOB_NAME set to 'ALL', applying all jobs in $JOB_PATH"
    JOB_NAME=""
    JOB_FILE="$JOB_PATH/*.yaml"
else
    JOB_FILE="$JOB_PATH/$JOB_NAME.yaml"
    if [ ! -e "$JOB_FILE" ]; then
        echo "No job file $JOB_FILE found, exiting"
        exit 2
    fi
fi
[ -z "$PUBLIC_CUSTOMIZATIONS_REPO" ] && PUBLIC_CUSTOMIZATIONS_REPO="git@github.com:jitsi/infra-customizations.git"
if [ -n "$PRIVATE_CUSTOMIZATIONS_REPO" ]; then
    echo "PRIVATE_CUSTOMIZATIONS_REPO is set, so updating $JOB_FILE with repo value"
    ESCAPED_PUBLIC=$(printf '%s\n' "$PUBLIC_CUSTOMIZATIONS_REPO" | sed -e 's/[]\/$*.^[]/\\&/g');
    ESCAPED_PRIVATE=$(printf '%s\n' "$PRIVATE_CUSTOMIZATIONS_REPO" | sed -e 's/[\/&]/\\&/g')
    if [[ $(uname) == "Darwin" ]]; then
        sed -i '' -e "s/$ESCAPED_PUBLIC/$ESCAPED_PRIVATE/g" $JOB_FILE
    else
        sed -i -e "s/$ESCAPED_PUBLIC/$ESCAPED_PRIVATE/g" $JOB_FILE
    fi

fi
set +x
[ -z "$JJB_URL" ] && JJB_URL="https://jenkins-opsdev.$TOP_LEVEL_DNS_ZONE_NAME"
[ -z "$JJB_USER" ] && JJB_USER="admin"
[ -z "$JJB_PASSWORD" ] && JJB_PASSWORD="replaceme"

if [ -z "$JJB_CONF_FILE" ]; then
    ACTIVE_JJB_CONF_FILE="./jenkins_jobs.ini"
    cat > $ACTIVE_JJB_CONF_FILE <<EOF
[jenkins]
url=$JJB_URL

EOF
else
    ACTIVE_JJB_CONF_FILE="$JJB_CONF_FILE"
fi

echo "Testing job definition for $JOB_NAME"
jenkins-jobs --flush-cache --conf $ACTIVE_JJB_CONF_FILE test $JOB_PATH $JOB_NAME
RET=$?

if [ $RET -eq 0 ]; then
    jenkins-jobs --flush-cache --conf $ACTIVE_JJB_CONF_FILE update $JOB_PATH $JOB_NAME
    RET=$?
else
    echo "Failed during job definition test, skipping update"
    exit 2
fi

if [ -z "$JJB_CONF_FILE" ]; then
    # we created ACTIVE_JJB_CONF_FILE so delete it now
    rm $ACTIVE_JJB_CONF_FILE
fi

exit $RET