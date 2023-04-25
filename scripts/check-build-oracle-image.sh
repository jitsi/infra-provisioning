#!/bin/bash
#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

[ -z "$ORACLE_REGION" ] && ORACLE_REGION=$DEFAULT_ORACLE_REGION

[ -z "$IMAGE_ARCH" ] && IMAGE_ARCH="x86_64"

# #pull in region-specific variables
# [ -e "../all/regions/${ORACLE_REGION}-oracle.sh" ] && . ../all/regions/${ORACLE_REGION}-oracle.sh

function checkImage() {
    IMAGE_TYPE=$1
    IMAGE_VERSION=$2
    IMAGE_ARCH=$3

    EXISTING_IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type $IMAGE_TYPE --version "$IMAGE_VERSION" --region="$ORACLE_REGION" --architecture "$IMAGE_ARCH" --compartment_id="$TENANCY_OCID" --tag_namespace="$TAG_NAMESPACE")

    if [ ! -z "$EXISTING_IMAGE_OCID" ]; then
        IMAGE_OCID="$EXISTING_IMAGE_OCID"
        return 0
    fi

    return 1
}

case $IMAGE_TYPE in
    # do nothing for known types, to check for them all at once if needful
    'JVB')
        ;;
    'Signal')
        ;;
    'Jigasi')
        ;;
    'JavaJibri')
        ;;
    *)
        checkImage "$IMAGE_TYPE" "latest" "$IMAGE_ARCH"
        if [ $? -eq 0 ]; then
          IMAGE_EXISTS="true"
          echo "$IMAGE_TYPE $ORACLE_REGION: $IMAGE_OCID"
        else
          IMAGE_EXISTS="false"
        fi
        export IMAGE_EXISTS
        ;;
esac

if [ ! -z "$JVB_VERSION" ]; then
    checkImage "JVB" "$JVB_VERSION" "$IMAGE_ARCH"
    if [ $? -eq 0 ]; then
      JVB_IMAGE_EXISTS="true"
      JVB_IMAGE_OCID="$IMAGE_OCID"
      echo "JVB $ORACLE_REGION: $JVB_IMAGE_OCID"
    else
      JVB_IMAGE_EXISTS="false"
    fi
    export JVB_IMAGE_OCID
    export JVB_IMAGE_EXISTS
fi

if [ ! -z "$SIGNAL_VERSION" ]; then
    checkImage "Signal" "$SIGNAL_VERSION" "$IMAGE_ARCH"
    if [ $? -eq 0 ]; then
      SIGNAL_IMAGE_EXISTS="true"
      SIGNAL_IMAGE_OCID="$IMAGE_OCID"
      echo "Signal $ORACLE_REGION: $SIGNAL_IMAGE_OCID"
    else
      SIGNAL_IMAGE_EXISTS="false"
    fi
    export SIGNAL_IMAGE_OCID
    export SIGNAL_IMAGE_EXISTS
fi

if [ ! -z "$JIGASI_VERSION" ]; then
    checkImage "Jigasi" "$JIGASI_VERSION" "$IMAGE_ARCH"
    if [ $? -eq 0 ]; then
      JIGASI_IMAGE_EXISTS="true"
      JIGASI_IMAGE_OCID="$IMAGE_OCID"
      echo "Jigasi $ORACLE_REGION: $JIGASI_IMAGE_OCID"
    else
      JIGASI_IMAGE_EXISTS="false"
    fi
    export JIGASI_IMAGE_OCID
    export JIGASI_IMAGE_EXISTS
fi


if [ ! -z "$JIBRI_VERSION" ]; then
    checkImage "JavaJibri" "$JIBRI_VERSION" "$IMAGE_ARCH"
    if [ $? -eq 0 ]; then
      JIBRI_IMAGE_EXISTS="true"
      JIBRI_IMAGE_OCID="$IMAGE_OCID"
      echo "Jibri $ORACLE_REGION: $JIBRI_IMAGE_OCID"
    else
      JIBRI_IMAGE_EXISTS="false"
    fi
    export JIBRI_IMAGE_OCID
    export JIBRI_IMAGE_EXISTS
fi
