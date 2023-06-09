#!/bin/bash

if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "## ssh user not defined, using current user: $SSH_USER"
else
  SSH_USER=$1
  echo "## will ssh as $SSH_USER"
fi

# assume set COMPARMENT_OCID ORACLE_REGION INSTANCE_ID DETAILS
BAD_PORT=444

# leave instance alive but draining while DNS health fails for this many seconds (6 hours)
[ -z "$DRAIN_SECONDS" ] && DRAIN_SECONDS=21600

#grab primary vnic
INSTANCE_PRIMARY_VNIC="$(oci compute instance list-vnics --region $ORACLE_REGION --instance-id $INSTANCE_ID | jq '.data[] | select(.["is-primary"] == true)')"
if [ $? -gt 0 ]; then
    echo "Failed determining primary VNIC, pre-detach drain operations will fail for $INSTANCE_ID"
fi

# grab public IP
INSTANCE_PRIMARY_PUBLIC_IP=$(echo "$INSTANCE_PRIMARY_VNIC" | jq -r '.["public-ip"]')
if [ "$INSTANCE_PRIMARY_PUBLIC_IP" == "null" ]; then
    echo "No primary IP found, something went wrong with rotation $INSTANCE_ID in $ORACLE_REGION"
    INSTANCE_PRIMARY_PUBLIC_IP=
fi

# next find route53 health check for IP
COTURN_HEALTHCHECK=$(aws route53 list-health-checks | jq ".HealthChecks[]|select(.HealthCheckConfig.IPAddress==\"$INSTANCE_PRIMARY_PUBLIC_IP\")")

if [ $? -eq 0 ]; then
    if [ ! -z "$COTURN_HEALTHCHECK" ]; then
        COTURN_HEALTHCHECK_ID=$(echo "$COTURN_HEALTHCHECK" | jq -r '.Id')
        # set health check to the wrong port, then wait a while before returning
        echo "Updating health check $COTURN_HEALTHCHECK_ID with known bad port $BAD_PORT to allow drain before rotating"
        aws route53 update-health-check --health-check-id $COTURN_HEALTHCHECK_ID --port $BAD_PORT
        sleep $DRAIN_SECONDS
    else
        echo "Error finding health check for $INSTANCE_PRIMARY_PUBLIC_IP"
    fi
else
    echo "Error finding Route53 health check for coturn $INSTANCE_ID in $ORACLE_REGION with IP $INSTANCE_PRIMARY_PUBLIC_IP"
fi

if [[ "$NOMAD_COTURN_FLAG" == "true" ]]; then
    # if nomad coturn is enabled, then drain the nomad client before shutting down
    # grab private IP
    INSTANCE_PRIMARY_PRIVATE_IP=$(echo "$INSTANCE_PRIMARY_VNIC" | jq -r '.["private-ip"]')
    if [ "$INSTANCE_PRIMARY_PRIVATE_IP" == "null" ]; then
        echo "No primary private IP found, something went wrong with rotation $INSTANCE_ID in $ORACLE_REGION"
        INSTANCE_PRIMARY_PRIVATE_IP=
    else
        echo -e "\n## rotate-coturn-oracle: setting nomad to drain on $INSTANCE_PRIMARY_PRIVATE_IP"
        timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP "nomad node eligibility -self -disable && nomad node drain -self -enable -detach -yes"
        echo -e "\n## rotate-coturn-oracle: waiting 90 for nomad drain to complete before stopping nomad and consul on $INSTANCE_PRIMARY_PRIVATE_IP"
        sleep 90
        timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP "nomad node drain -self -enable -force -detach -yes && sleep 10 && sudo service nomad stop && sudo service consul stop"
    fi
fi