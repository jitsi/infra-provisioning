
BOOTSTRAP_DIRECTORY="/tmp/bootstrap"
LOCAL_REPO_DIRECTORY="/opt/jitsi/bootstrap"

# Oracle team says it should take maximum 4 minutes until the networking is up
# This function will only try 2 times, which should last around ~ 1 minute
# check_private_ip will be retried multiple times
function check_private_ip() {
  local counter=1
  local ip_status=1

  while [ $counter -le 2 ]; do
    local my_private_ip=$(curl -s curl http://169.254.169.254/opc/v1/vnics/ | jq .[0].privateIp -r)

    if [ -z $my_private_ip ] || [ $my_private_ip == "null" ]; then
      sleep 30
      ((counter++))
    else
      ip_status=0
      break
    fi
  done

  if [ $ip_status -eq 1 ]; then
    echo "Private IP still not available status: $ip_status" > $tmp_msg_file
    return 1
  else
    return 0
  fi
}


function retry() {
  local n=0
  RETRIES=$2
  [ -z "$RETRIES" ] && RETRIES=5
  until [ $n -ge $RETRIES ]
  do
    # call the function given as parameter
    $1
    # check the result of the function
    if [ $? -eq 0 ]; then
      # success
      > $tmp_msg_file
      break
    else
      # failure, therefore retry
      n=$[$n+1]

      # only sleep if we're not going to be done with the loop
      if [ $n -lt $RETRIES ]; then
        sleep 10
      fi
    fi
  done

  if [ $n -eq $RETRIES ]; then
    return $n
  else
    return 0;
  fi
}



function add_ip_tags() {
    . /usr/local/bin/oracle_cache.sh
    vnic_id=$(curl -s curl http://169.254.169.254/opc/v1/vnics/ | jq .[0].vnicId -r)
    vnic_details_result=$(oci network vnic get --vnic-id "$vnic_id" --auth instance_principal)
    if [ $? -eq 0 ]; then
        PUBLIC_IP=$(echo "$vnic_details_result" | jq -r '.data["public-ip"]')

        PRIVATE_IP=$(echo "$vnic_details_result" | jq -r '.data["private-ip"]')

        IMAGE=$(curl -s curl http://169.254.169.254/opc/v1/instance/ | jq -r '.image')
        [ "$IMAGE" == "null" ] && IMAGE=""
        [ ! -z "$IMAGE" ] && IMAGE_ITEM=", \"image\": \"$IMAGE\""

        [ "$PUBLIC_IP" == "null" ] && PUBLIC_IP=""
        [ ! -z "$PUBLIC_IP" ] && PUBLIC_IP_ITEM=", \"public_ip\": \"$PUBLIC_IP\""

        ITEM="{\"private_ip\": \"$PRIVATE_IP\"${PUBLIC_IP_ITEM}${IMAGE_ITEM}}"

        INSTANCE_METADATA=`$OCI_BIN compute instance get --instance-id $INSTANCE_ID | jq .`
        INSTANCE_ETAG=$(echo $INSTANCE_METADATA | jq -r '.etag')
        NEW_FREEFORM_TAGS=$(echo $INSTANCE_METADATA | jq --argjson ITEM "$ITEM" '.data["freeform-tags"] += $ITEM' | jq '.data["freeform-tags"]')
        $OCI_BIN compute instance update --instance-id $INSTANCE_ID --freeform-tags "$NEW_FREEFORM_TAGS" --if-match "$INSTANCE_ETAG" --force
    else
      return 2
    fi
}

function fetch_credentials() {
  ENVIRONMENT=$1
  BUCKET="jvb-bucket-${ENVIRONMENT}"
  $OCI_BIN os object get -bn $BUCKET --name vault-password --file /root/.vault-password
  $OCI_BIN os object get -bn $BUCKET --name id_rsa_jitsi_deployment --file /root/.ssh/id_rsa
  chmod 400 /root/.ssh/id_rsa
}

function clean_credentials() {
  rm /root/.vault-password /root/.ssh/id_rsa
}

function set_hostname() {
  TYPE=$1
  MY_HOSTNAME=$2

  MY_IP=`curl -s curl http://169.254.169.254/opc/v1/vnics/ | jq .[0].privateIp -r`

  if [ -z "$MY_HOSTNAME" ]; then
    #clear domain if null
    [ "$DOMAIN" == "null" ] && DOMAIN=
    [ -z "$DOMAIN" ] && DOMAIN="oracle.jitsi.net"
    MY_COMPONENT_NUMBER="$(echo $MY_IP | awk -F. '{print $2"-"$3"-"$4}')"
    MY_HOSTNAME="$CLOUD_NAME-$TYPE-$MY_COMPONENT_NUMBER.$DOMAIN"
  fi

  hostname $MY_HOSTNAME
  grep $MY_HOSTNAME /etc/hosts || echo "$MY_IP    $MY_HOSTNAME" >> /etc/hosts
}

function checkout_repos() {
  [ -d $BOOTSTRAP_DIRECTORY/infra-configuration ] && rm -rf $BOOTSTRAP_DIRECTORY/infra-configuration
  [ -d $BOOTSTRAP_DIRECTORY/infra-customizations ] && rm -rf $BOOTSTRAP_DIRECTORY/infra-customizations

  if [ ! -n "$(grep "^github.com " ~/.ssh/known_hosts)" ]; then ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null; fi

  if [ -d "$LOCAL_REPO_DIRECTORY" ]; then
    echo "Found local repo copies in $LOCAL_REPO_DIRECTORY, using instead of clone"
    cp -a $LOCAL_REPO_DIRECTORY/infra-configuration $BOOTSTRAP_DIRECTORY
    cp -a $LOCAL_REPO_DIRECTORY/infra-customizations $BOOTSTRAP_DIRECTORY
    cd $BOOTSTRAP_DIRECTORY/infra-configuration
    git pull
    cd -
    cd $BOOTSTRAP_DIRECTORY/infra-customizations
    git pull
    cd -
  else
    echo "No local repos found, cloning directly from github"
    git clone $INFRA_CONFIGURATION_REPO $BOOTSTRAP_DIRECTORY/infra-configuration
    git clone $INFRA_CUSTOMIZATIONS_REPO $BOOTSTRAP_DIRECTORY/infra-customizations
  fi

  cd $BOOTSTRAP_DIRECTORY/infra-configuration
  git checkout $GIT_BRANCH
  git submodule update --init --recursive
  git show-ref heads/$GIT_BRANCH || git show-ref tags/$GIT_BRANCH
  cd -
  cd $BOOTSTRAP_DIRECTORY/infra-customizations
  git checkout $GIT_BRANCH
  git submodule update --init --recursive
  git show-ref heads/$GIT_BRANCH || git show-ref tags/$GIT_BRANCH
  cp -a $BOOTSTRAP_DIRECTORY/infra-customizations/* $BOOTSTRAP_DIRECTORY/infra-configuration
  cd -
}

function run_ansible_playbook() {
    cd $BOOTSTRAP_DIRECTORY/infra-configuration
    PLAYBOOK=$1
    VARS=$2
    DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}

    ansible-playbook -v \
        -i "127.0.0.1," \
        -c local \
        --tags "$DEPLOY_TAGS" \
        --extra-vars "$VARS" \
        --vault-password-file=/root/.vault-password \
        ansible/$PLAYBOOK || status_code=1

    if [ $status_code -eq 1 ]; then
        echo 'Provisioning stage failed' > $tmp_msg_file;
    fi

    cd -
    return $status_code
}

function ansible_pull() {
    PLAYBOOK=$1
    GIT_BRANCH=$2
    VARS=$3

    status_code=0

    DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}

    ansible-pull -v -U git@github.com:8x8Cloud/jitsi-video-infrastructure.git -v -d /tmp/bootstrap \
        --purge -i "127.0.0.1," --vault-password-file=/root/.vault-password --accept-host-key -C "$GIT_BRANCH" \
        --tags "$DEPLOY_TAGS" \
        --extra-vars "$VARS" \
        ansible/$PLAYBOOK || status_code=1

    if [ $status_code -eq 1 ]; then
        echo 'Provisioning stage failed' > $tmp_msg_file;
    fi
    return $status_code
}

function default_dump() {
  sudo /usr/local/bin/dump-boot.sh
}

function default_main() {
  [ -z "$PROVISION_COMMAND" ] && PROVISION_COMMAND="default_provision"
  [ -z "$CLEAN_CREDENTIALS" ] && CLEAN_CREDENTIALS="true"
  EXIT_CODE=0
  ( retry check_private_ip && retry add_ip_tags && retry $PROVISION_COMMAND ) ||  EXIT_CODE=1
  if [ "$CLEAN_CREDENTIALS" == "true" ]; then
    clean_credentials
  fi
  return $EXIT_CODE
}

function default_provision() {
  local status_code=0

  . /usr/local/bin/oracle_cache.sh
  fetch_credentials $ENVIRONMENT

  [ -z "$HOST_ROLE" ] && HOST_ROLE="$SHARD_ROLE"
  if [ -z "$HOST_ROLE" ]; then
    echo "No HOST_ROLE role set"
    return 1
  fi

  if [ -z "$ANSIBLE_PLAYBOOK" ]; then
    echo "No ANSIBLE_PLAYBOOK set"
    return 2
  fi

  if [ -z "$ANSIBLE_VARS" ]; then
    echo "No ANSIBLE_VARS set"
    return 3
  fi

  # set_hostname will build name like lonely-us-phoenix-1-consul-77-122-23.oracle.jitsi.net for 10.77.122.23
  set_hostname "$HOST_ROLE" "$MY_HOSTNAME"

  if [ -z "$INFRA_CONFIGURATION_REPO" ]; then
    ansible_pull "$ANSIBLE_PLAYBOOK" "$GIT_BRANCH" "$ANSIBLE_VARS" || status_code=1
  else
    checkout_repos
    run_ansible_playbook "$ANSIBLE_PLAYBOOK"  "$ANSIBLE_VARS" || status_code=1
  fi

  return $status_code;
}

function default_terminate() {
  echo "Terminating the instance; we enable debug to have more details in case of oci cli failures"
  INSTANCE_ID=`curl --connect-timeout 10 -s curl http://169.254.169.254/opc/v1/instance/ | jq -r .id`
  sudo /usr/local/bin/oci compute instance terminate --debug --instance-id "$INSTANCE_ID" --preserve-boot-volume false --auth instance_principal --force
  RET=$?
  # infinite loop on failure
  if [ $RET -gt 0 ]; then
    echo "Failed to terminate instance, exit code: $RET, sleeping 10 then retrying"
    sleep 10
    default_terminate
  fi
}
# end of postinstall-lib, this space intentionally left blank
