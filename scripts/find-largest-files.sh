#!/bin/bash

# Script to SSH into a specified instance and find the top 20 largest files and directories

set -e

usage() {
    echo "Usage: $0 <instance-ip> [ssh-user] [ssh-key]"
    echo ""
    echo "Arguments:"
    echo "  instance-ip  IP address of the instance to connect to"
    echo "  ssh-user     SSH user (default: ubuntu)"
    echo "  ssh-key      Path to SSH key (optional, uses default SSH key if not specified)"
    echo ""
    echo "Example:"
    echo "  $0 10.0.1.50"
    echo "  $0 10.0.1.50 root"
    echo "  $0 10.0.1.50 ubuntu ~/.ssh/my-key.pem"
    exit 1
}

if [[ -z "$1" ]]; then
    echo "Error: Instance IP is required"
    usage
fi

INSTANCE_IP="$1"
SSH_USER="${2:-ubuntu}"
SSH_KEY="${3:-}"

# Build SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
if [[ -n "$SSH_KEY" ]]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

echo "Connecting to $SSH_USER@$INSTANCE_IP..."
echo ""

ssh $SSH_OPTS "$SSH_USER@$INSTANCE_IP" bash -s << 'REMOTE_SCRIPT'
echo "=========================================="
echo "Top 20 Largest Files"
echo "=========================================="
sudo find / -xdev -type f -exec du -h {} + 2>/dev/null | sort -rh | head -20

echo ""
echo "=========================================="
echo "Top 20 Largest Directories"
echo "=========================================="
sudo du -h --max-depth=3 / 2>/dev/null | sort -rh | head -20

echo ""
echo "=========================================="
echo "Disk Usage Summary"
echo "=========================================="
df -h
REMOTE_SCRIPT

echo ""
echo "Done."
