# amd64: Chrome only (Firefox installed via apt below)
FROM --platform=linux/amd64 selenium/node-chrome:nightly AS base-amd64

# arm64: Chromium only (Firefox installed via apt below)
FROM --platform=linux/arm64 selenium/node-chromium:nightly AS base-arm64

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

COPY --chown="${SEL_UID}:${SEL_GID}" get_lang_package.sh install-firefox-apt.sh /opt/bin/
RUN chmod +x /opt/bin/get_lang_package.sh /opt/bin/install-firefox-apt.sh

# Patch upstream generate_config to use full browser versions instead of short (major.minor)
RUN sed -i 's/echo "${__major}.${__minor:0:1}"/echo "${__long_version}"/' /opt/bin/generate_config

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
      && apt install -y firefox$FIREFOX_VERSION firefox-beta \
      && INSTALL_VIA_APT=true \
      && if [ "$FIREFOX_VERSION" = "-beta" ] || [ "$FIREFOX_VERSION" = "-nightly" ] || [ "$FIREFOX_VERSION" = "-devedition" ] || [ "$FIREFOX_VERSION" = "-esr" ]; then \
        ln -fs $(which firefox$FIREFOX_VERSION) /usr/bin/firefox ; \
      fi ; \
    else \
      FIREFOX_DOWNLOAD_URL="https://download-installer.cdn.mozilla.net/pub/firefox/releases/$FIREFOX_VERSION/linux-x86_64/en-US/firefox-$FIREFOX_VERSION.tar.bz2" ; \
    fi \
  else \
    if [ "$FIREFOX_VERSION" = "nightly-latest" ]; then \
      /opt/bin/install-firefox-apt.sh \
      && FIREFOX_VERSION=$(echo "-$FIREFOX_VERSION" | sed 's/-latest//') \
      && apt install -y firefox$FIREFOX_VERSION \
      && INSTALL_VIA_APT=true \
      && if [ "$FIREFOX_VERSION" = "-nightly" ]; then \
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
  && echo "Downloading Firefox language packs" \
  && /opt/bin/get_lang_package.sh \
  && apt-get update -qqy \
  && apt-get upgrade -yq \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

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

USER ${SEL_UID}
