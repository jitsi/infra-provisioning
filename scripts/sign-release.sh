#!/bin/bash
# -*- coding: utf-8 -*-
# Sample script to GPG sign Release files
# Copyright © 2002 Colin Walters <walters@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# Usage:

# You need to create a secret keyring (secring.gpg).  You can use your
# existing one, or create a new one by doing something like the
# following:

# $ GNUPGHOME=/src/debian/mini-dinstall/s3kr1t gnupg --gen-key

set -e

# User variables
# MAKE SURE TO MAKE THIS DIRECTORY 0700!
[ -z "$GNUPGHOME" ] && export GNUPGHOME="/home/jenkins/jitsi/gnupg-jitsi"
if [ ! -d "$GNUPGHOME" ]; then
    mkdir -p "$GNUPGHOME"
fi
if [ -z "$USER" ]; then
    USER=$(id -n -u)
fi
# This is just a default value
#KEYID=$(getent passwd $USER | cut -f 5 -d : | cut -f 1 -d ,)
# KEYID is the legacy signing key (DSA-1024 "SIP Communicator", 2008). Kept for backward
# compatibility with existing clients.
[ -z "$KEYID" ] && KEYID="SIP Communicator"
# NEW_KEYID is the modern signing key (RSA-4096 / Ed25519). When set AND present in the
# keyring, we additionally emit a dual-signed InRelease so Debian Trixie / APT 3.0 (which
# rejects the legacy DSA-1024 + SHA-1 key outright) can verify the repo via the modern key.
# Until it is provisioned this stays empty and signing behaves exactly as before. See JIT-15930.
NEW_KEYID="${NEW_KEYID:-}"
PASSPHRASE=$(cat "$GNUPGHOME/passphrase")
# These should fail if for some reason the directory isn't owned by us
chown "$USER" "$GNUPGHOME"
chmod 0700 "$GNUPGHOME"
# Initialize GPG
gpg --help 1>/dev/null 2>&1 || true

# mini-dinstall invokes this script with the Release file as $1, from the distribution
# directory; emit signatures alongside it.
RELEASE="$1"
RELEASE_DIR=$(dirname "$RELEASE")

gpg_sign() {
    # Wrapper that feeds the passphrase on fd 0; remaining args are passed to gpg.
    echo "$PASSPHRASE" | gpg --no-tty --batch --pinentry-mode loopback --passphrase-fd=0 "$@"
}

# 1) Detached Release.gpg, signed by the legacy key only.
#    APT 3.0 (Sequoia sqv) cannot parse a detached signature file that contains a DSA
#    signature ("unsupported binary format"), so we deliberately keep this single-key and
#    let Trixie/modern clients verify via InRelease below. Older clients without InRelease
#    support continue to use this. See JIT-15930.
rm -f "$RELEASE_DIR/Release.gpg.tmp"
gpg_sign --default-key "$KEYID" --detach-sign -o "$RELEASE_DIR/Release.gpg.tmp" "$RELEASE"
mv "$RELEASE_DIR/Release.gpg.tmp" "$RELEASE_DIR/Release.gpg"

# 2) Inline-signed InRelease. Modern APT prefers InRelease over Release+Release.gpg, and
#    unlike a detached signature it tolerates a DSA signature packet sitting next to a good
#    RSA one. When a modern key is configured we dual-sign with SHA-256 so existing clients
#    verify via the legacy key and Trixie verifies via the modern key.
if [ -n "$NEW_KEYID" ] && gpg --list-keys "$NEW_KEYID" >/dev/null 2>&1; then
    rm -f "$RELEASE_DIR/InRelease.tmp"
    gpg_sign --digest-algo SHA256 -u "$KEYID" -u "$NEW_KEYID" --clearsign -o "$RELEASE_DIR/InRelease.tmp" "$RELEASE"
    mv "$RELEASE_DIR/InRelease.tmp" "$RELEASE_DIR/InRelease"
else
    # No modern key provisioned yet: preserve the previous behaviour exactly (Release.gpg
    # only, no InRelease) so this change is a no-op until NEW_KEYID is configured.
    echo "sign-release.sh: NEW_KEYID not set; skipping InRelease (Trixie support disabled). See JIT-15930." >&2
fi