#!/usr/bin/env python
import awacs
import distutils.util
import boto3, re, argparse, json, os, awacs

from templatelib import *
from troposphere import Parameter, Ref, Join, Tags, Base64, Output, GetAtt, Export, Select, Split, ImportValue
from troposphere.ec2 import CustomerGateway, VPNGateway, VPCGatewayAttachment, VPNConnection, VpnTunnelOptionsSpecification

def add_ipsec_parameters(t, single_connection=False):
    t.add_parameter(Parameter(
        "OciGateway1",
        Description="OCI Gateway 1",
        Type="String"
    ))

    if not single_connection:
        t.add_parameter(Parameter(
            "OciGateway2",
            Description="OCI Gateway 2",
            Type="String"
        ))

    t.add_parameter(Parameter(
        "PSKVpn1Tunnel1",
        Description="Pre-shared key for VPN Connection 1 Tunnel 1",
        Type="String"
    ))

    t.add_parameter(Parameter(
        "PSKVpn1Tunnel2",
        Description="Pre-shared key for VPN Connection 1 Tunnel 2",
        Type="String"
    ))

    if not single_connection:
        t.add_parameter(Parameter(
            "PSKVpn2Tunnel1",
            Description="Pre-shared key for VPN Connection 2 Tunnel 1",
            Type="String"
        ))

    if not single_connection:
        t.add_parameter(Parameter(
            "PSKVpn2Tunnel2",
            Description="Pre-shared key for VPN Connection 2 Tunnel 2",
            Type="String"
        ))

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

def add_ipsec_output(t, single_connection=False):
    t.add_output([
        Output(
            'VpnConnectionId1',
            Description="VpnConnectionId1",
            Value=Ref("AwsOciVpnConnection1"),
        )
    ])
    if not single_connection:
        t.add_output([
            Output(
                'VpnConnectionId2',
                Description="VpnConnectionId2",
                Value=Ref("AwsOciVpnConnection2"),
            )
        ])

def add_ipsec_resources(t, stackprefix, opts, single_connection=False):
    vpn_connection_properties1 = {
        "Type": "ipsec.1",
        "CustomerGatewayId": Ref("OciGateway1"),
        "StaticRoutesOnly": False,
        "VpnTunnelOptionsSpecifications": [
            VpnTunnelOptionsSpecification(
                "AwsOciVpnTunnel1OptionsSpecification1",
                PreSharedKey=Ref("PSKVpn1Tunnel1")),
            VpnTunnelOptionsSpecification(
                "AwsOciVpnTunnel1OptionsSpecification2",
                PreSharedKey=Ref("PSKVpn1Tunnel2"))
        ],
        "Tags": Tags(
            Name=Join("-", [Ref("TagEnvironment"),Ref("RegionAlias"),stackprefix,"AwsOciTunnel1"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role=Ref("TagRole")
        )
    }

    vpn_connection_properties2 = {
            "Type": "ipsec.1",
            "CustomerGatewayId": Ref("OciGateway2"),
            "StaticRoutesOnly": False,
            "VpnTunnelOptionsSpecifications": [
                VpnTunnelOptionsSpecification(
                    "AwsOciVpnTunnel2OptionsSpecification1",
                    PreSharedKey=Ref("PSKVpn2Tunnel1")),
                VpnTunnelOptionsSpecification(
                    "AwsOciVpnTunnel2OptionsSpecification2",
                    PreSharedKey=Ref("PSKVpn2Tunnel2"))
            ],
            "Tags": Tags(
                Name=Join("-", [Ref("TagEnvironment"),Ref("RegionAlias"),stackprefix,"AwsOciTunnel2"]),
                Environment=Ref("TagEnvironmentType"),
                Service=Ref("TagService"),
                Owner=Ref("TagOwner"),
                Team=Ref("TagTeam"),
                Product=Ref("TagProduct"),
                environment=Ref("TagEnvironment"),
                role=Ref("TagRole")
            )        
    }


    if opts['aws_transit_gateway_id']:
        vpn_connection_properties1["TransitGatewayId"] = opts['aws_transit_gateway_id']
        vpn_connection_properties2["TransitGatewayId"] = opts['aws_transit_gateway_id']

    else:
        vpn_connection_properties1["VpnGatewayId"] = opts['aws_vpn_gateway_id']
        vpn_connection_properties2["VpnGatewayId"] = opts['aws_vpn_gateway_id']

    t.add_resource(VPNConnection(
        "AwsOciVpnConnection1",
        **vpn_connection_properties1
    ))

    if not single_connection:
        t.add_resource(VPNConnection(
            "AwsOciVpnConnection2",
            **vpn_connection_properties2
        ))


def create_ipsec_template(filepath, stackprefix, opts, single_connection=False):
    t = create_template()

    add_default_tag_parameters(t)
    add_stack_name_region_alias_parameters(t)

    add_ipsec_parameters(t, single_connection=single_connection)
    add_ipsec_resources(t,stackprefix, opts, single_connection=single_connection)
    add_ipsec_output(t, single_connection=single_connection)

    write_template_json(filepath, t)


def main():
    parser = argparse.ArgumentParser(description='Create AWS IPSec Tunnel Part1 for Oracle stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region alias)', default=False, required=False)
    parser.add_argument('--filepath', action='store',
                        help='Path to template file', required=True)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', type=str, default=None, required=False)
    parser.add_argument('--single_connection', action='store_true',
                        help='Flag to control whether to create 1 or 2 connections', default=False, required=False)
    parser.add_argument('--pull_network_stack', action='store',
                        help='Pull network variables from a network stack', default='true', required=False)
    parser.add_argument('--transit_gateway_id', action='store',
                        help='Override and set transit gateway value', default=False, required=False)

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

    if args.transit_gateway_id:
        opts['aws_transit_gateway_id'] = args.transit_gateway_id

    if not 'aws_transit_gateway_id' in opts:
        opts['aws_transit_gateway_id'] = False

    # if not args.skip_template_generation:
    create_ipsec_template(filepath=args.filepath, stackprefix=args.stackprefix, opts=opts, single_connection=args.single_connection)


if __name__ == '__main__':
    main()
