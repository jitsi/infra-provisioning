# assume set COMPARMENT_OCID ORACLE_REGION INSTANCE_ID DETAILS
BAD_PORT=444

# leave instance alive but draining while DNS health fails for this many seconds (6 hours)
[ -z "$DRAIN_SECONDS" ] && DRAIN_SECONDS=21600

# grab public IP
INSTANCE_PRIMARY_PUBLIC_IP=$(oci compute instance list-vnics --region $ORACLE_REGION --instance-id $INSTANCE_ID | jq -r '.data[] | select(.["is-primary"] == true) | .["public-ip"]')
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