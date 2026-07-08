#!/bin/bash

# cleanup-cdn-r2-versions.sh
#
# Prunes old build folders from the Cloudflare R2 CDN bucket (v1/_cdn/*),
# which accumulates one folder per published branding build
# (see publish-branding-cdn.sh, e.g. v1/_cdn/meet8x8com_4570.1272).
#
# Retention policy, applied independently per version-prefix family
# (meet8x8com_, meetjitsi_, ...):
#   - a version is IN USE if any signal shard in any scanned environment
#     serves a base.html that points at it
#   - keep every in-use version
#   - keep every version newer than the oldest in-use version (they may
#     still be promoted later)
#   - keep the newest $CDN_KEEP_ROLLBACK (default 5) versions older than
#     the oldest in-use version, as rollback targets that outlive their
#     original releases
#   - delete everything older than those
#   - a prefix family with no in-use version found anywhere is skipped
#     entirely (fail safe: we cannot tell "unused" from "not scanned")
#   - folders that do not look like build versions (auth-static/, ...) are
#     never touched
#
# DRY RUN by default: prints what would be deleted. Pass --delete (or set
# CDN_CLEANUP_CONFIRM=true) to actually purge.
#
# The scanned environments default to every sites/*/vars.yml with
# jitsi_meet_cdn_cloudflare_enabled: true. Because prefix families are
# shared across environments (e.g. meet8x8com_ serves prod-8x8, stage-8x8
# and jitsi-net), overriding ENVIRONMENTS to a subset risks deleting a
# version another environment still uses — only do that if you know the
# prefix families do not overlap.

set -e

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

CONFIG_VARS_PATH="$LOCAL_PATH/../config/vars.yml"

DELETE_MODE="false"
[[ "$1" == "--delete" ]] && DELETE_MODE="true"
[[ "$CDN_CLEANUP_CONFIRM" == "true" ]] && DELETE_MODE="true"

[ -z "$CDN_KEEP_ROLLBACK" ] && CDN_KEEP_ROLLBACK=5
[ -z "$CDN_R2_BUCKET" ] && CDN_R2_BUCKET="$(yq '.cdn_r2_bucket' < $CONFIG_VARS_PATH)"
[ -z "$CDN_R2_ROOT" ] && CDN_R2_ROOT="v1/_cdn"

if [ -z "$CDN_R2_BUCKET" ] || [ "$CDN_R2_BUCKET" == "null" ]; then
    echo "No CDN_R2_BUCKET found, exiting..."
    exit 1
fi

if [ -z "$ANSIBLE_SSH_USER" ]; then
    ANSIBLE_SSH_USER=$(whoami)
fi

