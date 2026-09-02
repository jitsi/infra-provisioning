#!/bin/bash
#
# Single source of truth for the Selenium Grid version.
#
# Sourced by:
#   docker/selenium-grid-node/build.sh       -> --build-arg SELENIUM_VERSION
#                                               (node image base: selenium/node-chromium:$SELENIUM_VERSION)
#   scripts/deploy-nomad-selenium-grid-hub.sh -> NOMAD_VAR_selenium_version
#                                               (hub image: selenium/hub:$SELENIUM_VERSION)
#
# Keeping both in step matters: the hub used to be pinned to a release while the
# nodes tracked :nightly, so the two drifted onto different Grid versions with
# nothing recording which node image contained which Selenium build.
#
# An already-exported SELENIUM_VERSION wins, so a Jenkins parameter or a one-off
# build can override this without editing the file.
#
# This is deliberately NOT in clouds/all.sh: that path is a symlink into the
# separate infra-customizations-private repo, and this pins tooling rather than
# environment configuration.
#
# Browser versions are intentionally a separate axis. Chrome stable and beta are
# installed from Google's apt repo at image build time and get their drivers from
# Chrome for Testing, so browsers advance on a rebuild without moving this value.

export SELENIUM_VERSION="${SELENIUM_VERSION:-4.47}"
