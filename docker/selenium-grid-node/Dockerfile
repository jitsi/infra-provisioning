# amd64: all browsers (Chrome, Chromium, Firefox, Edge)
FROM --platform=linux/amd64 selenium/node-all-browsers:nightly AS base-amd64

# arm64: Chromium + Firefox (real native arm64 images layered)
# node-all-browsers arm64 manifest is fake (contains amd64 binaries), so we
# build from node-chromium and layer Firefox on top
FROM --platform=linux/arm64 selenium/node-chromium:nightly AS base-arm64-chromium
FROM --platform=linux/arm64 selenium/node-firefox:nightly AS base-arm64-firefox-donor

# Layer Firefox + GeckoDriver from the Firefox image onto the Chromium base
FROM base-arm64-chromium AS base-arm64
# Firefox is installed via apt into /usr/lib/firefox/ and /usr/bin/firefox
COPY --from=base-arm64-firefox-donor /usr/lib/firefox/ /usr/lib/firefox/
COPY --from=base-arm64-firefox-donor /usr/bin/firefox /usr/bin/firefox
# GeckoDriver
COPY --from=base-arm64-firefox-donor /opt/geckodriver* /opt/
COPY --from=base-arm64-firefox-donor /usr/bin/geckodriver /usr/bin/geckodriver
# Selenium browser metadata for Firefox
COPY --from=base-arm64-firefox-donor /opt/selenium/browsers/firefox/ /opt/selenium/browsers/firefox/

# Select the correct base for the target platform
FROM base-${TARGETARCH}

USER root

#============================================
# Custom cleanup scripts
#============================================
COPY --chown="${SEL_UID}:${SEL_GID}" firefox-cleanup.sh /opt/bin/firefox-cleanup.sh
COPY --chown="${SEL_UID}:${SEL_GID}" firefox-cleanup.conf /etc/supervisor/conf.d/firefox-cleanup.conf
COPY --chown="${SEL_UID}:${SEL_GID}" chrome-cleanup.sh /opt/bin/chrome-cleanup.sh
COPY --chown="${SEL_UID}:${SEL_GID}" chrome-cleanup.conf /etc/supervisor/conf.d/chrome-cleanup.conf
RUN chmod +x /opt/bin/firefox-cleanup.sh /opt/bin/chrome-cleanup.sh

# Bust cache for all dynamic-version installs below
ARG CACHEBUST=1

#============================================
# Chrome Beta (amd64 only) + browser metadata for upstream generate_config
#============================================
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
    apt-get update -qqy \
    && apt-get -qqy --no-install-recommends install google-chrome-beta \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* \
    && mkdir -p /opt/selenium/browsers/chrome_beta \
    && echo "chrome" > /opt/selenium/browsers/chrome_beta/name \
    && google-chrome-beta --version | awk '{print $4}' > /opt/selenium/browsers/chrome_beta/version \
    && echo '{"goog:chromeOptions": {"binary": "${SE_BROWSER_BINARY_LOCATION:-/usr/bin/google-chrome-beta}"}}' > /opt/selenium/browsers/chrome_beta/binary_location \
    && chown -R ${SEL_UID}:${SEL_GID} /opt/selenium/browsers/chrome_beta; \
  fi

#============================================
# Additional utilities
#============================================
RUN apt-get update -y && apt-get install -y iproute2 && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

USER ${SEL_UID}
