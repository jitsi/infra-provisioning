#!/bin/bash
# Checks the TLS certificate of each site in SSL_CHECK_SITES and reports every site to the
# global alertmanager: firing when its certificate expires within SSL_CHECK_DAYS or cannot be
# read, resolved otherwise. Alertmanager routes the firing alerts to the alert-emailer and Slack.
set -o pipefail

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT provided or found. Exiting ..."
    exit 1
fi

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"

[ -z "$SITES" ] && SITES="$SSL_CHECK_SITES"
[ -z "$SSL_CHECK_DAYS" ] && SSL_CHECK_DAYS=30
[ -z "$ALERTMANAGER_URL" ] && ALERTMANAGER_URL="https://$GLOBAL_ALERTMANAGER_HOST"
# a firing alert must outlive the gap to the next run, or it resolves between runs
[ -z "$ALERT_HOLD_HOURS" ] && ALERT_HOLD_HOURS=26

if [ -z "$SITES" ]; then
    echo "No SITES provided and SSL_CHECK_SITES is not set in clouds/all.sh. Exiting ..."
    exit 1
fi

if [ "$ALERTMANAGER_URL" == "https://" ]; then
    echo "No ALERTMANAGER_URL provided and GLOBAL_ALERTMANAGER_HOST is not set. Exiting ..."
    exit 1
fi

NOW=$(date -u +%s)
NOW_ISO=$(date -u -d "@$NOW" +%Y-%m-%dT%H:%M:%SZ)
HOLD_ISO=$(date -u -d "@$((NOW + ALERT_HOLD_HOURS * 3600))" +%Y-%m-%dT%H:%M:%SZ)

ALERTS='[]'
FAILED=0

add_alert() {
    local site="$1" ends_at="$2" summary="$3"
    ALERTS=$(jq -c \
        --arg site "$site" \
        --arg environment "$ENVIRONMENT" \
        --arg ends_at "$ends_at" \
        --arg summary "$summary" \
        --arg build_url "$BUILD_URL" \
        '. + [{
            labels: {
                alertname: "SSL_Certificate_Expiring",
                site: $site,
                environment: $environment,
                service: "infra",
                severity: "warn",
                scope: "global"
            },
            annotations: ({summary: $summary} + (if $build_url != "" then {alert_url: $build_url} else {} end)),
            endsAt: $ends_at
        }]' <<< "$ALERTS")
}

for site in $SITES; do
    end_date=$(timeout 20 openssl s_client -servername "$site" -connect "$site:443" < /dev/null 2> /dev/null \
        | openssl x509 -noout -enddate 2> /dev/null | cut -d= -f2)

    if [ -z "$end_date" ]; then
        echo "FAIL $site: could not read a certificate"
        add_alert "$site" "$HOLD_ISO" "could not read the TLS certificate of $site"
        FAILED=1
        continue
    fi

    end_epoch=$(date -u -d "$end_date" +%s)
    end_iso=$(date -u -d "@$end_epoch" +%Y-%m-%d)
    days_left=$(( (end_epoch - NOW) / 86400 ))

    if [ "$days_left" -lt "$SSL_CHECK_DAYS" ]; then
        echo "FAIL $site: certificate expires $end_iso ($days_left days)"
        add_alert "$site" "$HOLD_ISO" "TLS certificate of $site expires $end_iso ($days_left days)"
        FAILED=1
    else
        echo "OK   $site: certificate expires $end_iso ($days_left days)"
        add_alert "$site" "$NOW_ISO" "TLS certificate of $site expires $end_iso ($days_left days)"
    fi
done

echo "Posting $(jq length <<< "$ALERTS") alerts to $ALERTMANAGER_URL"
if ! curl -fsS -m 30 -X POST -H "Content-Type: application/json" \
        --data "$ALERTS" "$ALERTMANAGER_URL/api/v2/alerts"; then
    echo "Failed to post alerts to $ALERTMANAGER_URL"
    exit 2
fi

exit $FAILED
