#!/bin/bash
set -x #echo on

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

[ -z "$CLOUD_PROVIDER" ] && CLOUD_PROVIDER="$JIBRI_CLOUD_PROVIDER"

if [ -z "$CLOUD_PROVIDER" ]; then
  echo "Please specify the CLOUD_PROVIDER, either aws, oracle or all"
  exit 200
fi

if [ "$CLOUD_PROVIDER" != "aws" ] && [ "$CLOUD_PROVIDER" != "oracle" ] && [ "$CLOUD_PROVIDER" != "all" ] && [ "$CLOUD_PROVIDER" != "nomad" ]; then
  echo "Invalid CLOUD_PROVIDER, it should be either aws, oracle, nomad or all. Existing..."
  exit 201
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ "$CLOUD_PROVIDER" == "aws" ] || [ "$CLOUD_PROVIDER" == "all" ]; then
	echo "Deploying AWS jibris..."

	$LOCAL_PATH/create-jibri-stack.sh ubuntu
  if [ $? -gt 0 ]; then
    echo "AWS provisioning failed. Exiting..."
    exit 203
  fi
fi

if [ "$CLOUD_PROVIDER" == "oracle" ] || [ "$CLOUD_PROVIDER" == "all" ]; then
	if [ "$JIBRI_TYPE" != "java-jibri" ] && [ "$JIBRI_TYPE" != "sip-jibri" ]; then
    echo "Oracle supports only java-jibri and sip-jibri deployments. Exiting..."
    exit 202
  fi

  echo "Deploying Oracle Jibris..."
  $LOCAL_PATH/create-or-rotate-jibri-oracle.sh
  if [ $? -gt 0 ]; then
    echo "Oracle provisioning failed. Existing..."
    exit 203
  fi

fi

if [ "$CLOUD_PROVIDER" == "nomad" ]; then
	if [ "$JIBRI_TYPE" != "java-jibri" ]; then
    echo "Nomad supports only java-jibri deployments. Exiting..."
    exit 202
  fi

  echo "Deploying Nomad Jibris..."
  $LOCAL_PATH/create-or-rotate-jibri-nomad.sh
  if [ $? -gt 0 ]; then
    echo "Nomad provisioning failed. Existing..."
    exit 203
  fi
fi

