#!/bin/bash

# Registers the opus-transcriber-proxy transcription synthetic as a Nomad periodic job in
# one region of one environment. The job runs every 5 minutes, replays a sample Opus dump
# against that environment's public /transcribe endpoint, and emits a pass/fail gauge to the
# node-local telegraf; a Prometheus rule pages when it fails on two consecutive runs.
#
# ENVIRONMENT is both the cluster to deploy into and the environment whose endpoint/token are
# used (cloudprober-style), e.g. ENVIRONMENT=prod-8x8 ORACLE_REGION=us-phoenix-1.

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="opus-synthetic-$ORACLE_REGION"
PACKS_DIR="$LOCAL_PATH/../nomad/jitsi_packs/packs"

# --- Cloudflare Access service token: same source jicofo uses (ansible-vault jicofo.yml). ---
[ -z "$ENCRYPTED_JICOFO_CREDENTIALS_FILE" ] && ENCRYPTED_JICOFO_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jicofo.yml"
CF_ACCESS_CLIENT_ID="$(ansible-vault view $ENCRYPTED_JICOFO_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".secrets_jicofo_opus_transcriber_client_id_by_environment.\"$ENVIRONMENT\" // \"\"" -)"
CF_ACCESS_CLIENT_SECRET="$(ansible-vault view $ENCRYPTED_JICOFO_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".secrets_jicofo_opus_transcriber_secret_by_environment.\"$ENVIRONMENT\" // \"\"" -)"

if [ -z "$CF_ACCESS_CLIENT_ID" ] || [ -z "$CF_ACCESS_CLIENT_SECRET" ]; then
    echo "No opus-transcriber CF Access token for environment $ENVIRONMENT in $ENCRYPTED_JICOFO_CREDENTIALS_FILE, exiting"
    exit 3
fi

# --- Endpoint: reuse the jicofo transcription URL template. Its {{MEETING_ID}} placeholder
#     becomes __SESSION_ID__, which the job replaces at runtime with synthetic-<random>. ---
URL_TEMPLATE="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval '.jicofo_transcription_url_template // ""' -)"
if [ -z "$URL_TEMPLATE" ] || [ "$URL_TEMPLATE" == "false" ]; then
    echo "No jicofo_transcription_url_template in $ENVIRONMENT_CONFIGURATION_FILE, exiting"
    exit 3
fi
WS_URL_TEMPLATE="${URL_TEMPLATE//\{\{MEETING_ID\}\}/__SESSION_ID__}"

# --- Cadence: how often the running service replays the test (prod defaults to 5m; stage 2h). ---
[ -z "$OPUS_SYNTHETIC_INTERVAL_SECONDS" ] && OPUS_SYNTHETIC_INTERVAL_SECONDS="300"

# --- Image: the opus-transcriber-proxy image built by the repo's Docker Hub pipeline. ---
[ -z "$OPUS_SYNTHETIC_IMAGE" ] && OPUS_SYNTHETIC_IMAGE="jitsi/opus-transcriber-proxy:latest"

VAR_FILE="./opus-synthetic-${NOMAD_DC}.hcl"
cat > "$VAR_FILE" <<EOF
job_name="$JOB_NAME"
region="$ORACLE_REGION"
datacenters=["$NOMAD_DC"]
image="$OPUS_SYNTHETIC_IMAGE"
interval_seconds="$OPUS_SYNTHETIC_INTERVAL_SECONDS"
ws_url_template="$WS_URL_TEMPLATE"
cf_access_client_id="$CF_ACCESS_CLIENT_ID"
cf_access_client_secret="$CF_ACCESS_CLIENT_SECRET"
EOF

RENDER_DIR="/tmp/opus-synthetic-render-$$"

nomad-pack render --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var-file "$VAR_FILE" \
  --to-dir "$RENDER_DIR" \
  --auto-approve \
  $PACKS_DIR/jitsi_opus_synthetic

if [ $? -ne 0 ]; then
    echo "Failed to render nomad opus-synthetic job, exiting"
    rm -f "$VAR_FILE"
    rm -rf "$RENDER_DIR"
    exit 5
fi

RENDERED_JOB=$(find "$RENDER_DIR" -name "*.nomad" | head -1)
if [ -z "$RENDERED_JOB" ]; then
    echo "No rendered job file found in $RENDER_DIR, exiting"
    rm -f "$VAR_FILE"
    rm -rf "$RENDER_DIR"
    exit 5
fi

nomad job run "$RENDERED_JOB"
RUN_RC=$?

# The rendered var-file and job carry the CF Access token in cleartext; remove them.
rm -f "$VAR_FILE"
rm -rf "$RENDER_DIR"

if [ $RUN_RC -ne 0 ]; then
    echo "Failed to run nomad opus-synthetic job, exiting"
    exit 5
fi
