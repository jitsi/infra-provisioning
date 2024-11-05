#!/bin/bash
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$LOCAL_DEV_DIR" ] && LOCAL_DEV_DIR="$(realpath "$LOCAL_PATH/../..")"

[ -z "$ASAP_KEY_DIR" ] && ASAP_KEY_DIR="$(realpath ~/asap/keys)"
[ -z "$OPS_AGENT_VERSION" ] && OPS_AGENT_VERSION="latest"
[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

[ -z "$ENCRYPTED_ASAP_KEYS_FILE" ] && ENCRYPTED_ASAP_KEYS_FILE="$LOCAL_PATH/../../infra-customizations-private/ansible/secrets/asap-keys.yml"
[ -z "$ENCRYPTED_JENKINS_FILE" ] && ENCRYPTED_JENKINS_FILE="$LOCAL_PATH/../../infra-customizations-private/ansible/secrets/jenkins.yml"

set -e
set -o pipefail
if [ -r "$VAULT_PASSWORD_FILE" ]
then
    # ensure no output for ansible vault contents and fail if ansible-vault fails
    OLDVARS=$-
    set +x
    export ASAP_JWT_KID_DEV="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_prod.id" -)"

    export ASAP_JWT_KID_PROD="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_prod.id" -)"
    export ASAP_JWT_KID_STAGE="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_stage.id" -)"

    export ASAP_CLIENT_JWT_KID_MEET="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_client_meet.id" -)"
    export ASAP_CLIENT_JWT_KID_BETA="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_client_beta.id" -)"
    export ASAP_CLIENT_JWT_KID_PROD="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_client_prod.id" -)"
    export ASAP_CLIENT_JWT_KID_STAGE="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_client_stage.id" -)"
    export JENKINS_AWS_ACCESS_KEY_ID="$(ansible-vault view $ENCRYPTED_JENKINS_FILE --vault-password $VAULT_PASSWORD_FILE | tail +3 | xmlstarlet sel -t -c "/list//credentials//org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl[id[contains(.,'jenkins-aws-id')]]/secret/text()" | tr -d '\n' | tr -d ' ')"
    export JENKINS_AWS_SECRET_ACCESS_KEY="$(ansible-vault view $ENCRYPTED_JENKINS_FILE --vault-password $VAULT_PASSWORD_FILE | tail +3 | xmlstarlet sel -t -c "/list//credentials//org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl[id[contains(.,'jenkins-aws-secret')]]/secret/text()" | tr -d '\n' | tr -d ' ')"
    export JENKINS_TERRAFORM_AWS_ACCESS_KEY_ID="$(ansible-vault view $ENCRYPTED_JENKINS_FILE --vault-password $VAULT_PASSWORD_FILE | tail +3 | xmlstarlet sel -t -c "/list//credentials//org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl[id[contains(.,'oci-jenkins-terraform-aws-id')]]/secret/text()" | tr -d '\n' | tr -d ' ')"
    export JENKINS_TERRAFORM_AWS_SECRET_ACCESS_KEY="$(ansible-vault view $ENCRYPTED_JENKINS_FILE --vault-password $VAULT_PASSWORD_FILE | tail +3 | xmlstarlet sel -t -c "/list//credentials//org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl[id[contains(.,'oci-jenkins-terraform-aws-secret')]]/secret/text()" | tr -d '\n' | tr -d ' ')"

    ENVFILE="$(mktemp)"
    cat <<EOF > $ENVFILE
ASAP_JWT_KID_DEV=$ASAP_JWT_KID_DEV
ASAP_JWT_KEY_DEV=/opt/jitsi/keys/asap-pilot.key
ASAP_JWT_KID_PROD=$ASAP_JWT_KID_PROD
ASAP_JWT_KEY_PROD=/opt/jitsi/keys/asap-prod.key
ASAP_CLIENT_JWT_KID_MEET=$ASAP_CLIENT_JWT_KID_MEET
ASAP_CLIENT_JWT_KEY_MEET=/opt/jitsi/keys/asap-client-meet.key
ASAP_CLIENT_JWT_KID_BETA=$ASAP_CLIENT_JWT_KID_BETA
ASAP_CLIENT_JWT_KEY_BETA=/opt/jitsi/keys/asap-client-beta.key
ASAP_CLIENT_JWT_KID_PROD=$ASAP_CLIENT_JWT_KID_PROD
ASAP_CLIENT_JWT_KEY_PROD=/opt/jitsi/keys/asap-client-prod.key
ASAP_CLIENT_JWT_KID_STAGE=$ASAP_CLIENT_JWT_KID_STAGE
ASAP_CLIENT_JWT_KEY_STAGE=/opt/jitsi/keys/asap-client-pilot.key
AWS_ACCESS_KEY_ID=$JENKINS_AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$JENKINS_AWS_SECRET_ACCESS_KEY
TERRAFORM_AWS_ACCESS_KEY_ID=$JENKINS_TERRAFORM_AWS_ACCESS_KEY_ID
TERRAFORM_AWS_SECRET_ACCESS_KEY=$JENKINS_TERRAFORM_AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION=us-west-2
EOF

    # restore set -x if it was set initially
    case $OLDVARS in
        *x*)
            set -x
            ;;
    esac
else
    echo "$VAULT_PASSWORD_FILE not found or not readable; skipping variables that require it" 1>&2
    ENVFILE="$(mktemp)"
    cat <<EOF > $ENVFILE
AWS_DEFAULT_REGION=us-west-2
EOF
fi

docker run --env-file $ENVFILE  -v ~/.ssh:/home/jenkins/.ssh \
  -v $LOCAL_DEV_DIR/infra-provisioning:/home/jenkins/infra-provisioning \
  -v $LOCAL_DEV_DIR/infra-configuration:/home/jenkins/infra-configuration \
  -v $LOCAL_DEV_DIR/infra-customizations-private:/home/jenkins/infra-customizations-private \
  -v ~/.jenkins-oci:/home/jenkins/.oci \
  -v ~/.jenkins-aws:/home/jenkins/.aws \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $ASAP_KEY_DIR:/opt/jitsi/keys \
  --cap-add=CAP_IPC_LOCK \
  -it aaronkvanmeerten/ops-agent:$OPS_AGENT_VERSION "$@"

rm $ENVFILE
