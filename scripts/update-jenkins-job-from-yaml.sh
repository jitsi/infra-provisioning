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

# JJB is always handed the whole jobs/ directory so that shared macros (e.g. the
# governance-params parameter macro in _macros-governance.yaml) resolve, and is
# then filtered down to the job being updated. Loading a single file would leave
# those macros undefined.
if [[ "$JOB_NAME" == "ALL" ]]; then
    echo "JOB_NAME set to 'ALL', applying all jobs in $JOB_PATH"
    JOB_FILTER=""
    JOB_FILE="*.y*ml"
else
    JOB_FILTER="$JOB_NAME"
    JOB_FILE="$JOB_NAME.yaml"
    if [ ! -e "$JOB_PATH/$JOB_FILE" ]; then
        # some job definitions use the .yml extension
        JOB_FILE="$JOB_NAME.yml"
        if [ ! -e "$JOB_PATH/$JOB_FILE" ]; then
            echo "No job file $JOB_PATH/$JOB_NAME.yaml or $JOB_PATH/$JOB_NAME.yml found, exiting"
            exit 2
        fi
    fi
fi
[ -z "$PUBLIC_CUSTOMIZATIONS_REPO" ] && PUBLIC_CUSTOMIZATIONS_REPO="git@github.com:jitsi/infra-customizations.git"
if [ -n "$PRIVATE_CUSTOMIZATIONS_REPO" ]; then
    echo "PRIVATE_CUSTOMIZATIONS_REPO is set, so updating $JOB_FILE with repo value"
    ESCAPED_PUBLIC=$(printf '%s\n' "$PUBLIC_CUSTOMIZATIONS_REPO" | sed -e 's/[]\/$*.^[]/\\&/g');
    ESCAPED_PRIVATE=$(printf '%s\n' "$PRIVATE_CUSTOMIZATIONS_REPO" | sed -e 's/[\/&]/\\&/g')
    if [[ $(uname) == "Darwin" ]]; then
        sed -i '' -e "s/$ESCAPED_PUBLIC/$ESCAPED_PRIVATE/g" $JOB_PATH/$JOB_FILE
    else
        sed -i -e "s/$ESCAPED_PUBLIC/$ESCAPED_PRIVATE/g" $JOB_PATH/$JOB_FILE
    fi

fi
set +x
[ -z "$JJB_URL" ] && JJB_URL="https://jenkins-opsdev.$TOP_LEVEL_DNS_ZONE_NAME"
[ -z "$JJB_USER" ] && JJB_USER="admin"
[ -z "$JJB_PASSWORD" ] && JJB_PASSWORD="replaceme"

cd $JOB_PATH

if [ -z "$JJB_CONF_FILE" ]; then
    ACTIVE_JJB_CONF_FILE="./jenkins_jobs.ini"
    cat > $ACTIVE_JJB_CONF_FILE <<EOF
[jenkins]
url=$JJB_URL

EOF
else
    ACTIVE_JJB_CONF_FILE="$JJB_CONF_FILE"
fi

echo "Testing job definition for ${JOB_NAME}"
# shellcheck disable=SC2086 # JOB_FILTER is intentionally unquoted: empty means "every job"
jenkins-jobs --flush-cache --conf $ACTIVE_JJB_CONF_FILE test . $JOB_FILTER
RET=$?

if [ $RET -eq 0 ]; then
    # shellcheck disable=SC2086
    jenkins-jobs --flush-cache --conf $ACTIVE_JJB_CONF_FILE update . $JOB_FILTER
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