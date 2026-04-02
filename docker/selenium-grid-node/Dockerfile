FROM selenium/node-all-browsers:nightly

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
  mkdir -p /defaults

COPY --chown="${SEL_UID}:${SEL_GID}" config.toml.tpl driver_config.toml.tpl /defaults/

#============================================
# Custom scripts: cleanup, config generation, lang packs
#============================================
COPY --chown="${SEL_UID}:${SEL_GID}" firefox-cleanup.sh get_lang_package.sh install-firefox-apt.sh generate_config /opt/bin/
COPY --chown="${SEL_UID}:${SEL_GID}" firefox-cleanup.conf /etc/supervisor/conf.d/firefox-cleanup.conf
COPY --chown="${SEL_UID}:${SEL_GID}" chrome-cleanup.sh /opt/bin/chrome-cleanup.sh
COPY --chown="${SEL_UID}:${SEL_GID}" chrome-cleanup.conf /etc/supervisor/conf.d/chrome-cleanup.conf
RUN chmod +x /opt/bin/firefox-cleanup.sh /opt/bin/get_lang_package.sh /opt/bin/install-firefox-apt.sh /opt/bin/generate_config /opt/bin/chrome-cleanup.sh

# Bust cache for all dynamic-version installs below
ARG CACHEBUST=1

#============================================
# Chrome Beta (amd64 only)
#============================================
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
    apt-get update -qqy \
    && apt-get -qqy --no-install-recommends install google-chrome-beta \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*; \
  fi

#============================================
# Firefox language packs
#============================================
RUN /opt/bin/get_lang_package.sh

#============================================
# Additional utilities
#============================================
RUN apt-get update -y && apt-get install -y iproute2 && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

USER ${SEL_UID}
