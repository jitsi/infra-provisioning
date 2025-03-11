FROM selenium/node-base

USER root


## tpl and config templates
RUN \
  dpkgArch="$(dpkg --print-architecture)" && \
  case "${dpkgArch##*-}" in \
    "amd64") TPL_ARCH=amd64;; \
    "arm64") TPL_ARCH=arm64;; \
    *) echo "unsupported architecture"; exit 1 ;; \
  esac && \
  wget -qO /usr/bin/tpl https://github.com/jitsi/tpl/releases/download/v1.4.0/tpl-linux-${TPL_ARCH} && \
  chmod +x /usr/bin/tpl && \
  mkdir /defaults

COPY --chown="${SEL_UID}:${SEL_GID}" config.toml.tpl driver_config.toml.tpl /defaults/

#============================================
# Firefox cleanup script and supervisord file
#============================================
COPY --chown="${SEL_UID}:${SEL_GID}" firefox-cleanup.sh get_lang_package.sh install-firefox-apt.sh generate_config /opt/bin/
COPY --chown="${SEL_UID}:${SEL_GID}" firefox-cleanup.conf /etc/supervisor/conf.d/firefox-cleanup.conf
RUN chmod +x /opt/bin/firefox-cleanup.sh /opt/bin/get_lang_package.sh /opt/bin/install-firefox-apt.sh /opt/bin/generate_config

#=========
# Firefox
#=========
ARG FIREFOX_VERSION="latest"
ARG FIREFOX_DOWNLOAD_URL="https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64-aarch64&lang=en-US"
RUN apt-get update -y && \
  echo "Using Firefox version: $FIREFOX_VERSION" && \
  if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
    if [ $FIREFOX_VERSION = "latest" ] || [ $FIREFOX_VERSION = "beta-latest" ] || [ $FIREFOX_VERSION = "nightly-latest" ] || [ $FIREFOX_VERSION = "devedition-latest" ] || [ $FIREFOX_VERSION = "esr-latest" ]; then \
      FIREFOX_DOWNLOAD_URL="https://download.mozilla.org/?product=firefox-$FIREFOX_VERSION-ssl&os=linux64&lang=en-US"; \
      /opt/bin/install-firefox-apt.sh \
      && FIREFOX_VERSION=$(echo "-$FIREFOX_VERSION" | sed 's/-latest//') \
      && apt install -y firefox$FIREFOX_VERSION firefox-beta \
      && INSTALL_VIA_APT=true \
      && if [ $FIREFOX_VERSION = "-beta" ] || [ $FIREFOX_VERSION = "-nightly" ] || [ $FIREFOX_VERSION = "-devedition" ] || [ $FIREFOX_VERSION = "-esr" ]; then \
        ln -fs $(which firefox$FIREFOX_VERSION) /usr/bin/firefox ; \
      fi ; \
    else \
      FIREFOX_DOWNLOAD_URL="https://download-installer.cdn.mozilla.net/pub/firefox/releases/$FIREFOX_VERSION/linux-x86_64/en-US/firefox-$FIREFOX_VERSION.tar.bz2" ; \
    fi \
  else \
    if [ $FIREFOX_VERSION = "nightly-latest" ]; then \
      /opt/bin/install-firefox-apt.sh \
      && FIREFOX_VERSION=$(echo "-$FIREFOX_VERSION" | sed 's/-latest//') \
      && apt install -y firefox$FIREFOX_VERSION \
      && INSTALL_VIA_APT=true \
      && if [ $FIREFOX_VERSION = "-nightly" ]; then \
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
  # Do one more upgrade to fix possible CVEs from Firefox dependencies
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
# Google Chrome
#============================================
# can specify versions by CHROME_VERSION;
#  e.g. google-chrome-stable
#       google-chrome-beta
#       google-chrome-unstable
#============================================
ARG CHROME_VERSION="google-chrome-stable"
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then echo "installing chrome on x86_64"; else echo "skipping chrome on arm64" && exit 0; fi \
  && wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor | tee /etc/apt/trusted.gpg.d/google.gpg >/dev/null \
  && echo "deb http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
  && apt-get update -qqy \
  && if echo "${CHROME_VERSION}" | grep -qE "google-chrome-stable[_|=][0-9]*"; \
    then \
      CHROME_VERSION=$(echo "$CHROME_VERSION" | tr '=' '_') \
      && wget -qO google-chrome.deb "https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/${CHROME_VERSION}_$(dpkg --print-architecture).deb" \
      && apt-get -qqy --no-install-recommends install --allow-downgrades ./google-chrome.deb \
      && rm -rf google-chrome.deb ; \
    else \
      apt-get -qqy --no-install-recommends install ${CHROME_VERSION} google-chrome-beta ; \
    fi \
  && rm /etc/apt/sources.list.d/google-chrome.list \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/*


#=================================
# Chrome Launch Script Wrapper
#=================================
COPY ./wrap_chrome_binary /opt/bin/wrap_chrome_binary
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then echo "wrap_chrome_binary on x86_64"; else echo "skipping wrap_chrome_binary on arm64" && exit 0; fi \
  && /opt/bin/wrap_chrome_binary

#============================================
# Chrome webdriver
#============================================
# can specify versions by CHROME_DRIVER_VERSION
# Latest released version will be used by default
#============================================
ARG CHROME_DRIVER_VERSION
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
  DRIVER_ARCH=$(if [ "$(dpkg --print-architecture)" = "amd64" ]; then echo "linux64"; else echo "linux-aarch64"; fi) \
  && if [ ! -z "$CHROME_DRIVER_VERSION" ]; \
  then CHROME_DRIVER_URL=https://storage.googleapis.com/chrome-for-testing-public/$CHROME_DRIVER_VERSION/${DRIVER_ARCH}/chromedriver-${DRIVER_ARCH}.zip ; \
  else CHROME_MAJOR_VERSION=$(google-chrome --version | sed -E "s/.* ([0-9]+)(\.[0-9]+){3}.*/\1/") \
    && echo "Geting ChromeDriver latest version from https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_${CHROME_MAJOR_VERSION}" \
    && CHROME_DRIVER_VERSION=$(wget -qO- https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_${CHROME_MAJOR_VERSION} | sed 's/\r$//') \
    && CHROME_DRIVER_URL=https://storage.googleapis.com/chrome-for-testing-public/$CHROME_DRIVER_VERSION/${DRIVER_ARCH}/chromedriver-${DRIVER_ARCH}.zip ; \
  fi \
  && echo "Using ChromeDriver from: "$CHROME_DRIVER_URL \
  && echo "Using ChromeDriver version: "$CHROME_DRIVER_VERSION \
  && wget --no-verbose -O /tmp/chromedriver_${DRIVER_ARCH}.zip $CHROME_DRIVER_URL \
  && rm -rf /opt/selenium/chromedriver \
  && unzip /tmp/chromedriver_${DRIVER_ARCH}.zip -d /opt/selenium \
  && rm /tmp/chromedriver_${DRIVER_ARCH}.zip \
  && mv /opt/selenium/chromedriver-${DRIVER_ARCH}/chromedriver /opt/selenium/chromedriver-$CHROME_DRIVER_VERSION \
  && chmod 755 /opt/selenium/chromedriver-$CHROME_DRIVER_VERSION \
  && ln -fs /opt/selenium/chromedriver-$CHROME_DRIVER_VERSION /usr/bin/chromedriver; \
  else echo "skipping chromedriver on arm64" && exit 0; fi

