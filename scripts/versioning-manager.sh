#!/bin/bash

## wrapper to call jitsi-versioning service
## create/delete new releases on jitsi-versioning-service
## set a release on jitsi-versioning-service as GA
## pin a tenant to a release
## delete a tenant pin

echo "# starting versioning-manager.sh"

if [ ! -z "$DEBUG" ]; then
  set -x
fi

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

if [ -z "$VERSIONING_ACTION" ]; then
  echo "## ERROR: no VERSIONING_ACTION provided or found, exiting..."
  exit 2
fi

if [ -z "$VERSIONING_URL" ]; then
  echo "## no VERSIONING_URL provided or found, skipping this environment"
  exit 0  # clean exit because this environment may not support this feature
fi

if [ -z "$JWT_ENV_FILE" ]; then 
  if [ -z "$TOKEN_GENERATOR_ENV_VARIABLES" ]; then
    echo "No TOKEN_GENERATOR_ENV_VARIABLES provided or found. Exiting.. "
    exit 211
  fi

  JWT_ENV_FILE="/etc/jitsi/token-generator/$TOKEN_GENERATOR_ENV_VARIABLES"
fi

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE="$JWT_ENV_FILE" ASAP_JWT_SUB="token-generator" ASAP_JWT_ISS="jenkins" ASAP_JWT_AUD="jitsi-versioning" ASAP_SCD="any" /opt/jitsi/token-generator/scripts/jwt.sh | tail -n1)

