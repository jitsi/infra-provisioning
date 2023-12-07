#!/bin/bash
set -x

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$NOMAD_POOL_TYPE" ] && NOMAD_POOL_TYPE="general"

[ -z "$DOCKER_TAG" ] && DOCKER_TAG="unstable-$(date +%Y-%m-%d)"

if [ -n "$SIGNAL_VERSION" ]; then
    if [ -z "$JITSI_MEET_VERSION" ]; then
        JITSI_MEET_VERSION="$(echo $SIGNAL_VERSION | cut -d'-' -f2)"
    fi
else
    if [ -n "$JICOFO_VERSION" ]; then
        SIGNAL_VERSION="$JICOFO_VERSION-$JITSI_MEET_VERSION-$PROSODY_VERSION"
    else
        SIGNAL_VERSION="$DOCKER_TAG"
    fi
fi

if [ -n "$JITSI_MEET_VERSION" ]; then
    WEB_TAG="web-1.0.$JITSI_MEET_VERSION-1"
fi

[ -z "$WEB_TAG" ] && WEB_TAG="$DOCKER_TAG"

[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"
[ -z "$MAIN_CONFIGURATION_FILE" ] && MAIN_CONFIGURATION_FILE="$LOCAL_PATH/../config/vars.yml"

BRANDING_NAME="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_branding_override -)"
if [[ "$BRANDING_NAME" != "null" ]]; then
    export CONFIG_web_repo="$AWS_ECR_REPO_HOST/jitsi/$BRANDING_NAME"
    WEB_TAG="$JITSI_MEET_VERSION"
else
    BRANDING_NAME="jitsi-meet"
fi

if [[ "$BRANDING_NAME" == "jitsi-meet" ]]; then
    # check for branding
    MANIFEST="$(docker manifest inspect jitsi/web:$WEB_TAG)"
    if [ $? -ne 0 ]; then
        echo "No branding image available at jitsi/web:$WEB_TAG, exiting"
        exit 1
    fi
else
    # login to docker and check for branding image
    [ -z "$AWS_DEFAULT_REGION" ] && AWS_DEFAULT_REGION="us-west-2"
    aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ECR_REPO_HOST

    # grab manifest from ECR
    RETRIES=360
    while true; do
        MANIFEST="$(docker manifest inspect $AWS_ECR_REPO_HOST/jitsi/$BRANDING_NAME:$WEB_TAG)"
        if [ $? -eq 0 ]; then
            echo "Image details found for $AWS_ECR_REPO_HOST/jitsi/$BRANDING_NAME:$WEB_TAG"
            break
        else
            # check if we have any more retries left
            if [ $RETRIES -eq 0 ]; then
                echo "No image available at $AWS_ECR_REPO_HOST/jitsi/$BRANDING_NAME:$WEB_TAG, exiting"
                echo "$MANIFEST"
                exit 1
            else
                RETRIES=$((RETRIES-1))
                echo "No image available yet at $AWS_ECR_REPO_HOST/jitsi/$BRANDING_NAME:$WEB_TAG, delaying release job"
                sleep 10
            fi
        fi
    done
fi

export CONFIG_legal_urls="$(yq eval -o json '.legal_urls' $ENVIRONMENT_CONFIGURATION_FILE)"

# evaluate each string, integer and boolean in the environment configuration file and export it as a CONFIG_ environment variable
eval $(yq '.. | select(tag == "!!int" or tag == "!!str" or tag == "!!bool") |  "export CONFIG_"+(path | join("_")) + "=\"" + . + "\""' $ENVIRONMENT_CONFIGURATION_FILE)

export CONFIG_environment="$ENVIRONMENT"
export CONFIG_domain="$DOMAIN"
export CONFIG_release_number="$RELEASE_NUMBER"
export CONFIG_signal_version="$SIGNAL_VERSION"
export CONFIG_web_tag="$WEB_TAG"
export CONFIG_pool_type="$NOMAD_POOL_TYPE"
export CONFIG_branding_name="$BRANDING_NAME"

[ -z "$REGIONS" ] && REGIONS="$DRG_PEER_REGIONS"

NOMAD_DC="[]"
for ORACLE_REGION in $REGIONS; do
    NOMAD_DC="$( echo "$NOMAD_DC" "[\"$ENVIRONMENT-$ORACLE_REGION\"]" | jq -c -s '.|add')"
done

PACKS_DIR="$LOCAL_PATH/../nomad/jitsi_packs/packs"


nomad-pack plan \
  --name "web-release-${RELEASE_NUMBER}" \
  -var "job_name=web-release-${RELEASE_NUMBER}" \
  -var "dc=$NOMAD_DC" \
  $PACKS_DIR/jitsi_meet_web

PLAN_RET=$?

if [ $PLAN_RET -gt 1 ]; then
    echo "Failed planning web release job, exiting"
    exit 4
else
    if [ $PLAN_RET -eq 1 ]; then
        echo "Plan was successful, will make changes"
    fi
    if [ $PLAN_RET -eq 0 ]; then
        echo "Plan was successful, no changes needed"
    fi
fi

nomad-pack run \
  --name "web-release-${RELEASE_NUMBER}" \
  -var "job_name=web-release-${RELEASE_NUMBER}" \
  -var "dc=$NOMAD_DC" \
  $PACKS_DIR/jitsi_meet_web
#  | tail -n+2 \
# #  | nomad job run -
