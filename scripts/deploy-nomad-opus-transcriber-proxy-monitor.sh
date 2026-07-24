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

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="opus-transcriber-proxy-monitor-$ORACLE_REGION"

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

# The job's Nomad region is left at the default "global"; the OCI region is targeted via the
# datacenter ($NOMAD_DC) and the region-specific NOMAD_ADDR (matches jitsi-test-lab/cloudprober).
sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/opus-transcriber-proxy-monitor.hcl" | nomad job run \
  -var="dc=$NOMAD_DC" \
  -var="environment=$ENVIRONMENT" \
  -var="image=$OPUS_TRANSCRIBER_PROXY_MONITOR_IMAGE" \
  -var="interval_seconds=$OPUS_TRANSCRIBER_PROXY_MONITOR_INTERVAL_SECONDS" \
  -var="ws_url_template=$WS_URL_TEMPLATE" \
  -

if [ $? -ne 0 ]; then
    echo "Failed to run nomad opus-transcriber-proxy-monitor job, exiting"
    exit 5
fi
