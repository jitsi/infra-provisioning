#!/bin/bash
#
# Install one Google Chrome channel plus a ChromeDriver whose major version
# matches it, and register both with upstream generate_config.
#
# Usage: install-chrome-channel.sh <stable|beta>
#
# The Selenium base images ship at most one chromedriver, matched to whatever
# browser that image happens to carry. Both of our channels are installed from
# Google's apt repo at build time, so neither is guaranteed to match -- and
# ChromeDriver enforces a major-version match. Each channel therefore gets its
# own driver resolved from Chrome for Testing.
#
# Fails the build if no matching driver can be resolved, rather than leaving a
# stereotype that only breaks at session-creation time in the nightly run.

set -eu

CHANNEL="${1:?usage: install-chrome-channel.sh <stable|beta>}"
CFT_BASE="https://googlechromelabs.github.io/chrome-for-testing"

case "$CHANNEL" in
  stable) BROWSER_DIR="chrome";      CFT_CHANNEL="Stable" ;;
  beta)   BROWSER_DIR="chrome_beta"; CFT_CHANNEL="Beta" ;;
  *) echo "FATAL: unknown channel '$CHANNEL' (expected stable or beta)"; exit 1 ;;
esac

PKG="google-chrome-${CHANNEL}"
BIN="/usr/bin/${PKG}"
DRIVER_PATH="/opt/selenium/chromedriver-${CHANNEL}"

DPKG_ARCH="$(dpkg --print-architecture)"
case "$DPKG_ARCH" in
  amd64) CFT_PLATFORM="linux64" ;;
  arm64) CFT_PLATFORM="linux-arm64" ;;
  *) echo "FATAL: unsupported architecture '$DPKG_ARCH'"; exit 1 ;;
esac

#-------------------------------------------------------------------
# Google's apt repo. Present already on the Chrome base images, absent
# on node-chromium (which installs Chromium from Debian sid), so add it
# idempotently rather than assuming either way.
#-------------------------------------------------------------------
if [ ! -f /etc/apt/sources.list.d/google-chrome.list ]; then
  echo "Adding Google Chrome apt repository for ${DPKG_ARCH}"
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
  chmod 644 /etc/apt/keyrings/google-chrome.gpg
  echo "deb [arch=${DPKG_ARCH} signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list
fi

#-------------------------------------------------------------------
# Browser. --only-upgrade is deliberately NOT used: we want whatever the
# repo currently offers, installed fresh, then frozen into the image.
#-------------------------------------------------------------------
apt-get update -qqy
apt-get -qqy --no-install-recommends install "$PKG"
apt-mark hold "$PKG"

# Stop the cron-driven updater and the in-browser one. apt-mark hold only
# covers the apt path; Chrome also reads managed policy at launch.
rm -f /etc/cron.daily/google-chrome
mkdir -p /etc/opt/chrome/policies/managed
printf '{"AutoUpdateCheckPeriodMinutes": 0, "UpdateDefault": 0}\n' \
  > /etc/opt/chrome/policies/managed/no-update.json

rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# "Google Chrome 153.0.8010.12 beta" / "Google Chrome 152.0.7977.64" -> field 3.
# Anchored on the known field rather than "first dotted number anywhere": both
# BROWSER_MAJOR and the driver-major assertion derive from this value, so a bad
# parse would move both sides together and the assertion could not catch it.
BROWSER_VERSION="$("$BIN" --version | awk '{print $3}')"
if ! echo "$BROWSER_VERSION" | grep -qE '^[0-9]+(\.[0-9]+){3}$'; then
  echo "FATAL: could not parse a version from: $("$BIN" --version)"
  exit 1
fi
BROWSER_BUILD="$(echo "$BROWSER_VERSION" | cut -d. -f1-3)"
BROWSER_MAJOR="$(echo "$BROWSER_VERSION" | cut -d. -f1)"
echo "Installed ${PKG} ${BROWSER_VERSION} (build ${BROWSER_BUILD}, ${DPKG_ARCH})"

