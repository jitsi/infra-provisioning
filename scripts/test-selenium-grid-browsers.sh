#!/bin/bash
#
# Smoke test for a selenium grid: creates Chrome and Firefox sessions
# via the W3C WebDriver API, then cleans them up.
#
# Required env vars (or pass GRID_URL directly):
#   GRID_URL - full WebDriver hub URL (e.g. https://...:4444/wd/hub)
#   OR all of: ENVIRONMENT, ORACLE_REGION, GRID
#
# Optional:
#   RETRY_ATTEMPTS - number of retries waiting for grid readiness (default: 10)
#   RETRY_DELAY    - seconds between retries (default: 30)

set -euo pipefail

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# Source environment configs if needed to resolve DNS zone
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"

# Build GRID_URL from components if not provided directly
if [ -z "${GRID_URL:-}" ]; then
    if [ -z "${ENVIRONMENT:-}" ] || [ -z "${ORACLE_REGION:-}" ] || [ -z "${GRID:-}" ]; then
        echo "ERROR: Either GRID_URL or (ENVIRONMENT, ORACLE_REGION, GRID) must be set"
        exit 2
    fi
    DNS_ZONE="${TOP_LEVEL_DNS_ZONE_NAME:-jitsi.net}"
    GRID_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-${GRID}-grid.${DNS_ZONE}/wd/hub"
fi

echo "## Selenium Grid smoke test against: $GRID_URL"

RETRY_ATTEMPTS="${RETRY_ATTEMPTS:-10}"
RETRY_DELAY="${RETRY_DELAY:-30}"

# Wait for grid to become ready
echo "## Waiting for grid to become ready..."
for i in $(seq 1 "$RETRY_ATTEMPTS"); do
    STATUS=$(curl -sf --connect-timeout 10 --max-time 30 "${GRID_URL}/status" 2>/dev/null || true)
    if [ -n "$STATUS" ]; then
        READY=$(echo "$STATUS" | jq -r '.value.ready // false' 2>/dev/null || echo "false")
        if [ "$READY" = "true" ]; then
            echo "## Grid is ready (attempt $i/$RETRY_ATTEMPTS)"
            break
        fi
    fi
    if [ "$i" -eq "$RETRY_ATTEMPTS" ]; then
        echo "ERROR: Grid not ready after $RETRY_ATTEMPTS attempts"
        exit 1
    fi
    echo "## Grid not ready, retrying in ${RETRY_DELAY}s (attempt $i/$RETRY_ATTEMPTS)..."
    sleep "$RETRY_DELAY"
done

SUCCESS=0

# Test a browser session: create, verify, delete
# Usage: test_browser <browser_name> <capabilities_json>
test_browser() {
    local BROWSER="$1"
    local CAPS="$2"

    echo "## Testing $BROWSER session..."

    RESPONSE=$(curl -sf --connect-timeout 30 --max-time 120 \
        -X POST "${GRID_URL}/session" \
        -H "Content-Type: application/json" \
        -d "$CAPS" 2>&1) || {
        echo "ERROR: Failed to create $BROWSER session"
        echo "$RESPONSE"
        return 1
    }

    SESSION_ID=$(echo "$RESPONSE" | jq -r '.value.sessionId // empty' 2>/dev/null)
    if [ -z "$SESSION_ID" ]; then
        echo "ERROR: No session ID returned for $BROWSER"
        echo "$RESPONSE"
        return 1
    fi

    echo "## $BROWSER session created: $SESSION_ID"

    # Clean up session
    curl -sf --connect-timeout 10 --max-time 30 \
        -X DELETE "${GRID_URL}/session/${SESSION_ID}" > /dev/null 2>&1 || true

    echo "## $BROWSER session deleted successfully"
    return 0
}

# Test Chrome
CHROME_CAPS='{"capabilities":{"alwaysMatch":{"browserName":"chrome","goog:chromeOptions":{"args":["--headless","--no-sandbox","--disable-dev-shm-usage"]}}}}'
if ! test_browser "Chrome" "$CHROME_CAPS"; then
    SUCCESS=1
fi

# Test Firefox
FIREFOX_CAPS='{"capabilities":{"alwaysMatch":{"browserName":"firefox","moz:firefoxOptions":{"args":["-headless"]}}}}'
if ! test_browser "Firefox" "$FIREFOX_CAPS"; then
    SUCCESS=1
fi

if [ $SUCCESS -eq 0 ]; then
    echo "## Smoke test PASSED: Chrome and Firefox sessions verified"
else
    echo "## Smoke test FAILED"
fi

exit $SUCCESS
