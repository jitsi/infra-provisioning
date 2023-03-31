#!/usr/bin/env python

# pip install boto3 awscli
import boto3
import sys
import pprint

from hcvlib import *

ENVIRONMENT=sys.argv[1]
SHARD=sys.argv[2]
STATE=sys.argv[3]
#jenkins build number, we get it from jenkins
BUILD_NUMBER=sys.argv[4]

ENVIRONMENT_TAG="environment"
SHARD_TAG="shard"
SHARD_ROLE_TAG="shard-role"
SHARD_TESTED_TAG="shard-tested"
BUILD_NUMBER_TAG="jenkins_job_id" 

SHARD_CORE_ROLE="core"
SHARD_JVB_ROLE="JVB"
SHARD_HAPROXY_ROLE="haproxy"

# table column width
width = 25

region = shard_region_from_name(SHARD)

update_consul_kv(ENVIRONMENT, region, SHARD, STATE, BUILD_NUMBER)

if region in ORACLE_REGION_MAP:
  # do it the oracle way
  shard_instances = get_oracle_instances_by_role(['core'],environment_name=ENVIRONMENT,shard_name=SHARD,regions=[region])
  if len(shard_instances) == 0:
    print('No OCI instances match filters: '+SHARD_ROLE_TAG+': '+SHARD_CORE_ROLE+', '+ENVIRONMENT_TAG+': '+ENVIRONMENT+', '+SHARD_TAG+': '+SHARD)
  else:
    update_instance_tags(shard_instances[0], new_freeform_tags={SHARD_TESTED_TAG:STATE, BUILD_NUMBER_TAG:BUILD_NUMBER})
    print('OCI Tags applied in '+region+' for '+ENVIRONMENT_TAG+': '+ENVIRONMENT+', '+SHARD_TAG+': '+SHARD+', '+SHARD_TESTED_TAG+': '+STATE+', '+BUILD_NUMBER_TAG+': '+BUILD_NUMBER)
else:
  # do it the AWS way
  ec2 = boto3.resource('ec2', region_name=region)

  jicofo_instances = ec2.instances.filter(
      Filters=[
          {'Name': 'tag:' + ENVIRONMENT_TAG, 'Values': [ENVIRONMENT]},
          {'Name': 'tag:' + SHARD_ROLE_TAG, 'Values': [SHARD_CORE_ROLE]},
          {'Name': 'tag:' + SHARD_TAG, 'Values': [SHARD]}
      ])

  instance_ids = [j.instance_id for j in jicofo_instances]

  if len(instance_ids) == 0:
    print('No instances match filters: '+SHARD_ROLE_TAG+': '+SHARD_CORE_ROLE+', '+ENVIRONMENT_TAG+': '+ENVIRONMENT+', '+SHARD_TAG+': '+SHARD)
  else:
    ec2.create_tags(DryRun=False, Resources=instance_ids, Tags=[{'Key':SHARD_TESTED_TAG, 'Value':STATE},{'Key': BUILD_NUMBER_TAG, 'Value': BUILD_NUMBER}])
    print('AWS Tags applied in '+region+' for '+ENVIRONMENT_TAG+': '+ENVIRONMENT+', '+SHARD_TAG+': '+SHARD+', '+SHARD_TESTED_TAG+': '+STATE+', '+BUILD_NUMBER_TAG+': '+BUILD_NUMBER)