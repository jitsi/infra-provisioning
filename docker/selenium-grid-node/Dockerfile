# arm64 only. Google now ships Chrome for linux-arm64 (stable, beta and canary
# debs are in the apt repo) and Chrome for Testing publishes linux-arm64
# chromedrivers from Chrome 153 onwards, so the amd64 half of this image is no
# longer needed -- both browser channels run natively on ARM nodes.
#
# SELENIUM_VERSION pins the Grid version for the node image; the same variable
# feeds the hub image (see scripts/selenium-version.sh) so the
# two cannot drift apart. Previously this tracked :nightly, which meant the node
# Selenium version -- and the stable browser -- changed silently on every rebuild.
ARG SELENIUM_VERSION=4.47
FROM selenium/node-chromium:${SELENIUM_VERSION}

USER root

#============================================
# Custom cleanup scripts
#============================================
COPY --chown="${SEL_UID}:${SEL_GID}" firefox-cleanup.sh /opt/bin/firefox-cleanup.sh
COPY --chown="${SEL_UID}:${SEL_GID}" firefox-cleanup.conf /etc/supervisor/conf.d/firefox-cleanup.conf
COPY --chown="${SEL_UID}:${SEL_GID}" chrome-cleanup.sh /opt/bin/chrome-cleanup.sh
COPY --chown="${SEL_UID}:${SEL_GID}" chrome-cleanup.conf /etc/supervisor/conf.d/chrome-cleanup.conf
RUN chmod +x /opt/bin/firefox-cleanup.sh /opt/bin/chrome-cleanup.sh

COPY --chown="${SEL_UID}:${SEL_GID}" get_lang_package.sh install-firefox-apt.sh install-chrome-channel.sh /opt/bin/
RUN chmod +x /opt/bin/get_lang_package.sh /opt/bin/install-firefox-apt.sh /opt/bin/install-chrome-channel.sh

# Patch upstream generate_config:
#   - short_version returns the full version (not major.minor[0])
#   - keep browserVersion as the channel (stable/beta) instead of overwriting with the numeric version
#   - add se:browserVersion to the stereotype JSON with the actual numeric version
RUN sed -i 's/echo "${__major}.${__minor:0:1}"/echo "${__long_version}"/' /opt/bin/generate_config \
    && sed -i 's|SE_NODE_BROWSER_VERSION=$(short_version "$(cat "${browser_dir}version")")|:|' /opt/bin/generate_config \
    && sed -i 's|\\"$(hostname)\\"}|\\"$(hostname)\\", \\"se:browserVersion\\": \\"$(cat "${browser_dir}version" 2>/dev/null)\\"}|' /opt/bin/generate_config

# Bust cache for all dynamic-version installs below
ARG CACHEBUST=1

# Freeze the base image's Chromium so the CVE upgrade in the Firefox step below
# cannot roll it forward. It is no longer the browser behind any stereotype --
# the "chrome" browser dir it created is overwritten by the stable channel
# install below -- but it stays installed as part of the base image.
RUN apt-mark hold chromium || true

#============================================
# Google Chrome stable + beta, each with a version-matched ChromeDriver
#
# Both channels come from Google's apt repo at build time, the way Chrome Beta
# and Firefox already did, rather than from the base image. That decouples
# browser versions from SELENIUM_VERSION: a rebuild picks up current Chrome
# without moving the Grid version, and vice versa. The base image is not a
# usable source for stable anyway -- docker-selenium had published no Chrome 152
# images weeks after 152 went stable.
#
# Each channel gets its own driver because ChromeDriver enforces a major-version
# match and the two channels are always a major apart. The build fails loudly if
# a matching driver cannot be resolved.
#============================================
RUN /opt/bin/install-chrome-channel.sh stable
RUN /opt/bin/install-chrome-channel.sh beta

