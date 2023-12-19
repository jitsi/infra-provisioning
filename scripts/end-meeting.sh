#!/bin/bash

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT found.  Exiting..."
    exit 203
fi

if [ -e "./stack-env.sh" ]; then 
    . ./stack-env.sh
else
    . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh
fi

if [ -n "$1" ]; then
    CONFERENCE=$1
else
    if [ -z "$CONFERENCE" ]; then
        echo "No CONFERENCE set or passed in.  Exiting..."
        exit 2
    fi
fi

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"

[ -z "$SIGNAL_API_HOSTNAME" ] && SIGNAL_API_HOSTNAME="signal-api-$ENVIRONMENT.$TOP_LEVEL_DNS_ZONE_NAME"

if [ -z "$JWT_ENV_FILE" ]; then 
  if [ -z "$TOKEN_GENERATOR_ENV_VARIABLES" ]; then
    echo "No TOKEN_GENERATOR_ENV_VARIABLES provided or found. Exiting.. "
    exit 211
  fi

  JWT_ENV_FILE="/etc/jitsi/token-generator/$TOKEN_GENERATOR_ENV_VARIABLES"
fi

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE="/etc/jitsi/token-generator/$TOKEN_GENERATOR_ENV_VARIABLES" ASAP_JWT_SUB="*" ASAP_JWT_ISS="jitsi" ASAP_JWT_AUD="jitsi" /opt/jitsi/token-generator/scripts/jwt.sh | tail -n1)

END_MEETING_URL="https://$SIGNAL_API_HOSTNAME/end-meeting?conference=$CONFERENCE"

set -x

curl -d'{}' -v -H"Authorization: Bearer $TOKEN" "$END_MEETING_URL"
