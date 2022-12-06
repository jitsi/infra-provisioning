#!/usr/bin/env python

# pip install troposphere boto3

import boto3
import re
import argparse
import json
import os
from botocore.exceptions import ClientError
from troposphere import Parameter, Ref, Template, Join, Tags, Base64, Output, GetAtt,cloudformation
from troposphere.ec2 import Instance, NetworkInterfaceProperty
from troposphere.ec2 import SecurityGroupEgress,SecurityGroup,SecurityGroupIngress
from troposphere.autoscaling import Tag, AutoScalingGroup, LaunchConfiguration, BlockDeviceMapping, EBSBlockDevice, NotificationConfigurations, MetricsCollection, ScalingPolicy
from troposphere.route53 import RecordSetType, HealthCheck, HealthCheckConfiguration
from troposphere.cloudwatch import Alarm, MetricDimension

def create_template():
    t = Template()

    t.add_version("2010-09-09")

    t.add_description(
        "Template for the provisioning AWS resources for the HC Video shard"
    )

    return t

def write_template_json(filepath, t):
    data = json.loads(re.sub('shard_','shard-',t.to_json()))

    with open (filepath, 'w+') as outfile:
        json.dump(data, outfile)

def add_stack_name_region_alias_parameters(t):
    stack_name_prefix_param = t.add_parameter(Parameter(
        "StackNamePrefix",
        Description="Prefix for stack",
        Type="String",
        Default="vaas",
    ))
    region_alias_param = t.add_parameter(Parameter(
        "RegionAlias",
        Description="Alias for AWS Region",
        Type="String",
    ))
    
def add_stack_domain_parameters(t):
    param_domain_name = t.add_parameter(Parameter(
        "DomainName",
        Description="HC Video internal domain name",
        Type="String",
        Default="infra.jitsi.net"
    ))

def add_stack_key_parameters(t):
    param_key_name = t.add_parameter(Parameter(
        "KeyName",
        Type="String",
        Description="Name of an existing EC2 KeyPair to enable SSH access to the ec2 hosts",
        MinLength=1,
        MaxLength=64,
        AllowedPattern="[-_ a-zA-Z0-9]*",
        ConstraintDescription="can contain only alphanumeric characters, spaces, dashes and underscores."    
    ))
    
def add_stack_virtualization_parameters(t):
    param_app_instance_type = t.add_parameter(Parameter(
        "AppInstanceType",
        Description="App server instance type",
        Type="String",
        Default="t3.large",
        AllowedValues=[
            "t1.micro",
            "t2.micro",
            "t3.micro",
            "t3.small",
            "t3.medium",
            "t3.large",
            "m1.small",
            "m1.medium",
            "m1.large",
            "m3.large"
        ],
        ConstraintDescription="Must be a valid and allowed EC2 instance type."
    ))
    
    param_app_instance_virtualization = t.add_parameter(Parameter(
        "AppInstanceVirtualization",
        Description="App server instance virtualization",
        Type="String",
        Default="HVM",
        AllowedValues=[
            "HVM",
            "PV"
        ],
        ConstraintDescription="Must be a valid and allowed virtualization type."
    ))

def add_default_tag_parameters(t):

    tag_environment_type_param = t.add_parameter(Parameter(
        "TagEnvironmentType",
        Description="Tag: EnvironmentType",
        Type="String",
        Default="dev"
    ))

    tag_product_param = t.add_parameter(Parameter(
        "TagProduct",
        Description="Tag: Product",
        Type="String",
        Default="meetings"
    ))

    tag_service_param = t.add_parameter(Parameter(
        "TagService",
        Description="Tag: Service",
        Type="String",
        Default="jitsi-meet"
    ))

    tag_team_param = t.add_parameter(Parameter(
        "TagTeam",
        Description="Tag: Team",
        Type="String",
        Default="meet@8x8.com"
    ))

    tag_owner_param = t.add_parameter(Parameter(
        "TagOwner",
        Description="Tag: Owner",
        Type="String",
        Default="Meetings"
    ))