#=========
# Firefox
#=========
ARG FIREFOX_VERSION="latest"
ARG FIREFOX_DOWNLOAD_URL="https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64-aarch64&lang=en-US"
RUN apt-get update -y && \
  echo "Using Firefox version: $FIREFOX_VERSION" && \
  if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
    if [ "$FIREFOX_VERSION" = "latest" ] || [ "$FIREFOX_VERSION" = "beta-latest" ] || [ "$FIREFOX_VERSION" = "nightly-latest" ] || [ "$FIREFOX_VERSION" = "devedition-latest" ] || [ "$FIREFOX_VERSION" = "esr-latest" ]; then \
      FIREFOX_DOWNLOAD_URL="https://download.mozilla.org/?product=firefox-$FIREFOX_VERSION-ssl&os=linux64&lang=en-US"; \
      /opt/bin/install-firefox-apt.sh \
      && FIREFOX_VERSION=$(echo "-$FIREFOX_VERSION" | sed 's/-latest//') \
      && apt install -y firefox$FIREFOX_VERSION \
      && (apt install -y firefox-beta || true) \
      && INSTALL_VIA_APT=true \
      && if [ "$FIREFOX_VERSION" = "-beta" ] || [ "$FIREFOX_VERSION" = "-nightly" ] || [ "$FIREFOX_VERSION" = "-devedition" ] || [ "$FIREFOX_VERSION" = "-esr" ]; then \
        ln -fs $(which firefox$FIREFOX_VERSION) /usr/bin/firefox ; \
      fi ; \
    else \
      FIREFOX_DOWNLOAD_URL="https://download-installer.cdn.mozilla.net/pub/firefox/releases/$FIREFOX_VERSION/linux-x86_64/en-US/firefox-$FIREFOX_VERSION.tar.bz2" ; \
    fi \
  else \
    if [ "$FIREFOX_VERSION" = "latest" ] || [ "$FIREFOX_VERSION" = "beta-latest" ] || [ "$FIREFOX_VERSION" = "nightly-latest" ] || [ "$FIREFOX_VERSION" = "devedition-latest" ] || [ "$FIREFOX_VERSION" = "esr-latest" ]; then \
      /opt/bin/install-firefox-apt.sh \
      && FIREFOX_VERSION=$(echo "-$FIREFOX_VERSION" | sed 's/-latest//') \
      && apt install -y firefox$FIREFOX_VERSION \
      && (apt install -y firefox-beta || true) \
      && INSTALL_VIA_APT=true \
      && if [ "$FIREFOX_VERSION" = "-beta" ] || [ "$FIREFOX_VERSION" = "-nightly" ] || [ "$FIREFOX_VERSION" = "-devedition" ] || [ "$FIREFOX_VERSION" = "-esr" ]; then \
        ln -fs $(which firefox$FIREFOX_VERSION) /usr/bin/firefox ; \
      fi ; \
    else \
      FIREFOX_DOWNLOAD_URL="${FIREFOX_DOWNLOAD_URL}" ; \
    fi ; \
  fi && \
  echo "Using Firefox download URL: $FIREFOX_DOWNLOAD_URL" && \
  if [ "$INSTALL_VIA_APT" != "true" ]; then \
    echo "Installing firefox dependencies" \
    && apt-get -y --no-install-recommends install libavcodec-extra libgtk-3-dev libdbus-glib-1-dev xz-utils \
    && echo "Grabbing firefox from URL" \
    && wget -S -O /tmp/firefox.tar.xz $FIREFOX_DOWNLOAD_URL \
    && rm -rf /opt/firefox \
    && tar -C /opt -xvf /tmp/firefox.tar.xz \
    && rm -rf /tmp/firefox.tar.xz \
    && mv /opt/firefox /opt/firefox-$FIREFOX_VERSION \
    && mkdir -p /opt/firefox-$FIREFOX_VERSION/distribution/extensions \
    && ln -fs /opt/firefox-$FIREFOX_VERSION/firefox /usr/bin/firefox ; \
  fi \
  && echo "Downloading Firefox lanuage packs" \
  # Download the language pack for Firefox
  && /opt/bin/get_lang_package.sh \
  # Pin Firefox (and firefox-beta when present) so the CVE upgrade below
  # doesn't roll them forward; freezes the apt-installed version into the image.
  && (apt-mark hold firefox || true) \
  && (apt-mark hold firefox-beta || true) \
  # Disable Firefox's in-app updater (Mozilla AUS) — apt-mark hold doesn't
  # cover it. Both firefox and firefox-beta read this policy file.
  && mkdir -p /etc/firefox/policies \
  && printf '{"policies": {"DisableAppUpdate": true}}\n' > /etc/firefox/policies/policies.json \
  # Do one more upgrade to fix possible CVEs from Firefox dependencies
  && apt-get update -qqy \
  && apt-get upgrade -yq \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

