#!/bin/bash

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ssh as $ANSIBLE_SSH_USER"
fi

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

[ -z "$REMOUNT_ROLE" ] && REMOUNT_ROLE="consul"

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"

if [ -z "$INVENTORY_FILE" ]; then
    INVENTORY_FILE="./remap.inventory"
    $LOCAL_PATH/node.py --environment=$ENVIRONMENT --role $REMOUNT_ROLE --batch > $INVENTORY_FILE
fi

for i in $(cat $INVENTORY_FILE); do
    echo "remounting $i"
    scp terraform/lib/postinstall-lib.sh $ANSIBLE_SSH_USER@$i:/tmp/postinstall-lib.sh
    echo -e '#!/bin/bash\nVOLUMES_ENABLED="true"\nexport OCI_BIN=/usr/local/bin/oci\n. /tmp/postinstall-lib.sh\nmount_volumes\n' | ssh $ANSIBLE_SSH_USER@$i "cat > ./remount-boot-volumes.sh"
    ssh $ANSIBLE_SSH_USER@$i "chmod +x ./remount-boot-volumes.sh && sudo ./remount-boot-volumes.sh && rm /tmp/postinstall-lib.sh ./remount-boot-volumes.sh"
done