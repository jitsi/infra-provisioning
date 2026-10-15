#!/bin/bash

# Git mirror sync script
# Syncs configured repositories from remote sources to local bare repos

set -e

export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

# Start ssh-agent if key exists
if [ -f ~/.ssh/id_rsa ]; then
    eval "$(ssh-agent -s)" > /dev/null
    trap "kill $SSH_AGENT_PID 2>/dev/null" EXIT
    ssh-add ~/.ssh/id_rsa 2>/dev/null
fi

GIT_BASE_PATH="${GIT_BASE_PATH:-/home/git}"

if [ -z "$GIT_MIRROR_REPOS" ]; then
    echo "[$(date)] ERROR: GIT_MIRROR_REPOS environment variable is not set"
    exit 1
fi

IFS=',' read -ra REPOS <<< "$GIT_MIRROR_REPOS"

ERRORS=0

for repo in "${REPOS[@]}"; do
    # Trim whitespace
    repo=$(echo "$repo" | xargs)
    [ -z "$repo" ] && continue

    # Parse repo URL - extract org/name from git@github.com:org/name.git or https://github.com/org/name.git
    if [[ "$repo" =~ \.git$ ]]; then
        repo_name=$(echo "$repo" | sed -E 's|.*[:/]([^/]+/[^/]+)\.git$|\1|')
    else
        repo_name=$(echo "$repo" | sed -E 's|.*[:/]([^/]+/[^/]+)$|\1|')
    fi

    local_path="${GIT_BASE_PATH}/${repo_name}.git"

    echo "[$(date)] Syncing $repo -> $local_path"

    if [ ! -d "$local_path" ]; then
        echo "  Initializing bare repo..."
        mkdir -p "$(dirname "$local_path")"
        if ! git clone --mirror "$repo" "$local_path"; then
            echo "  ERROR: Failed to clone $repo"
            ERRORS=$((ERRORS + 1))
            continue
        fi
    else
        cd "$local_path"
        if ! git remote update --prune; then
            echo "  ERROR: Failed to update $repo"
            ERRORS=$((ERRORS + 1))
            continue
        fi
    fi
    echo "  OK"
done

echo "[$(date)] Sync complete (errors: $ERRORS)"
exit $ERRORS
