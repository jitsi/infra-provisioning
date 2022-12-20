#!/usr/bin/env bash
set -x

# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE='./.vault-password.txt'

[ -z "$BUCKET_NAME" ] && BUCKET_NAME="jvb-bucket-${ENVIRONMENT}"

if [ ! -f "$VAULT_PASSWORD_FILE" ] && [ ! -z "$ANSIBLE_VAULT_PASSWORD_VALUE" ]; then
    echo "$ANSIBLE_VAULT_PASSWORD_VALUE" > $VAULT_PASSWORD_FILE
fi

if [ ! -f "$VAULT_PASSWORD_FILE" ]; then
    echo "No VAULT_PASSWORD_FILE found and no ANSIBLE_VAULT_PASSWORD_VALUE set. Exiting..."
  exit 203
fi

if [ -z "$ORACLE_REGIONS" ]; then
  echo "No ORACLE_REGIONS found. Exiting..."
  exit 203
fi

if [ -z "$USER_PRIVATE_KEY_PATH" ]; then
  echo "No USER_PRIVATE_KEY_PATH found. Exiting..."
  exit 203
fi


for ORACLE_REGION in $ORACLE_REGIONS; do
    oci os object put --force --region $ORACLE_REGION --bucket-name $BUCKET_NAME --name id_rsa_jitsi_deployment --file "$USER_PRIVATE_KEY_PATH"
    oci os object put --force --region $ORACLE_REGION --bucket-name $BUCKET_NAME --name vault-password --file "$VAULT_PASSWORD_FILE"
done