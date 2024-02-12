#!/bin/bash
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$LOCAL_DEV_DIR" ] && LOCAL_DEV_DIR="$(realpath "$HOME/dev")"
[ -z "$ASAP_KEY_DIR" ] && ASAP_KEY_DIR="/opt/jitsi/keys"
[ -z "$OPS_AGENT_VERSION" ] && OPS_AGENT_VERSION="latest"
[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE='./.vault-password.txt'

[ -z "$ENCRYPTED_ASAP_KEYS_FILE" ] && ENCRYPTED_ASAP_KEYS_FILE="$LOCAL_PATH/../../infra-customizations-private/ansible/secrets/asap-keys.yml"
[ -z "$ENCRYPTED_JENKINS_FILE" ] && ENCRYPTED_JENKINS_FILE="$LOCAL_PATH/../../infra-customizations-private/ansible/secrets/jenkins.yml"

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export ASAP_JWT_KID_DEV="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_prod.id" -)"

export ASAP_JWT_KID_PROD="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_stage.id" -)"

export ASAP_CLIENT_JWT_KID_MEET="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_client_meet.id" -)"
export ASAP_CLIENT_JWT_KID_BETA="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_client_beta.id" -)"
export ASAP_CLIENT_JWT_KID_PROD="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_client_prod.id" -)"
export ASAP_CLIENT_JWT_KID_STAGE="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".asap_key_client_stage.id" -)"
export JENKINS_AWS_ACCESS_KEY_ID="$(ansible-vault view $ENCRYPTED_JENKINS_FILE --vault-password $VAULT_PASSWORD_FILE | tail +3 | xmlstarlet sel -t -c "/list//credentials//org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl[id[contains(.,'jenkins-aws-id')]]/secret/text()" | tr -d '\n' | tr -d ' ')"
export JENKINS_AWS_SECRET_ACCESS_KEY="$(ansible-vault view $ENCRYPTED_JENKINS_FILE --vault-password $VAULT_PASSWORD_FILE | tail +3 | xmlstarlet sel -t -c "/list//credentials//org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl[id[contains(.,'jenkins-aws-secret')]]/secret/text()" | tr -d '\n' | tr -d ' ')"

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
AWS_DEFAULT_REGION=us-west-2
EOF

docker run --env-file $ENVFILE  -v ~/.ssh:/home/jenkins/.ssh \
  -v $LOCAL_DEV_DIR/infra-provisioning:/home/jenkins/infra-provisioning \
  -v $LOCAL_DEV_DIR/infra-configuration:/home/jenkins/infra-configuration \
  -v $LOCAL_DEV_DIR/infra-customizations-private:/home/jenkins/infra-customizations-private \
  -v ~/.jenkins-oci:/home/jenkins/.oci \
  -v ~/.jenkins-aws:/home/jenkins/.aws \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $ASAP_KEY_DIR:/opt/jitsi/keys \
  -it aaronkvanmeerten/ops-agent:$OPS_AGENT_VERSION

rm $ENVFILE