# rclone remote for the R2 bucket, same credentials as publish-branding-cdn.sh
[ -z "$RCLONE_CONFIG_PATH" ] && RCLONE_CONFIG_PATH="$HOME/.config/rclone/rclone.conf"
CREATED_RCLONE_CONFIG="false"
if [ ! -e "$RCLONE_CONFIG_PATH" ]; then
    R2_SECRETS_PATH="$LOCAL_PATH/../ansible/secrets/r2-bucket.yml"
    [ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"
    R2_ACCESS_KEY_ID="$(ansible-vault view $R2_SECRETS_PATH --vault-password $VAULT_PASSWORD_FILE | yq eval ".r2_access_key_id" -)"
    R2_SECRET_ACCESS_KEY="$(ansible-vault view $R2_SECRETS_PATH --vault-password $VAULT_PASSWORD_FILE | yq eval ".r2_secret_access_key" -)"
    R2_ENDPOINT_URL="$(ansible-vault view $R2_SECRETS_PATH --vault-password $VAULT_PASSWORD_FILE | yq eval ".r2_endpoint_url" -)"
    mkdir -p "$(dirname $RCLONE_CONFIG_PATH)"
    cat > "$RCLONE_CONFIG_PATH" <<EOF
[default]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY_ID
secret_access_key = $R2_SECRET_ACCESS_KEY
endpoint = $R2_ENDPOINT_URL
bucket_acl = private
no_check_bucket = true
EOF
    CREATED_RCLONE_CONFIG="true"
fi

function cleanup_rclone_config() {
    [[ "$CREATED_RCLONE_CONFIG" == "true" ]] && rm -f "$RCLONE_CONFIG_PATH"
}
trap cleanup_rclone_config EXIT

# version folders look like <prefix><meet>.<branding> (meet8x8com_4570.1272)
# or a bare meet version (4679); anything else (auth-static, ...) is untouchable
VERSION_FOLDER_REGEX='^([A-Za-z0-9]+_)?[0-9]+(\.[0-9]+)?$'

# sortable fixed-width key from "<meet>[.<branding>]"
function version_key() {
    local major="${1%%.*}"
    local minor="${1#*.}"
    [[ "$minor" == "$1" ]] && minor=0
    printf "%012d.%012d" "$major" "$minor"
}

# --- 1. find in-use versions across environments ---------------------------

if [ -z "$ENVIRONMENTS" ]; then
    for SITE_VARS in $LOCAL_PATH/../sites/*/vars.yml; do
        CDN_CLOUDFLARE_FLAG=$(yq eval '.jitsi_meet_cdn_cloudflare_enabled' $SITE_VARS | tail -1)
        if [[ "$CDN_CLOUDFLARE_FLAG" == "true" ]]; then
            ENVIRONMENTS="$ENVIRONMENTS $(basename $(dirname $SITE_VARS))"
        fi
    done
fi

if [ -z "$ENVIRONMENTS" ]; then
    echo "No ENVIRONMENTS with jitsi_meet_cdn_cloudflare_enabled found, exiting..."
    exit 1
fi

echo "## scanning environments for in-use CDN versions:$ENVIRONMENTS"

IN_USE_FOLDERS=""
for ENV in $ENVIRONMENTS; do
    # DOMAIN must be cleared inside the subshell: stack-env.sh only sets it
    # when unset, so a value carried over from the previous environment would
    # win and every shard query would hit the wrong domain
    DOMAIN=$(DOMAIN=""; . $LOCAL_PATH/../sites/$ENV/stack-env.sh > /dev/null 2>&1; echo $DOMAIN)
    if [ -z "$DOMAIN" ]; then
        echo "## ERROR: no DOMAIN for environment $ENV, exiting without deleting anything"
        exit 1
    fi

    # the prefix family this environment publishes to, used to sanity-check
    # what the shards report back
    EXPECTED_PREFIX=$(yq eval '.jitsi_meet_cdn_prefix' $LOCAL_PATH/../sites/$ENV/vars.yml | tail -1)
    [[ "$EXPECTED_PREFIX" == "null" ]] && EXPECTED_PREFIX=""

    # shard.sh list honors SHARDS_FROM_CONSUL: default (false) enumerates via
    # shard.py (needs cloud credentials, the mode Jenkins jobs use); true asks
    # consul directly
    SHARDS=$(RELEASE_NUMBER="" ENVIRONMENT="$ENV" $LOCAL_PATH/shard.sh list $ANSIBLE_SSH_USER)
    ENV_FOLDERS=""
    for SHARD in $SHARDS; do
        BASE_HTML=$(curl --silent --insecure --max-time 10 "https://$DOMAIN/$SHARD/base.html" || true)
        # base href is either host-relative (/v1/_cdn/<folder>/) or the legacy
        # absolute form (https://web-cdn.jitsi.net/<folder>/)
        FOLDER=$(echo "$BASE_HTML" | sed -e 's|.*web-cdn.jitsi.net/||' -e 's|.*/v1/_cdn/||' -e 's|/".*||')
        if [[ "$FOLDER" =~ $VERSION_FOLDER_REGEX ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$EXPECTED_PREFIX" ]]; then
                ENV_FOLDERS="$ENV_FOLDERS $FOLDER"
            else
                echo "## WARNING: $ENV shard $SHARD reports CDN folder '$FOLDER' but $ENV publishes prefix '${EXPECTED_PREFIX:-<none>}'; ignoring it (check DOMAIN/shard routing)"
            fi
        else
            echo "## WARNING: could not extract CDN version from $ENV shard $SHARD (got '$FOLDER')"
        fi
    done

    ENV_FOLDERS=$(echo $ENV_FOLDERS | tr ' ' '\n' | sort -u)
    if [ -z "$ENV_FOLDERS" ]; then
        if [[ " $CDN_CLEANUP_ALLOW_EMPTY " == *" $ENV "* ]]; then
            echo "## WARNING: no in-use CDN versions found for $ENV, allowed by CDN_CLEANUP_ALLOW_EMPTY"
        else
            echo "## ERROR: no in-use CDN versions found for $ENV; refusing to clean up anything."
            echo "## if $ENV legitimately has no shards, add it to CDN_CLEANUP_ALLOW_EMPTY"
            exit 1
        fi
    else
        echo "## $ENV in use: "$ENV_FOLDERS
        IN_USE_FOLDERS="$IN_USE_FOLDERS $ENV_FOLDERS"
    fi
done

IN_USE_FOLDERS=$(echo $IN_USE_FOLDERS | tr ' ' '\n' | sort -u)

# --- 2. list version folders in the bucket ---------------------------------

ALL_FOLDERS=$(rclone lsf --dirs-only "default:$CDN_R2_BUCKET/$CDN_R2_ROOT/" | sed 's|/$||')

CANDIDATE_FOLDERS=""
PREFIXES=""
for FOLDER in $ALL_FOLDERS; do
    if [[ "$FOLDER" =~ $VERSION_FOLDER_REGEX ]]; then
        CANDIDATE_FOLDERS="$CANDIDATE_FOLDERS $FOLDER"
        PREFIX="${BASH_REMATCH[1]}"
        PREFIXES="$PREFIXES ${PREFIX:-<none>}"
    else
        echo "## skipping non-version folder: $FOLDER"
    fi
done
PREFIXES=$(echo $PREFIXES | tr ' ' '\n' | sort -u)

# --- 3. apply retention per prefix family -----------------------------------

DELETE_LIST=""
for PREFIX in $PREFIXES; do
    [[ "$PREFIX" == "<none>" ]] && PREFIX=""

    # this family's folders in the bucket, oldest first
    FAMILY=""
    for FOLDER in $CANDIDATE_FOLDERS; do
        [[ "$FOLDER" =~ $VERSION_FOLDER_REGEX ]] || continue
        [[ "${BASH_REMATCH[1]}" == "$PREFIX" ]] || continue
        FAMILY="$FAMILY $(version_key ${FOLDER#$PREFIX})|$FOLDER"
    done
    FAMILY=$(echo $FAMILY | tr ' ' '\n' | sort)

    # oldest in-use version in this family
    OLDEST_IN_USE_KEY=""
    for FOLDER in $IN_USE_FOLDERS; do
        [[ "$FOLDER" =~ $VERSION_FOLDER_REGEX ]] || continue
        [[ "${BASH_REMATCH[1]}" == "$PREFIX" ]] || continue
        KEY=$(version_key ${FOLDER#$PREFIX})
        if [ -z "$OLDEST_IN_USE_KEY" ] || [[ "$KEY" < "$OLDEST_IN_USE_KEY" ]]; then
            OLDEST_IN_USE_KEY="$KEY"
        fi
    done

    if [ -z "$OLDEST_IN_USE_KEY" ]; then
        echo "## prefix '${PREFIX:-<none>}': no in-use versions found in any scanned environment, skipping family"
        continue
    fi

    # everything below the oldest in-use version, oldest first; keep the
    # newest CDN_KEEP_ROLLBACK of them as rollback targets, delete the rest
    OLDER=""
    for ENTRY in $FAMILY; do
        KEY="${ENTRY%%|*}"
        [[ "$KEY" < "$OLDEST_IN_USE_KEY" ]] && OLDER="$OLDER $ENTRY"
    done
    OLDER_COUNT=$(echo $OLDER | wc -w | tr -d ' ')
    DELETE_COUNT=$((OLDER_COUNT - CDN_KEEP_ROLLBACK))
    [ "$DELETE_COUNT" -lt 0 ] && DELETE_COUNT=0

    echo "## prefix '${PREFIX:-<none>}': $(echo $FAMILY | wc -w | tr -d ' ') folders, $OLDER_COUNT older than oldest in-use, keeping $CDN_KEEP_ROLLBACK rollback versions, deleting $DELETE_COUNT"

    if [ "$DELETE_COUNT" -gt 0 ]; then
        FAMILY_DELETES=$(echo $OLDER | tr ' ' '\n' | head -n $DELETE_COUNT | cut -d'|' -f2)
        DELETE_LIST="$DELETE_LIST $FAMILY_DELETES"
    fi
done

# --- 4. delete (or report) ---------------------------------------------------

DELETE_LIST=$(echo $DELETE_LIST | tr ' ' '\n' | sort)
if [ -z "$DELETE_LIST" ]; then
    echo "## nothing to delete"
    exit 0
fi

echo "## folders to delete from $CDN_R2_BUCKET/$CDN_R2_ROOT:"
echo "$DELETE_LIST"

if [[ "$DELETE_MODE" != "true" ]]; then
    echo "## DRY RUN: no deletions performed; re-run with --delete to purge"
    exit 0
fi

for FOLDER in $DELETE_LIST; do
    echo "## purging $CDN_R2_BUCKET/$CDN_R2_ROOT/$FOLDER"
    rclone purge --transfers 64 --checkers 64 --fast-list "default:$CDN_R2_BUCKET/$CDN_R2_ROOT/$FOLDER"
done

echo "## CDN R2 cleanup complete"
