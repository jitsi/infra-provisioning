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

if [ ! -f "$VAULT_PASSWORD_FILE" ] && [ ! -z "$ANSIBLE_VAULT_PASSWORD_VALUE" ]
echo "$ANSIBLE_VAULT_PASSWORD_VALUE" > $VAULT_PASSWORD_FILE

[ -z "$BUCKET_NAME" ] && BUCKET_NAME="jvb-bucket-${ENVIRONMENT}"

os object put --region $ORACLE_REGION --bucket $BUCKET_NAME --name id_rsa --file $USER_PRIVATE_KEY_PATH
os object put --region $ORACLE_REGION --bucket $BUCKET_NAME --name vault-password --file $VAULT_PASSWORD_FILE