def pull_vars_from_network_stack(region, regionalias, stackprefix, az_letter=None):
    out = {}
    stack_name = regionalias + "-" + stackprefix + "-network"

    client = boto3.client( 'cloudformation', region_name=region )
    response = client.describe_stacks(
        StackName=stack_name
    )
    for stack in response["Stacks"]:
        outputs =  dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])

        out['vpc_id'] = outputs.get('VPC')
        out['ssh_security_group'] = outputs.get('SSHSecurityGroup')
        out['jvb_security_group'] = outputs.get("JVBSecurityGroup")
        out['signal_security_group'] = outputs.get('SignalSecurityGroup')

        out['jvb_subnets_A'] = outputs.get("JVBSubnetsA")
        out['jvb_subnets_B'] = outputs.get("JVBSubnetsB")

        out['public_subnetA'] = outputs.get("PublicSubnetA")
        out['public_subnetB'] = outputs.get("PublicSubnetB")

        out['network_acl_id'] = outputs.get("NetworkACL")
        out['ipv6_status'] = outputs.get("IPv6Status",False)
        out['private_route_table'] = outputs.get("PrivateRouteTable")
        out['public_route_table'] = outputs.get("PublicRouteTable")

        ec2 = boto3.client('ec2',region_name=region)
        vpcs = ec2.describe_vpcs(Filters=[{'Name':'vpc-id','Values':[out['vpc_id']]}])

        for vpc in vpcs['Vpcs']:
            out['ipv6_cidr'] =vpc['Ipv6CidrBlockAssociationSet'][0]['Ipv6CidrBlock']


    if az_letter:
        if az_letter == "a":
            out['subnetId'] = out['public_subnetA']
            out['jvb_zone_id'] = out['jvb_subnets_A']
        elif az_letter in ("b", "c"):
            out['subnetId'] = out['public_subnetB']
            out['jvb_zone_id']= out['jvb_subnets_B']

    return out

def pull_vars_from_nat_network_stack(region, regionalias, stackprefix):
    out = {}

    #now check for the NAT network
    stack_name = regionalias + "-" + stackprefix + "-NAT-network"

    client = boto3.client( 'cloudformation', region_name=region )
    response = client.describe_stacks(
        StackName=stack_name
    )
    if response["Stacks"]:
        for stack in response["Stacks"]:
            outputs =  dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
            out['nat_subnetA'] = outputs.get("NATSubnetA")
            out['nat_subnetB'] = outputs.get("NATSubnetB")
            out['nat_routetableA'] = outputs.get("NATRouteTableA")
            out['nat_routetableB'] = outputs.get("NATRouteTableB")
            out['nat_eigw'] = outputs.get("EgressOnlyInternetGateway")

    return out

def pull_vars_from_transit_gateway_stack(region, regionalias, stackprefix):
    out = {}

    #first look for transit gateway stack, use it if found
    stack_name = regionalias + "-" + stackprefix + "-transit-gateway-mesh"
    client = boto3.client( 'cloudformation', region_name=region )
    response = client.describe_stacks(
        StackName=stack_name
    )
    if response["Stacks"]:
        for stack in response["Stacks"]:
            outputs =  dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
            out['aws_transit_gateway_id'] = outputs.get("TransitGatewayId")

    return out

def pull_vars_from_vpn_stack(region, regionalias, stackprefix):
    out = {}
    #now check for the VPN network
    stack_name = regionalias + "-" + stackprefix + "-vpn-aws-oci-network"

    client = boto3.client( 'cloudformation', region_name=region )
    response = client.describe_stacks(
        StackName=stack_name
    )
    if response["Stacks"]:
        for stack in response["Stacks"]:
            outputs =  dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
            out['aws_vpn_gateway_id'] = outputs.get("AwsVpnGatewayId")

    return out