#============================================
# Chrome cleanup script and supervisord file
#============================================
COPY ./chrome-cleanup.sh /opt/bin/chrome-cleanup.sh
COPY ./chrome-cleanup.conf /etc/supervisor/conf.d/chrome-cleanup.conf
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then echo "skipping chromium on x86_64" && exit 0; else sed -i -e 's/chrome\/chrome/chromium\/chromium/' /opt/bin/chrome-cleanup.sh; fi

# Install Chromium
ARG CHROMIUM_VERSION="latest"
ARG CHROMIUM_DEB_SITE="https://deb.debian.org/debian"
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
    echo "skipping chromium on x86_64" && exit 0; \
  else \
    echo "installing chromium on arm64" \
    && apt-get update -y \
    && apt-get install -y software-properties-common \
    && add-apt-repository ppa:xtradeb/apps \
    && apt-get update -y \
    && apt-get install -y chromium chromium-driver; \
  fi

#=================================
# Chromium Launch Script Wrapper
#=================================
COPY wrap_chromium_binary /opt/bin/wrap_chromium_binary
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then echo "skipping wrap_chromium_binary on x86_64" && exit 0; else echo "wrap_chromium_binary on arm64"; fi \
  && /opt/bin/wrap_chromium_binary

#============================================
# Chromium cleanup script and supervisord file
#============================================
COPY chrome-cleanup.sh /opt/bin/chrome-cleanup.sh
COPY chrome-cleanup.conf /etc/supervisor/conf.d/chrome-cleanup.conf

RUN apt-get update -y && apt-get install -y iproute2

USER ${SEL_UID}