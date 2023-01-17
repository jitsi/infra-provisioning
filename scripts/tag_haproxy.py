#!/usr/bin/env python

# pip install boto3 awscli

import sys

from hcvlib import *

ENVIRONMENT=sys.argv[1]
RELEASE_NUMBER=sys.argv[2]
GIT_BRANCH=sys.argv[3]
#jenkins build number, we get it from jenkins

ENVIRONMENT_TAG="environment"
RELEASE_TAG="haproxy_release_number"
SHARD_ROLE_TAG="shard-role"
GIT_BRANCH_TAG="git_branch"
TAG_NAMESPACE="jitsi"

SHARD_HAPROXY_ROLE="haproxy"

for region in ORACLE_REGION_MAP.keys():
  # do it the oracle way
  proxy_instances = get_oracle_instances_by_role([SHARD_HAPROXY_ROLE],environment_name=ENVIRONMENT,regions=[region])
  if len(proxy_instances) > 0:
    for i in proxy_instances:
        update_instance_tags(i, new_freeform_tags={RELEASE_TAG:RELEASE_NUMBER}, new_defined_tags={TAG_NAMESPACE:{GIT_BRANCH_TAG:GIT_BRANCH}})
    print('OCI Tags applied in '+region+' for '+ENVIRONMENT_TAG+': '+ENVIRONMENT+', '+GIT_BRANCH_TAG+': '+GIT_BRANCH+', '+RELEASE_TAG+': '+RELEASE_NUMBER)

