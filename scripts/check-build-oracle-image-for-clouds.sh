#!/bin/bash
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

[ -z "$CLOUDS" ] && CLOUDS=$($LOCAL_PATH/release_clouds.sh $ENVIRONMENT)

if [[ "$IMAGE_TYPE" == "Signal" ]]; then
    export SIGNAL_VERSION="$JICOFO_VERSION-$JITSI_MEET_VERSION-$PROSODY_VERSION"
fi

BUILD_IMAGE=false
for C in $CLOUDS; do
    . $LOCAL_PATH/../clouds/${C}.sh
    . $LOCAL_PATH/check-build-oracle-image.sh

    if [ ! -z "$SIGNAL_VERSION" ]; then
        if [[ "$SIGNAL_IMAGE_EXISTS" == "false" ]]; then
            echo "No signal image $SIGNAL_VERSION found in region $ORACLE_REGION"
            BUILD_IMAGE=true
        fi
    fi
    if [ ! -z "$JVB_VERSION" ]; then
        if [[ "$JVB_IMAGE_EXISTS" == "false" ]]; then
            echo "No JVB image $JVB_VERSION found in region $ORACLE_REGION"
            BUILD_IMAGE=true
        fi
    fi
    if [ ! -z "$JIBRI_VERSION" ]; then
        if [[ "$JIBRI_IMAGE_EXISTS" == "false" ]]; then
            echo "No jibri image $JIBRI_VERSION found in region $ORACLE_REGION"
            BUILD_IMAGE=true
        fi
    fi
    if [ ! -z "$JIGASI_VERSION" ]; then
        if [[ "$JIGASI_IMAGE_EXISTS" == "false" ]]; then
            echo "No jigasi image $JIGASI_VERSION found in region $ORACLE_REGION"
            BUILD_IMAGE=true
        fi
    fi
done

if $BUILD_IMAGE; then
    echo "Image not found in at least one cloud, continuing to build image"
    exit 1
else
    echo "Image(s) found in all clouds, no need to build new images"
    exit 0
fi