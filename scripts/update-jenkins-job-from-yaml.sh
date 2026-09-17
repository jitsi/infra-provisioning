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
#
# This couples every job definition together permanently: a job file that fails
# to parse blocks EVERY update, not just its own and not just JOB_NAME=ALL. That
# is the standing price of shared macros, so keep the directory parseable.
if [[ "$JOB_NAME" == "ALL" ]]; then
    echo "JOB_NAME set to 'ALL', applying all jobs in $JOB_PATH"
    JOB_FILTER=""
    JOB_FILE="*.y*ml"
else
    JOB_FILE="$JOB_NAME.yaml"
    if [ ! -e "$JOB_PATH/$JOB_FILE" ]; then
        # some job definitions use the .yml extension
        JOB_FILE="$JOB_NAME.yml"
        if [ ! -e "$JOB_PATH/$JOB_FILE" ]; then
            echo "No job file $JOB_PATH/$JOB_NAME.yaml or $JOB_PATH/$JOB_NAME.yml found, exiting"
            exit 2
        fi
    fi
    # JJB filters by the job names a file DECLARES, which is not always the file's
    # own name: deploy-nomad-coturn.yaml declares provision-nomad-coturn, and the
    # deploy-nomad-* family in infra-customizations does the same. Filtering on
    # JOB_NAME would match nothing and exit 0 without updating anything, so derive
    # the filter from the file instead.
    #
    # Ask JJB for the names rather than pattern-matching the YAML. "jenkins-jobs
    # list" expands job-template / project / job-group definitions exactly as the
    # test and update runs below will, so a file that declares its jobs through a
    # template resolves to the real job names. The grep-for-"^- job:" this replaced
    # could not see those: it returned an empty filter and the run aborted with
    # "No job declared", which is what kept the repeated nomad job definitions from
    # being collapsed into templates.
    #
    # Name expansion does not resolve component macros, so a single file lists fine
    # on its own even though it references governance-params or
    # infra-provisioning-checkout from _macros-*.yaml.
    if ! JOB_FILTER=$(jenkins-jobs list -p "$JOB_PATH/$JOB_FILE" 2>/dev/null); then
        echo "Could not read job names from $JOB_PATH/$JOB_FILE, exiting. JJB said:"
        jenkins-jobs list -p "$JOB_PATH/$JOB_FILE"
        exit 2
    fi
    if [ -z "$JOB_FILTER" ]; then
        echo "No job declared in $JOB_PATH/$JOB_FILE, exiting"
        exit 2
    fi
    echo "Job file $JOB_FILE declares: $(echo $JOB_FILTER | tr '\n' ' ')"
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