#-------------------------------------------------------------------
# Matching ChromeDriver from Chrome for Testing.
#   1. the exact build
#   2. the latest build of the same major (a major match is all
#      ChromeDriver requires)
#   3. the channel's current release
#-------------------------------------------------------------------
curl -sSf -o /tmp/cft-builds.json "${CFT_BASE}/latest-patch-versions-per-build-with-downloads.json"

DRIVER_URL="$(jq -r --arg b "$BROWSER_BUILD" --arg p "$CFT_PLATFORM" \
  '.builds[$b].downloads.chromedriver[]? | select(.platform == $p) | .url' \
  /tmp/cft-builds.json)"

if [ -z "$DRIVER_URL" ]; then
  echo "No ChromeDriver for build ${BROWSER_BUILD}, trying the latest ${BROWSER_MAJOR}.x build"
  DRIVER_URL="$(jq -r --arg m "$BROWSER_MAJOR" --arg p "$CFT_PLATFORM" \
    '[.builds | to_entries[] | select(.key | startswith($m + "."))]
     | sort_by(.value.version | split(".") | map(tonumber)) | last
     | .value.downloads.chromedriver[]? | select(.platform == $p) | .url' \
    /tmp/cft-builds.json)"
fi

if [ -z "$DRIVER_URL" ]; then
  echo "No ChromeDriver for major ${BROWSER_MAJOR}, trying the ${CFT_CHANNEL} channel"
  curl -sSf -o /tmp/cft-channels.json "${CFT_BASE}/last-known-good-versions-with-downloads.json"
  DRIVER_URL="$(jq -r --arg c "$CFT_CHANNEL" --arg p "$CFT_PLATFORM" \
    '.channels[$c].downloads.chromedriver[]? | select(.platform == $p) | .url' \
    /tmp/cft-channels.json)"
fi

if [ -z "$DRIVER_URL" ]; then
  echo "FATAL: Chrome for Testing publishes no ${CFT_PLATFORM} ChromeDriver for ${PKG} ${BROWSER_VERSION}."
  echo "       linux-arm64 drivers exist from Chrome 153 onwards only."
  exit 1
fi

echo "Using ChromeDriver from ${DRIVER_URL}"
curl -sSfL -o /tmp/chromedriver.zip "$DRIVER_URL"
rm -rf /tmp/chromedriver-extract
python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
  /tmp/chromedriver.zip /tmp/chromedriver-extract
find /tmp/chromedriver-extract -type f -name chromedriver -exec mv {} "$DRIVER_PATH" \;
rm -rf /tmp/chromedriver-extract /tmp/chromedriver.zip /tmp/cft-builds.json /tmp/cft-channels.json
chmod 755 "$DRIVER_PATH"

DRIVER_VERSION="$("$DRIVER_PATH" --version | awk '{print $2}')"
if [ "$(echo "$DRIVER_VERSION" | cut -d. -f1)" != "$BROWSER_MAJOR" ]; then
  echo "FATAL: ChromeDriver ${DRIVER_VERSION} does not match ${PKG} ${BROWSER_VERSION}"
  exit 1
fi
echo "ChromeDriver ${DRIVER_VERSION} matches ${PKG} ${BROWSER_VERSION}"

#-------------------------------------------------------------------
# Browser metadata for upstream generate_config. It walks
# /opt/selenium/browsers/*/ and emits one stereotype per directory.
#-------------------------------------------------------------------
mkdir -p "/opt/selenium/browsers/${BROWSER_DIR}"
echo "chrome" > "/opt/selenium/browsers/${BROWSER_DIR}/name"
echo "$BROWSER_VERSION" > "/opt/selenium/browsers/${BROWSER_DIR}/version"
echo "$DRIVER_VERSION" > "/opt/selenium/browsers/${BROWSER_DIR}/driver_version"
echo "{\"goog:chromeOptions\": {\"binary\": \"\${SE_BROWSER_BINARY_LOCATION:-${BIN}}\"}}" \
  > "/opt/selenium/browsers/${BROWSER_DIR}/binary_location"

chown -R "${SEL_UID}:${SEL_GID}" "/opt/selenium/browsers/${BROWSER_DIR}"
chown "${SEL_UID}:${SEL_GID}" "$DRIVER_PATH"
