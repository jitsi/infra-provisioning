#!/bin/bash
## wrapper to call Meetings payments service to look up a tenant name based on a customer id
##
## PAYMENTS_ACTION=GET_CUSTOMER CUSTOMER_ID=xxxxx ../all/bin/payments-service.sh

if [ ! -z "$DEBUG" ]; then
  echo "# starting payments-service.sh"
fi

if [ -z "$ENVIRONMENT" ]; then
  echo "## ERROR: no ENVIRONMENT provided or found, exiting..."
  exit 2 
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

if [ -z "$PAYMENTS_ACTION" ]; then
  echo "## ERROR: no PAYMENTS_ACTION provided or found, exiting..."
  exit 2
fi

if [ -z "$PAYMENTS_URL" ]; then
  echo "## ERROR: no PAYMENTS_URL provided or found"
  exit 2
fi

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE="/etc/jitsi/token-generator/$TOKEN_GENERATOR_ENV_VARIABLES" ASAP_JWT_SUB="token-generator" ASAP_JWT_ISS="jenkins" ASAP_JWT_AUD="payments-service" ASAP_SCD="any" /opt/jitsi/token-generator/scripts/jwt.sh | tail -n1)

if [ "$PAYMENTS_ACTION" == "GET_CUSTOMER" ]; then
  if [ -z "$CUSTOMER_ID" ]; then
    echo "## ERROR: no CUSTOMER_ID provided or found for GET_CUSTOMER, exiting..."
    exit 2
  fi
  if [ ! -z "$DEBUG" ]; then
    echo "## getting customer details for $CUSTOMER_ID"
  fi

  response=$(curl -s -w "\n %{http_code}" -X GET \
      "$PAYMENTS_URL"/v1/customers/"$CUSTOMER_ID" \
      -H 'accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOKEN")

  httpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g')
  if [ "$httpCode" == 200 ]; then
    echo "$response"
  else
    echo -e "## ERROR getting customer details from ${PAYMENTS_URL}/v1/customers/${CUSTOMER_ID} with response:\n$response"
    exit 1 
  fi
else
  echo "## ERROR no action performed, invalid PAYMENTS_ACTION: $PAYMENTS_ACTION"
  echo "## PAYMENTS_ACTION must be GET_CUSTOMER"
  exit 2
fi