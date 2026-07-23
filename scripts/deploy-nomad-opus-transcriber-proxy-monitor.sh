#!/bin/bash

# Registers the opus-transcriber-proxy transcription monitor as a Nomad service in one region of
# one environment. The service runs the opus-transcriber-proxy image in monitor mode: it replays a
# sample Opus dump against that environment's public /transcribe endpoint on an interval and exposes
# a healthy flag on /metrics, which Prometheus scrapes and alerts on.
#
# ENVIRONMENT is both the cluster to deploy into and the environment whose endpoint/token are used
# (cloudprober-style), e.g. ENVIRONMENT=prod-8x8 ORACLE_REGION=us-phoenix-1.

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

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="opus-transcriber-proxy-monitor-$ORACLE_REGION"
PACKS_DIR="$LOCAL_PATH/../nomad/jitsi_packs/packs"

# The CF Access service token is NOT passed here: the job's task (named opus-transcriber-proxy)
# reads it from Vault at runtime (secret/default/opus-transcriber-proxy/monitor-$ENVIRONMENT). It
# must be seeded there first (scripts/write-secrets-to-vault.sh in infra-customizations-private).

# --- Endpoint: reuse the jicofo transcription URL template. Its {{MEETING_ID}} placeholder
#     becomes __SESSION_ID__, which the monitor replaces at runtime with monitor-<random>. ---
URL_TEMPLATE="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval '.jicofo_transcription_url_template // ""' -)"
if [ -z "$URL_TEMPLATE" ] || [ "$URL_TEMPLATE" == "false" ]; then
    echo "No jicofo_transcription_url_template in $ENVIRONMENT_CONFIGURATION_FILE, exiting"
    exit 3
fi
# The site var wraps the URL in an Ansible Jinja literal: {{ 'wss://...' }}. Unwrap to the inner
# string (which still contains {{MEETING_ID}}), then substitute our session-id placeholder.
URL_TEMPLATE="$(echo "$URL_TEMPLATE" | sed -E "s/^\{\{[[:space:]]*'//; s/'[[:space:]]*\}\}\$//")"
WS_URL_TEMPLATE="${URL_TEMPLATE//\{\{MEETING_ID\}\}/__SESSION_ID__}"

# --- Cadence: how often the running service replays the test. Per-env from the site's
#     opus_transcriber_proxy_monitor_interval_seconds, overridable by the
#     OPUS_TRANSCRIBER_PROXY_MONITOR_INTERVAL_SECONDS env, defaulting to 300 (5m). ---
if [ -z "$OPUS_TRANSCRIBER_PROXY_MONITOR_INTERVAL_SECONDS" ]; then
    OPUS_TRANSCRIBER_PROXY_MONITOR_INTERVAL_SECONDS="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval '.opus_transcriber_proxy_monitor_interval_seconds // ""' -)"
fi
[ -z "$OPUS_TRANSCRIBER_PROXY_MONITOR_INTERVAL_SECONDS" ] && OPUS_TRANSCRIBER_PROXY_MONITOR_INTERVAL_SECONDS="300"

# --- Image: the opus-transcriber-proxy image built by the repo's Docker Hub pipeline. ---
[ -z "$OPUS_TRANSCRIBER_PROXY_MONITOR_IMAGE" ] && OPUS_TRANSCRIBER_PROXY_MONITOR_IMAGE="jitsi/opus-transcriber-proxy:latest"

VAR_FILE="./opus-transcriber-proxy-monitor-${NOMAD_DC}.hcl"
# No region is set: the cluster's Nomad region is "global"; the OCI region is targeted via the
# datacenter ($NOMAD_DC) and the region-specific NOMAD_ADDR (matches jitsi-test-lab/cloudprober).
cat > "$VAR_FILE" <<EOF
job_name="$JOB_NAME"
datacenters=["$NOMAD_DC"]
environment="$ENVIRONMENT"
image="$OPUS_TRANSCRIBER_PROXY_MONITOR_IMAGE"
interval_seconds="$OPUS_TRANSCRIBER_PROXY_MONITOR_INTERVAL_SECONDS"
ws_url_template="$WS_URL_TEMPLATE"
EOF

RENDER_DIR="/tmp/opus-transcriber-proxy-monitor-render-$$"

nomad-pack render --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var-file "$VAR_FILE" \
  --to-dir "$RENDER_DIR" \
  --auto-approve \
  $PACKS_DIR/jitsi_opus_transcriber_proxy_monitor

if [ $? -ne 0 ]; then
    echo "Failed to render nomad opus-transcriber-proxy-monitor job, exiting"
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

rm -f "$VAR_FILE"
rm -rf "$RENDER_DIR"

if [ $RUN_RC -ne 0 ]; then
    echo "Failed to run nomad opus-transcriber-proxy-monitor job, exiting"
    exit 5
fi