def pull_network_stack_vars(region, regionalias, stackprefix, az_letter=None):
    out = dict()

    #start with the basic network stack
    out.update(pull_vars_from_network_stack(region, regionalias, stackprefix, az_letter))

    #find nat network if exists
    try:
        out.update(pull_vars_from_nat_network_stack(region, regionalias, stackprefix))
    except ClientError as e:
        print((e.response['Error']['Message']))


    #look for transit gateway stack, use it if found
    try:
        out.update(pull_vars_from_transit_gateway_stack(region, regionalias, stackprefix))
    except ClientError as e:
        print((e.response['Error']['Message']))

    #next check VPN stack
    try:
        out.update(pull_vars_from_vpn_stack(region, regionalias, stackprefix))
    except ClientError as e:
        print((e.response['Error']['Message']))

    return out

def fill_in_bash_network_vars(out, az_letter=None):
    if not out['vpc_id']:
        out['vpc_id'] = os.environ.get('EC2_VPC_ID')
    if not out['signal_security_group']:
        out['signal_security_group'] = os.environ.get('SIGNAL_SECURITY_GROUP')
    if not out['public_subnetA']:
        out['public_subnetA'] = os.environ.get('DEFAULT_PUBLIC_SUBNET_ID_a')
    if not out['public_subnetB']:
        out['public_subnetB'] = os.environ.get('DEFAULT_PUBLIC_SUBNET_ID_b')
    if not out['ssh_security_group']:
        out['ssh_security_group'] = os.environ.get('SSH_SECURITY_GROUP')
    if not out['jvb_security_group']:
        out['jvb_security_group'] = os.environ.get('JVB_SECURITY_GROUP')
    if not out['network_acl_id']:
        out['network_acl_id'] = os.environ.get('DEFAULT_ACL_ID')
    if not out['private_route_table']:
        out['private_route_table'] = os.environ.get('DEFAULT_PRIVATE_ROUTE_ID')
    if ('aws_vpn_gateway_id' not in out) or (not out['aws_vpn_gateway_id']):
        out['aws_vpn_gateway_id'] = os.environ.get('AWS_VPN_GATEWAY_ID')
    return out

def pull_bash_network_vars(az_letter=None):
    out = {}

    out['vpc_id'] = os.environ.get('EC2_VPC_ID')
    out['signal_security_group'] = os.environ.get('SIGNAL_SECURITY_GROUP')
    out['public_subnetA'] = os.environ.get('DEFAULT_PUBLIC_SUBNET_ID_a')
    out['public_subnetB'] = os.environ.get('DEFAULT_PUBLIC_SUBNET_ID_b')
    out['ssh_security_group'] = os.environ.get('SSH_SECURITY_GROUP')
    out['jvb_security_group'] = os.environ.get('JVB_SECURITY_GROUP')
    out['network_acl_id'] = os.environ.get('DEFAULT_ACL_ID')
    out['private_route_table'] = os.environ.get('DEFAULT_PRIVATE_ROUTE_ID')
    out['aws_vpn_gateway_id'] = os.environ.get('AWS_VPN_GATEWAY_ID')

    if az_letter:
        if az_letter == "a":
            out['subnetId'] = out['public_subnetA']
            out['jvb_zone_id'] = os.environ.get('DEFAULT_DC_SUBNET_IDS_a')
        elif az_letter in ("b", "c"):
            out['subnetId'] = out['public_subnetB']
            out['jvb_zone_id']= os.environ.get('DEFAULT_DC_SUBNET_IDS_b')
    return out

def autoassign_ipv6_on_creation(region, vpc_id, enable_autoassign_ipv6=False):
    ec2_resource = boto3.resource('ec2', region_name=region)
    vpc = ec2_resource.Vpc(vpc_id)
    ec2_client = boto3.client('ec2', region_name=region)

    for subnet in vpc.subnets.all():
        subnet_id = subnet.subnet_id
        response = ec2_client.modify_subnet_attribute(
            AssignIpv6AddressOnCreation={
                'Value': enable_autoassign_ipv6
            },
            SubnetId=subnet_id
        )