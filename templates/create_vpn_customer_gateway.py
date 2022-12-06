#!/usr/bin/env python
import awacs
import distutils.util
import boto3, re, argparse, json, os, awacs

from templatelib import *
from troposphere import Parameter, Ref, Sub, Join, Tags, Base64, Output, GetAtt, Export, Select, Split
from troposphere.ec2 import CustomerGateway, VPNGateway, VPCGatewayAttachment, VPNConnection, \
    VpnTunnelOptionsSpecification


def add_customer_gw_parameters(t, single_connection=False):
    t.add_parameter(Parameter(
        "OciGatewayIP1",
        Description="OCI Gateway IP 1",
        Type="String"
    ))

    if not single_connection:
        t.add_parameter(Parameter(
            "OciGatewayIP2",
            Description="OCI Gateway IP 2",
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


def add_customer_gw_output(t, single_connection=False):
    t.add_output([
        Output(
            'OciGateway1',
            Description="Oci Gateway 1",
            Value=Ref("OciGateway1")
        )
    ])
    if not single_connection:
        t.add_output([
            Output(
                'OciGateway2',
                Description="Oci Gateway 2",
                Value=Ref("OciGateway2")
            )
        ])


def add_customer_gw_resources(t, stackprefix, single_connection=False):
    t.add_resource(CustomerGateway(
        "OciGateway1",
        BgpAsn="31898",
        IpAddress=Ref("OciGatewayIP1"),
        Type="ipsec.1",
        Tags=Tags(
            Name=Join("-", [Ref("TagEnvironment"),Ref("RegionAlias"),stackprefix,"OciGateway1"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role=Ref("TagRole")
        )
    ))

    if not single_connection:
        t.add_resource(CustomerGateway(
            "OciGateway2",
            BgpAsn="31898",
            IpAddress=Ref("OciGatewayIP2"),
            Type="ipsec.1",
            Tags=Tags(
                Name=Join("-", [Ref("TagEnvironment"),Ref("RegionAlias"),stackprefix,"OciGateway2"]),
                Environment=Ref("TagEnvironmentType"),
                Service=Ref("TagService"),
                Owner=Ref("TagOwner"),
                Team=Ref("TagTeam"),
                Product=Ref("TagProduct"),
                environment=Ref("TagEnvironment"),
                role=Ref("TagRole")
            )
        ))


def create_customer_gw_template(filepath, stackprefix, single_connection=False):
    t = create_template()

    add_default_tag_parameters(t)
    add_stack_name_region_alias_parameters(t)

    add_customer_gw_parameters(t, single_connection=single_connection)
    add_customer_gw_resources(t, stackprefix, single_connection=single_connection)
    add_customer_gw_output(t, single_connection=single_connection)

    write_template_json(filepath, t)


def main():
    parser = argparse.ArgumentParser(description='Create OCI Customer Gateways')

    parser.add_argument('--filepath', action='store',
                        help='Path to template file', required=True)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', type=str, default=None, required=False)
    parser.add_argument('--single_connection', action='store_true',
                        help='Controls whether to create 1 or 2 (default) connections', default=False, required=False)

    args = parser.parse_args()

    create_customer_gw_template(filepath=args.filepath, stackprefix=args.stackprefix, single_connection=args.single_connection)


if __name__ == '__main__':
    main()
