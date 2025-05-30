
#!/bin/bash
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "## ssh user not defined, using current user: $SSH_USER"
else
  SSH_USER=$1
  echo "## will ssh as $SSH_USER"
fi

echo "## rotate-consul-pre-detch: getting private IP"
INSTANCE_PRIMARY_PRIVATE_IP=$(oci compute instance list-vnics --region $ORACLE_REGION --instance-id $INSTANCE_ID | jq -r '.data[] | select(.["is-primary"] == true) | .["private-ip"]')
if [ "$INSTANCE_PRIMARY_PRIVATE_IP" == "null" ]; then
    echo "## ERROR: no private IP found, something went wrong with rotation $INSTANCE_ID in $ORACLE_REGION"
    exit 1
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# first archive the keyring material from the old server if nomad version is less than 1.9
echo "## rotate-consul-pre-detach: checking for nomad keyring material from $INSTANCE_PRIMARY_PRIVATE_IP"
export ARCHIVE_KEYRING="true"
timeout 120 ssh -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP  "[ \$(nomad --version | head -1 | awk '{print $2}' | cut -d '.' -f2) -ge 9 ] && echo 'nomad version is 1.9 or greater, no keyring needed' && exit 1 || sudo tar -czf /tmp/nomad-keyring.tar.gz /var/nomad/server/keystore"
RET=$?
if [[ $RET -gt 0 ]]; then
    if [ $RET -eq 1 ]; then
        echo "## rotate-consul-pre-detach: nomad version is 1.9 or greater, no keyring archival needed"
        export ARCHIVE_KEYRING="false"
    else
        echo "## ERROR archiving nomad keyring material on $INSTANCE_PRIMARY_PRIVATE_IP with code $RET"
    fi
fi

if [ "$ARCHIVE_KEYRING" == "true" ]; then
    echo "## rotate-consul-pre-detach: copying nomad keyring material from $INSTANCE_PRIMARY_PRIVATE_IP"
    scp -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP:/tmp/nomad-keyring.tar.gz ./nomad-keyring.tar.gz || echo "## failed to copy nomad keyring material from $INSTANCE_PRIMARY_PRIVATE_IP"
    ## now delete the remote copy
    echo "## rotate-consul-pre-detach: deleting /tmp archived nomad keyring material from $INSTANCE_PRIMARY_PRIVATE_IP"
    timeout 120 ssh -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP "sudo rm -f /tmp/nomad-keyring.tar.gz"
fi

echo "## rotate-consul-pre-detach shutting down nomad service on $INSTANCE_PRIMARY_PRIVATE_IP with user $SSH_USER"

timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP "nomad node eligibility -self -disable && nomad node drain -self -enable -detach -yes"
if [[ $RET -gt 0 ]]; then
    echo "## ERROR draining nomad on $INSTANCE_PRIMARY_PRIVATE_IP with code $RET"
fi
echo -e "\n## rotate-consul-pre-detach: waiting for nomad drain to complete before stopping nomad and consul on $INSTANCE_PRIMARY_PRIVATE_IP"
sleep 120
timeout 120 ssh -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP "nomad node drain -self -enable -force -detach -yes && sleep 20 && sudo service nomad stop"
RET=$?
if [[ $RET -gt 0 ]]; then
    echo "## ERROR stopping nomad on $INSTANCE_PRIMARY_PRIVATE_IP with code $RET"
fi

echo "## rotate-consul-pre-detach graceful consul leave on $INSTANCE_PRIMARY_PRIVATE_IP with user $SSH_USER"
timeout 120 ssh -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP "sudo consul leave"
RET=$?
if [[ $RET -gt 0 ]]; then
    echo "## ERROR stopping consul on $INSTANCE_PRIMARY_PRIVATE_IP with code $RET"
fi

echo "## rotate-consul-pre-detach shutting down consul service on $INSTANCE_PRIMARY_PRIVATE_IP with user $SSH_USER"
timeout 120 ssh -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP "sudo service consul stop"
RET=$?
if [[ $RET -gt 0 ]]; then
    echo "## ERROR stopping consul on $INSTANCE_PRIMARY_PRIVATE_IP with code $RET"
fi