if [ "$VERSIONING_ACTION" == "CREATE_RELEASE" ]; then
  if [ -z "$VERSIONING_RELEASE" ]; then
    echo "## ERROR: no VERSIONING_RELEASE provided or found for CREATE_RELEASE, exiting..."
    exit 2
  fi

  if [ -z "$SIGNAL_VERSION" ]; then
    echo "## ERROR: no SIGNAL_VERSION provided or found for CREATE_RELEASE, exiting..."
    exit 2
  fi

  if [ -z "$JVB_VERSION" ]; then
    echo "## ERROR: no JVB_VERSION provided or found for CREATE_RELEASE, exiting..."
    exit 2
  fi

  # date must be in java.time.Instant format, defaults to now
  [ -z "$VERSIONING_RELEASE_DATE"] && VERSIONING_RELEASE_DATE="$(date --utc +%FT%TZ)"

  # default 3 months from the release date
  [ -z "$VERSIONING_RELEASE_EOL_DATE"] && VERSIONING_RELEASE_EOL_DATE="$(date --utc '+%FT%TZ' -d $VERSIONING_RELEASE_DATE' + 3 months')"

  # placeholder; currently unused
  [ -z "$VERSIONING_LTS" ] && VERSIONING_LTS=false

  # valid: AVAILABLE, GA, DELETED
  # note that AVAILABLE will not appear to customers until after it's been set to GA
  [ -z "$VERSIONING_RELEASE_STATUS" ] && VERSIONING_RELEASE_STATUS="AVAILABLE"

  # this is the end of the URL path, e.g., '6-may-2022-release-notes'
  # for https://developer.8x8.com/jaas/docs/6-may-2022-release-notes 
  [ -z "$VERSIONING_RELEASE_NOTES_TITLE" ] && VERSIONING_RELEASE_NOTES_TITLE=""

  REQUEST_BODY='{
      "releaseNumber": "'"$VERSIONING_RELEASE"'",
      "version": "Signal '$SIGNAL_VERSION' JVB '$JVB_VERSION'",
      "environment": "'$ENVIRONMENT'",
      "releaseDate": "'$VERSIONING_RELEASE_DATE'",
      "endOfLife": "'$VERSIONING_RELEASE_EOL_DATE'",
      "lts": '$VERSIONING_LTS',
      "releaseStatus": "'"$VERSIONING_RELEASE_STATUS"'",
      "releaseNotesTitle": "'$VERSIONING_RELEASE_NOTES_TITLE'"
  }'

  echo "## creating release $VERSIONING_RELEASE with version Signal $SIGNAL_VERSION JVB $JVB_VERSION"
  response=$(curl -s -w "\n %{http_code}" -X POST \
      "$VERSIONING_URL"/v1/releases \
      -H 'accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOKEN" \
      -d "$REQUEST_BODY")

  httpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g')
  if [ "$httpCode" == 200 ]; then
    echo "## release $VERSIONING_RELEASE was created successfully"
  else
    echo "## ERROR creating release $VERSIONING_RELEASE with status code $httpCode and response:\n$response"
    exit 1 
  fi

elif [ "$VERSIONING_ACTION" == "DELETE_RELEASE" ]; then

  if [ -z "$VERSIONING_RELEASE" ]; then
    echo "## ERROR: no VERSIONING_RELEASE provided or found for DELETE_RELEASE, exiting..."
    exit 2
  fi

  [ -z "$VERSIONING_FORCE_UNPIN" ] && VERSIONING_FORCE_UNPIN="false"

  echo "## deleting release $VERSIONING_RELEASE"
  response=$(curl -s -w '\n %{http_code}' -X DELETE \
      "$VERSIONING_URL"/v1/releases/"$VERSIONING_RELEASE"?environment="$ENVIRONMENT"\&forceUnpin="$VERSIONING_FORCE_UNPIN" \
      -H 'accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOKEN")

  httpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g')
  if [ "$httpCode" == 200 ]; then
    echo "## release $VERSIONING_RELEASE was successfully deleted"
  elif [ "$httpCode" == 404 ]; then
    echo "## WARNING versioning manager did not find release $VERSIONING_RELEASE with response:\n$response"
  else
    echo "## ERROR deleting release $VERSIONING_RELEASE with status code $httpCode and response:\n$response"
    exit 1
  fi

elif [ "$VERSIONING_ACTION" == "SET_RELEASE_GA" ]; then

  if [ -z "$VERSIONING_RELEASE" ]; then
    echo "## ERROR: no VERSIONING_RELEASE provided or found for SET_RELEASE_GA, exiting..."
    exit 2
  fi

  echo "## setting release $VERSIONING_RELEASE as GA"
  response=$(curl -s -w '\n %{http_code}' -X PUT \
      "$VERSIONING_URL"/v1/releases/"$VERSIONING_RELEASE"/ga?environment="$ENVIRONMENT" \
      -H 'accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOKEN")

  httpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g')
  if [ "$httpCode" == 200 ]; then
    echo "## release $VERSIONING_RELEASE was successfully set to GA"
  else
    echo "## ERROR setting release $VERSIONING_RELEASE to GA with status code $httpCode and response:\n$response"
    exit 1
  fi

elif [ "$VERSIONING_ACTION" == "GET_RELEASES" ]; then
  echo "## getting list of all releases"
  response=$(curl -s -w '\n %{http_code}' -X GET \
      "$VERSIONING_URL"/v1/releases?environment="$ENVIRONMENT" \
      -H 'accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOKEN")

  httpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g')
  if [ "$httpCode" == 200 ]; then
    echo "## release list:"
    echo "$response" | jq
  else
    echo "## ERROR getting releases with status code $httpCode and response:\n$response"
    exit 1
  fi

elif [ "$VERSIONING_ACTION" == "UPDATE_RELEASE_TITLE" ]; then
  echo "## updating release notes title"
  if [ -z "$VERSIONING_RELEASE_NOTES_TITLE" ]; then
    echo "## no VERSIONING_RELEASE_NOTES_TITLE provided or found, exiting"
    exit 2
  fi

  REQUEST_BODY='{
      "releaseNotesTitle": "'$VERSIONING_RELEASE_NOTES_TITLE'"
  }'

  response=$(curl -s -w '\n %{http_code}' -X PUT \
      "$VERSIONING_URL"/v1/releases/"$VERSIONING_RELEASE"?environment="$ENVIRONMENT" \
      -H 'accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOKEN" \
      -d "$REQUEST_BODY")

  httpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g')
  if [ "$httpCode" == 200 ]; then
    echo "## release list:"
    echo "$response" | jq
  else
    echo "## ERROR updating release notes title with status code $httpCode and response:\n$response"
    exit 1
  fi

elif [ "$VERSIONING_ACTION" == "SET_TENANT_PIN" ]; then
  echo "## setting tenant pin"
  if [ -z "$TENANT" ]; then
    echo "## no TENANT provided or found, exiting"
    exit 2
  fi
  if [ -z "$RELEASE_NUMBER" ]; then
    echo "## no RELEASE_NUMBER set, exiting"
    exit 2
  fi

  response=$(curl -s -w '\n %{http_code}' -X POST \
      "$VERSIONING_URL"/v1/customers/"$TENANT"/pin/"$RELEASE_NUMBER"?environment="$ENVIRONMENT" \
      -H 'accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOKEN" \
      -d "$REQUEST_BODY")

  httpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g')
  if [ "$httpCode" == 200 ]; then
    echo "## successfully pinned tenant $TENANT to release $RELEASE_NUMBER"
  else
    echo "## ERROR setting pin for $TENANT with status code $httpCode and response:\n$response"
    exit 1
  fi

elif [ "$VERSIONING_ACTION" == "DELETE_TENANT_PIN" ]; then
  echo "## deleting tenant pin"
  if [ -z "$TENANT" ]; then
    echo "## no TENANT provided or found, exiting"
    exit 2
  fi

  response=$(curl -s -w '\n %{http_code}' -X DELETE \
      "$VERSIONING_URL"/v1/customers/"$TENANT"/pin/?environment="$ENVIRONMENT" \
      -H 'accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOKEN" \
      -d "$REQUEST_BODY")

  httpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g')
  if [ "$httpCode" == 200 ]; then
    echo "## successfully deleted pin for $TENANT"
  else
    echo "## ERROR deleting pin for $TENANT with status code $httpCode and response:\n$response"
    exit 1
  fi

else
  echo "## ERROR no action performed, invalid VERSIONING_ACTION: $VERSIONING_ACTION"
  echo "## VERSIONING_ACTION must be CREATE_RELEASE, DELETE_RELEASE, GET_RELEASES, SET_RELEASE_GA, UPDATE_RELEASE_TITLE, SET_TENANT_PIN, or DELETE_TENANT_PIN"
  exit 2
fi
