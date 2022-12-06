#!/usr/bin/env python
import awacs
import distutils.util
import boto3, re, argparse, json, os, awacs

from templatelib import *
from troposphere import Parameter, Ref, Sub, Join, Tags, Base64, Output, GetAtt, Export, Select, Split
from troposphere.ec2 import VPNGateway, VPCGatewayAttachment, VPNGatewayRoutePropagation


def  add_vpn_aws_network_parameters(t):
    t.add_parameter(Parameter(
        "TagEnvironment",
        Description="Tag: environment",
        Type="String"
    ))

    t.add_parameter(Parameter(
        "TagRole",
        Description="Tag: role",
        Type="String"
    ))

def add_vpn_aws_network_output(t):
    t.add_output([
        Output(
            'AwsVpnGatewayId',
            Description="The AWS Virtual Private Network id",
            Value=Ref("AwsVpnGateway")
        )
    ])

def add_vpn_aws_network_resources(t, stackprefix, opts):
    t.add_resource(VPNGateway(
        "AwsVpnGateway",
        Type="ipsec.1",
        Tags=Tags(
            Name=Join("-", [Ref("RegionAlias"),stackprefix,"vpn-gateway"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role=Ref("TagRole")
        )
    ))

    t.add_resource(VPCGatewayAttachment(
        "AwsVpnVpcGatewayAttachment",
        VpnGatewayId=Ref("AwsVpnGateway"),
        VpcId=opts['vpc_id']
    ))

    t.add_resource(VPNGatewayRoutePropagation(
        "AwsVpnGatewayRoutePropagation",
        RouteTableIds=[opts['public_route_table'], opts['private_route_table'], opts['nat_routetableA'], opts['nat_routetableB']],
        VpnGatewayId=Ref("AwsVpnGateway"),
        DependsOn="AwsVpnVpcGatewayAttachment"
    ))


def create_vpn_aws_network_template(filepath, stackprefix, opts):
    t = create_template()

    add_default_tag_parameters(t)
    add_stack_name_region_alias_parameters(t)

    add_vpn_aws_network_parameters(t)
    add_vpn_aws_network_resources(t, stackprefix, opts)
    add_vpn_aws_network_output(t)

    write_template_json(filepath, t)

def main():
    parser = argparse.ArgumentParser(description='Create VPN AWS Network Pre-requisites')
    parser.add_argument('--region', action='store',
                        help='AWS region)', required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region alias)', default=False, required=False)
    parser.add_argument('--filepath', action='store',
                        help='Path to template file', required=True)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', type=str, default=None, required=False)
    parser.add_argument('--pull_network_stack', action='store',
                        help='Pull network variables from a network stack', default='true', required=False)

    args = parser.parse_args()

    if not args.regionalias:
        regionalias=args.region
    else:
        regionalias=args.regionalias

    if args.pull_network_stack.lower() == "true":
        opts=pull_network_stack_vars(region=args.region, regionalias=regionalias, stackprefix=args.stackprefix)
        opts=fill_in_bash_network_vars(opts)
    else:
        opts=pull_bash_network_vars()

    create_vpn_aws_network_template(filepath=args.filepath, stackprefix=args.stackprefix, opts=opts)


if __name__ == '__main__':
    main()