#============================================
# Firefox + Firefox Beta browser metadata for upstream generate_config
#============================================
RUN mkdir -p /opt/selenium/browsers/firefox \
    && echo "firefox" > /opt/selenium/browsers/firefox/name \
    && firefox --version | awk '{print $3}' > /opt/selenium/browsers/firefox/version \
    && echo '{"moz:firefoxOptions": {"binary": "${SE_BROWSER_BINARY_LOCATION:-/usr/bin/firefox}"}}' > /opt/selenium/browsers/firefox/binary_location \
    && chown -R ${SEL_UID}:${SEL_GID} /opt/selenium/browsers/firefox \
    && if command -v firefox-beta >/dev/null 2>&1; then \
      mkdir -p /opt/selenium/browsers/firefox_beta \
      && echo "firefox" > /opt/selenium/browsers/firefox_beta/name \
      && firefox-beta --version | awk '{print $3}' > /opt/selenium/browsers/firefox_beta/version \
      && echo '{"moz:firefoxOptions": {"binary": "${SE_BROWSER_BINARY_LOCATION:-/usr/bin/firefox-beta}"}}' > /opt/selenium/browsers/firefox_beta/binary_location \
      && chown -R ${SEL_UID}:${SEL_GID} /opt/selenium/browsers/firefox_beta; \
    fi

#============
# GeckoDriver
#============
ARG GECKODRIVER_VERSION=latest
RUN LATEST_VERSION=$(curl -sk https://api.github.com/repos/mozilla/geckodriver/releases/latest | jq -r '.tag_name') \
  && DRIVER_ARCH=$(if [ "$(dpkg --print-architecture)" = "amd64" ]; then echo "linux64"; else echo "linux-aarch64"; fi) \
  && GK_VERSION=$(if [ ${GECKODRIVER_VERSION:-latest} = "latest" ]; then echo "${LATEST_VERSION}"; else echo $GECKODRIVER_VERSION; fi) \
  && echo "Using GeckoDriver version: "$GK_VERSION \
  && wget --no-verbose -O /tmp/geckodriver.tar.gz https://github.com/mozilla/geckodriver/releases/download/${GK_VERSION}/geckodriver-${GK_VERSION}-${DRIVER_ARCH}.tar.gz \
  && rm -rf /opt/geckodriver \
  && tar -C /opt -zxf /tmp/geckodriver.tar.gz \
  && rm /tmp/geckodriver.tar.gz \
  && mv /opt/geckodriver /opt/geckodriver-$GK_VERSION \
  && chmod 755 /opt/geckodriver-$GK_VERSION \
  && ln -fs /opt/geckodriver-$GK_VERSION /usr/bin/geckodriver

#============================================
# Additional utilities
#============================================
RUN apt-get update -y && apt-get install -y iproute2 && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# Per-browser channel labels — read by the patched generate_config so each stereotype's
# browserVersion reflects the channel (jitsi-stable/jitsi-beta) instead of the upstream default.
# Avoid the literal "stable" string — Selenium Grid's DefaultSlotMatcher treats a request
# browserVersion of "stable" as a wildcard that matches any stereotype (see SeleniumHQ
# selenium#15481, Step 6), which would let "stable" requests land on beta-stereotype slots.
ENV SE_NODE_BROWSER_VERSION_CHROME=jitsi-stable \
    SE_NODE_BROWSER_VERSION_CHROME_BETA=jitsi-beta \
    SE_NODE_BROWSER_VERSION_FIREFOX=jitsi-stable \
    SE_NODE_BROWSER_VERSION_FIREFOX_BETA=jitsi-beta

# Point each chrome stereotype at its own version-matched ChromeDriver. Neither
# channel can use the base image's driver now: both are installed from Google's
# apt repo, so neither is guaranteed to match what the base shipped.
#
# generate_config resolves the _CHROME / _CHROME_BETA suffixes per browser
# directory (same mechanism as SE_NODE_BROWSER_VERSION_*) and json-merges these
# into that stereotype only. Selenium reads se:webDriverExecutable off the
# stereotype in LocalNodeFactory and passes it to
# DriverService.Builder.usingDriverExecutable().
ENV SE_NODE_STEREOTYPE_EXTRA_CHROME='{"se:webDriverExecutable": "/opt/selenium/chromedriver-stable"}' \
    SE_NODE_STEREOTYPE_EXTRA_CHROME_BETA='{"se:webDriverExecutable": "/opt/selenium/chromedriver-beta"}'

USER ${SEL_UID}
