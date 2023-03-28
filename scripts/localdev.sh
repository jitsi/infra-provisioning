#!/bin/bash
#
# create symlinks for local script development from infra-provisioning
# 

if [ -z "$CUSTOMIZATION_DIRNAME" ];then
    echo "## no CUSTOMIZATION_DIRNAME found, exiting..."
    exit 1
fi

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))
cd $LOCAL_PATH/..

echo "## creating symlinks needed for local script development"

ln -s ../infra-configuration/ansible
ln -s ../${CUSTOMIZATION_DIRNAME}/cloud_vpcs
ln -s ../${CUSTOMIZATION_DIRNAME}/clouds
ln -s ../${CUSTOMIZATION_DIRNAME}/config
ln -s ../${CUSTOMIZATION_DIRNAME}/regions
ln -s ../${CUSTOMIZATION_DIRNAME}/sites

cd ../infra-configuration
ln -s ../${CUSTOMIZATION_DIRNAME}/config
ln -s ../${CUSTOMIZATION_DIRNAME}/sites

cd ansible
ln -s ../${CUSTOMIZATION_DIRNAME}/config
ln -s ../${CUSTOMIZATION_DIRNAME}/secrets
ln -s ../${CUSTOMIZATION_DIRNAME}/sites

cd ../../${CUSTOMIZATION_DIRNAME}/ansible
ln -s ../config
ln -s ../sites






