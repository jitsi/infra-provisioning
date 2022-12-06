#!/usr/bin/env python
import awacs
import distutils.util
import boto3, re, argparse, json, os, awacs

from templatelib import *
from awacs.aws import Statement, Principal
from awacs.sts import AssumeRole
from troposphere import Parameter, Ref, Join, Tags, Base64, Output, GetAtt, Export, Select, Split
from troposphere.route53 import RecordSetType
from troposphere.iam import Role, InstanceProfile, Policy
from troposphere.ec2 import Subnet, SubnetNetworkAclAssociation, SubnetRouteTableAssociation, \
    RouteTable, Route, VPC, InternetGateway, DHCPOptions, NetworkAcl, NetworkAclEntry, VPCGatewayAttachment, \
    VPCDHCPOptionsAssociation, SecurityGroupRule, SecurityGroupEgress, Instance, VPCCidrBlock, SubnetCidrBlock
from troposphere.cloudformation import CustomResource


def add_network_output(t, enable_ipv6):
    t.add_output([
        Output(
            'VPC',
            Description="The VPC ID",
            Value=Ref("VaasVPC"),
        ),
        Output(
            'VPCCidr',
            Description= "CIDR block for VPC",
            Value= Ref("VPCCidr"),
        ),
        Output(
            'SignalSecurityGroup',
            Description= "Signal Security Group",
            Value= Ref("SignalSecurityGroup"),
        ),
        Output(
            'JVBSecurityGroup',
            Description="JVB Security Group",
            Value=Ref("JVBSecurityGroup"),
        ),
        Output(
            'SSHSecurityGroup',
            Description="SSH Jumpbox Security Group",
            Value=Ref("PublicNetworkSecurityGroup"),
        ),
        Output(
            'SSHDNSName',
            Description="The SSH DNS Name",
            Value=Join("",[Join("-", [ Ref("RegionAlias"), Ref("StackNamePrefix"),"ssh"]),".",Ref("DomainName")])
        ),
        Output(
            'SSHIPAddress',
            Description="The SSH IP Address",
            Value=GetAtt("SSHServer","PublicIp"),
        ),
        Output(
            'PublicSubnetA',
            Description="The Subnet ID for the Public Subnet in the first AZ",
            Value=Ref("PublicSubnetA"),
        ),
        Output(
            'PublicSubnetB',
            Description="The Subnet ID for the Public Subnet in the second AZ",
            Value=Ref("PublicSubnetB"),
        ),
        Output(
            'PublicSubnetsIDs',
            Description="The Subnets IDs for the Public Subnets",
            Value=Join(",",[Ref("PublicSubnetA"),Ref("PublicSubnetB")]),
        ),
        Output(
            'JVBSubnetsA',
            Description="The subnet IDs for JVBs in first AZ",
            Value=Join(",",[Ref("JVBSubnetA1"),Ref("JVBSubnetA2"),Ref("JVBSubnetA3"),Ref("JVBSubnetA4"),Ref("JVBSubnetA5"),Ref("JVBSubnetA6"),Ref("JVBSubnetA7"),Ref("JVBSubnetA8")]),
        ),
        Output(
            'JVBSubnetsB',
            Description="The subnet IDs for JVBs in second AZ",
            Value=Join(",", [Ref("JVBSubnetB1"), Ref("JVBSubnetB2"),Ref("JVBSubnetB3"),Ref("JVBSubnetB4"),Ref("JVBSubnetB5"),Ref("JVBSubnetB6"),Ref("JVBSubnetB7"),Ref("JVBSubnetB8")]),
        ),
        Output(
            'NetworkACL',
            Description="Default network ACL for subnets in the VPC",
            Value=Ref("VaasNetworkACL"),
        ),
        Output(
            'PrivateRouteTable',
            Description="Route table for private subnets in the VPC",
            Value=Ref("VaasRouteTablePrivate"),
        ),
        Output(
            'PublicRouteTable',
            Description="Route table for public subnets in the VPC",
            Value=Ref("VaasRouteTablePublic"),
        ),
        Output(
            'IPv6Status',
            Description="IPv6 status",
            Value=str(enable_ipv6)
        )
    ])

def add_network_cft_parameters(t):
    param_vpccidr = t.add_parameter(Parameter(
        "VPCCidr",
        Description="CIDR for VPC",
        Type="String",
        ConstraintDescription="Should look like 10.0.0.0/16",
        Default="10.0.0.0/16"
    ))

    param_az1_letter = t.add_parameter(Parameter(
        "AZ1Letter",
        Description="Ending letter for initial availability zone in region",
        Type="String",
        Default="a"
    ))

    param_az2_letter = t.add_parameter(Parameter(
        "AZ2Letter",
        Description="Ending letter for second availability zone in region",
        Type="String",
        Default="b"
    ))

    param_cidr_publicsubnetA = t.add_parameter(Parameter(
        "PublicSubnetACidr",
        Description="CIDR for public subnet in the 1st AvailabilityZone",
        ConstraintDescription="Should look like 10.0.3.0/24",
        Type="String",
        Default="10.0.3.0/24"
    ))

    param_cidr_publicsubnetB = t.add_parameter(Parameter(
        "PublicSubnetBCidr",
        Description="CIDR for public subnet in the 2nd AvailabilityZone",
        ConstraintDescription="Should look like 10.0.4.0/24",
        Type="String",
        Default="10.0.4.0/24"
    ))

    param_jvb_cidrs_subnetA = t.add_parameter(Parameter(
        "JVBSubnetACidrs",
        Description="Comma-delimited list of 2 CIDRs for Subnets in the 1st AvailabilityZone",
        ConstraintDescription="Should look like 10.0.1.0/28,10.0.1.16/28",
        Type="CommaDelimitedList",
        Default="10.0.1.0/25, 10.0.1.128/25,10.0.5.0/24,10.0.7.0/24,10.0.9.0/24,10.0.11.0/24,10.0.13.0/24,10.0.15.0/24"
    ))

    param_jvb_cidrs_subnetB = t.add_parameter(Parameter(
        "JVBSubnetBCidrs",
        Description="Comma-delimited list of 2 CIDRs for Subnets in the 2nd AvailabilityZone",
        ConstraintDescription="Should look like 10.0.2.0/28,10.0.2.16/28",
        Type="CommaDelimitedList",
        Default="10.0.2.0/25, 10.0.2.128/25, 10.0.6.0/24, 10.0.8.0/24, 10.0.10.0/24, 10.0.12.0/24, 10.0.14.0/24, 10.0.16.0/24"
    ))

    param_cidr_publicsubnetA_ipv6 = t.add_parameter(Parameter(
        "PublicSubnetACidrIPv6",
        Description="CIDR for IPv6 public subnet in the 1st AvailabilityZone",
        ConstraintDescription="Should look like 01::/64",
        Type="String",
        Default="01::/64"
    ))

    param_cidr_publicsubnetB_ipv6 = t.add_parameter(Parameter(
        "PublicSubnetBCidrIPv6",
        Description="CIDR for IPv6 public subnet in the 2nd AvailabilityZone",
        ConstraintDescription="Should look like 02::/64",
        Type="String",
        Default="02::/64"
    ))

    param_jvb_cidrs_subnetA_ipv6 = t.add_parameter(Parameter(
        "JVBSubnetACidrsIPv6",
        Description="Comma-delimited list of 2 IPv6 CIDRs for Subnets in the 1st AvailabilityZone",
        ConstraintDescription="Should look like a1::/64,a2::/64",
        Type="CommaDelimitedList",
        Default="a1::/64,a2::/64,a3::/64,a4::/64,a5::/64,a6::/64,a7::/64,a8::/64"
    ))

    param_jvb_cidrs_subnetB_ipv6 = t.add_parameter(Parameter(
        "JVBSubnetBCidrsIPv6",
        Description="Comma-delimited list of 2 IPv6 CIDRs for Subnets in the 2nd AvailabilityZone",
        ConstraintDescription="Should look like b1::/64,b2::/64",
        Type="CommaDelimitedList",
        Default="b1::/64,b2::/64,b3::/64,b4::/64,b5::/64,b6::/64,b7::/64,b8::/64"
    ))

    param_jvb_subnet_map_publicip = t.add_parameter(Parameter(
        "JVBSubnetMapPublicIp",
        Description="Indicates whether JVB subnets should receive an AWS public IP address",
        Type="String",
        Default="true"
    ))

    param_public_subnet_map_publicip = t.add_parameter(Parameter(
        "PublicSubnetMapPublicIp",
        Description="Indicates whether public subnets should receive an AWS public IP address",
        Type="String",
        Default="true"
    ))

    param_jigasi_subnet_map_publicip = t.add_parameter(Parameter(
        "JigasiSubnetMapPublicIp",
        Description="Indicates whether JVB subnets should receive an AWS public IP address",
        Type="String",
        Default="true"
    ))

    param_public_dns_hostedzone_id = t.add_parameter(Parameter(
        "PublicDNSHostedZoneId",
        Description="Video Engineering public hosted zone Id",
        Type="String",
    ))

    param_ec2_imageid = t.add_parameter(Parameter(
        "Ec2ImageId",
        Description="AMI ID for SSH Server",
        Type="String"
    ))

    tag_environment_param = t.add_parameter(Parameter(
        "TagEnvironment",
        Description="Tag: environment",
        Type="String",
        Default="all"
    ))

    tag_vpc_peering_status_param = t.add_parameter(Parameter(
        "TagVPCpeeringStatus",
        Description="Tag: vpc_peering_status",
        Type="String",
        Default="false"
    ))

    param_autoassign_ipv6_lambda = t.add_parameter(Parameter(
        "AutoassignIpv6LambdaFunctionName",
        Description='Lambda function name for custom resource',
        Type="String"
    ))

def add_network_cft_resources(t,enable_ipv6):

    vaas_vpc = t.add_resource(VPC(
        'VaasVPC',
        CidrBlock=Ref("VPCCidr"),
        InstanceTenancy="default",
        EnableDnsSupport="true",
        EnableDnsHostnames="true",
        Tags=Tags(
            Name=Join("-", [Ref("RegionAlias"),Ref("StackNamePrefix"),"vpc"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            vpc_peering_status=Ref('TagVPCpeeringStatus'),
            stack_name_prefix=Ref("StackNamePrefix")
        )
    ))

    jvb_subnet_a1 = t.add_resource(Subnet(
        'JVBSubnetA1',
        CidrBlock=Select("0", Ref("JVBSubnetACidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet1"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_a2 = t.add_resource(Subnet(
        'JVBSubnetA2',
        CidrBlock=Select("1", Ref("JVBSubnetACidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet2"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_a3 = t.add_resource(Subnet(
        'JVBSubnetA3',
        CidrBlock=Select("2", Ref("JVBSubnetACidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet3"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_a4 = t.add_resource(Subnet(
        'JVBSubnetA4',
        CidrBlock=Select("3", Ref("JVBSubnetACidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet4"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_a5 = t.add_resource(Subnet(
        'JVBSubnetA5',
        CidrBlock=Select("4", Ref("JVBSubnetACidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet5"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_a6 = t.add_resource(Subnet(
        'JVBSubnetA6',
        CidrBlock=Select("5", Ref("JVBSubnetACidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet6"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_a7 = t.add_resource(Subnet(
        'JVBSubnetA7',
        CidrBlock=Select("6", Ref("JVBSubnetACidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet7"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_a8 = t.add_resource(Subnet(
        'JVBSubnetA8',
        CidrBlock=Select("7", Ref("JVBSubnetACidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet8"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_b1 = t.add_resource(Subnet(
        'JVBSubnetB1',
        CidrBlock=Select("0", Ref("JVBSubnetBCidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet1"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_b2 = t.add_resource(Subnet(
        'JVBSubnetB2',
        CidrBlock=Select("1", Ref("JVBSubnetBCidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet2"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_b3 = t.add_resource(Subnet(
        'JVBSubnetB3',
        CidrBlock=Select("2", Ref("JVBSubnetBCidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet3"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_b4 = t.add_resource(Subnet(
        'JVBSubnetB4',
        CidrBlock=Select("3", Ref("JVBSubnetBCidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet4"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_b5 = t.add_resource(Subnet(
        'JVBSubnetB5',
        CidrBlock=Select("4", Ref("JVBSubnetBCidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet5"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_b6 = t.add_resource(Subnet(
        'JVBSubnetB6',
        CidrBlock=Select("5", Ref("JVBSubnetBCidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet6"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_b7 = t.add_resource(Subnet(
        'JVBSubnetB7',
        CidrBlock=Select("6", Ref("JVBSubnetBCidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet7"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    jvb_subnet_b8 = t.add_resource(Subnet(
        'JVBSubnetB8',
        CidrBlock=Select("7", Ref("JVBSubnetBCidrs")),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=Ref("JVBSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-JVBSubnet8"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='JVB'
        )
    ))

    public_subnetA = t.add_resource(Subnet(
        'PublicSubnetA',
        CidrBlock=Ref("PublicSubnetACidr"),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=Ref("PublicSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-PublicSubnet"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='Public'
        )
    ))

    public_subnetB = t.add_resource(Subnet(
        'PublicSubnetB',
        CidrBlock=Ref("PublicSubnetBCidr"),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=Ref("PublicSubnetMapPublicIp"),
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-PublicSubnet"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='Public'
        )
    ))

    vass_igw = t.add_resource(InternetGateway(
        'VaasIGW',
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),"-",Ref("StackNamePrefix"),"-igw"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
        )
    ))

    vaas_dhcp_options = t.add_resource(DHCPOptions(
        'VaasDHCPOptions',
        DomainName="ec2.internal",
        DomainNameServers=["AmazonProvidedDNS"],
    ))

    vass_network_acl = t.add_resource(NetworkAcl(
        'VaasNetworkACL',
        VpcId=Ref("VaasVPC")
    ))

    vass_route_table_public = t.add_resource(RouteTable(
        'VaasRouteTablePublic',
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),"-",Ref("StackNamePrefix"),"-PublicRouteTable"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
        )
    ))

    vass_route_table_private = t.add_resource(RouteTable(
        'VaasRouteTablePrivate',
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),"-",Ref("StackNamePrefix"),"-PrivateRouteTable"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
        )
    ))

    vass_network_acl_entry_egress_allow_all = t.add_resource(NetworkAclEntry(
        'VaasNetworkACLEntryEgressAllowAll',
        CidrBlock="0.0.0.0/0",
        Egress=True,
        Protocol="-1",
        RuleAction="allow",
        RuleNumber="100",
        NetworkAclId=Ref("VaasNetworkACL")
    ))

    vass_network_acl_entry_ingres_allow_all = t.add_resource(NetworkAclEntry(
        'VaasNetworkACLEntryIngresAllowAll',
        CidrBlock="0.0.0.0/0",
        Protocol="-1",
        RuleAction="allow",
        RuleNumber="100",
        NetworkAclId=Ref("VaasNetworkACL")
    ))

    subnetacl1 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl1',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("PublicSubnetA")
    ))

    subnetacl2 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl2',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("PublicSubnetB")
    ))

    subnetacl3 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl3',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetA1")
    ))

    subnetacl4 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl4',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetA2")
    ))

    subnetacl5 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl5',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetB1")
    ))

    subnetacl6 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl6',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetB2")
    ))


    subnetacl3 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl7',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetA3")
    ))

    subnetacl4 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl8',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetA4")
    ))

    subnetacl5 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl9',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetB3")
    ))

    subnetacl6 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl10',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetB4")
    ))

    subnetacl11 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl11',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetA5")
    ))

    subnetacl12 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl12',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetA6")
    ))

    subnetacl13 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl13',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetA7")
    ))

    subnetacl14 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl14',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetA8")
    ))

    subnetacl15 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl15',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetB5")
    ))

    subnetacl16 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl16',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetB6")
    ))

    subnetacl17 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl17',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetB7")
    ))

    subnetacl18 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl18',
        NetworkAclId=Ref("VaasNetworkACL"),
        SubnetId=Ref("JVBSubnetB8")
    ))

    vaas_vpcigw_link =t.add_resource(VPCGatewayAttachment(
        'VaasVPCIGWLink',
        VpcId=Ref("VaasVPC"),
        InternetGatewayId=Ref("VaasIGW"),
    ))

    subnetroute1 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute1',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetA1")
    ))

    subnetroute2 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute2',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetA2")
    ))

    subnetroute3 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute3',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetB1")
    ))

    subnetroute4 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute4',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetB2")
    ))

    subnetroute1 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute7',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetA3")
    ))

    subnetroute2 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute8',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetA4")
    ))

    subnetroute3 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute9',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetB3")
    ))

    subnetroute4 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute10',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetB4")
    ))

    subnetroute11 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute11',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetA5")
    ))

    subnetroute12 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute12',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetA6")
    ))

    subnetroute13 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute13',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetA7")
    ))

    subnetroute14 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute14',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetA8")
    ))

    subnetroute15 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute15',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetB5")
    ))

    subnetroute16 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute16',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetB6")
    ))

    subnetroute17 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute17',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetB7")
    ))

    subnetroute18 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute18',
        RouteTableId=Ref("VaasRouteTablePrivate"),
        SubnetId=Ref("JVBSubnetB8")
    ))

    subnetroute5 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute5',
        RouteTableId=Ref("VaasRouteTablePublic"),
        SubnetId=Ref("PublicSubnetA")
    ))

    subnetroute6 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute6',
        RouteTableId=Ref("VaasRouteTablePublic"),
        SubnetId=Ref("PublicSubnetB")
    ))

    route1 = t.add_resource(Route(
        'route1',
        DestinationCidrBlock="0.0.0.0/0",
        RouteTableId=Ref("VaasRouteTablePrivate"),
        GatewayId=Ref("VaasIGW"),
        DependsOn="VaasVPCIGWLink",
    ))

    route2 = t.add_resource(Route(
        'route2',
        DestinationCidrBlock="0.0.0.0/0",
        RouteTableId=Ref("VaasRouteTablePublic"),
        GatewayId=Ref("VaasIGW"),
        DependsOn="VaasVPCIGWLink",
    ))

    dchpassoc1 = t.add_resource(VPCDHCPOptionsAssociation(
        'dchpassoc1',
        VpcId=Ref("VaasVPC"),
        DhcpOptionsId=Ref("VaasDHCPOptions")
    ))

    signal_security_group = t.add_resource(SecurityGroup(
        'SignalSecurityGroup',
        GroupDescription="Signal/Core nodes",
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("-", [Ref("RegionAlias"),Ref("StackNamePrefix"),"CoreGroup"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
        )
    ))

    jvb_security_group = t.add_resource(SecurityGroup(
        'JVBSecurityGroup',
        GroupDescription="JVB nodes",
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("-", [Ref("RegionAlias"),Ref("StackNamePrefix"),"JVBGroup"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
        )
    ))

    public_network_security_group = t.add_resource(SecurityGroup(
        'PublicNetworkSecurityGroup',
        GroupDescription="Access to SSH jump box",
        VpcId=Ref("VaasVPC"),
        Tags=Tags(
            Name=Join("-", [Ref("RegionAlias"),Ref("StackNamePrefix"),"SSHGroup"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
        ),
        SecurityGroupIngress=[
            SecurityGroupRule(
                IpProtocol="tcp",
                FromPort="22",
                ToPort="22",
                CidrIp="0.0.0.0/0"
            )
        ]
    ))

    ingress0 = t.add_resource(SecurityGroupIngress(
        'ingress0',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="80",
        ToPort="80",
        CidrIp="0.0.0.0/0"
    ))

    ingress1 = t.add_resource(SecurityGroupIngress(
        'ingress1',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="8888",
        ToPort="8888",
        CidrIp="10.0.0.0/8"
    ))

    ingress2 = t.add_resource(SecurityGroupIngress(
        'ingress2',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="5347",
        ToPort="5347",
        SourceSecurityGroupId=Ref("JVBSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    ingress3 = t.add_resource(SecurityGroupIngress(
        'ingress3',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        SourceSecurityGroupId=Ref("PublicNetworkSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    ingress4 = t.add_resource(SecurityGroupIngress(
        'ingress4',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="443",
        ToPort="443",
        CidrIp="0.0.0.0/0"
    ))

    ingress5 = t.add_resource(SecurityGroupIngress(
        'ingress5',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="5222",
        ToPort="5222",
        CidrIp="0.0.0.0/0"
    ))

    ingress6 = t.add_resource(SecurityGroupIngress(
        'ingress6',
        GroupId=Ref("JVBSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        SourceSecurityGroupId=Ref("PublicNetworkSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    ingress7 = t.add_resource(SecurityGroupIngress(
        'ingress7',
        GroupId=Ref("JVBSecurityGroup"),
        IpProtocol="udp",
        FromPort="5001",
        ToPort="5001",
        SourceSecurityGroupId=Ref("JVBSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    ingress8 = t.add_resource(SecurityGroupIngress(
        'ingress8',
        GroupId=Ref("JVBSecurityGroup"),
        IpProtocol="udp",
        FromPort="10000",
        ToPort="20000",
        CidrIp="0.0.0.0/0"
    ))

    ingress9 = t.add_resource(SecurityGroupIngress(
        'ingress9',
        GroupId=Ref("JVBSecurityGroup"),
        IpProtocol="tcp",
        FromPort="443",
        ToPort="443",
        CidrIp="0.0.0.0/0"
    ))

    ingress10 = t.add_resource(SecurityGroupIngress(
        'ingress10',
        GroupId=Ref("JVBSecurityGroup"),
        IpProtocol="icmp",
        FromPort="-1",
        ToPort="-1",
        CidrIp="0.0.0.0/0"
    ))

    ingress11 = t.add_resource(SecurityGroupIngress(
        'ingress11',
        GroupId=Ref("JVBSecurityGroup"),
        IpProtocol="tcp",
        FromPort="5001",
        ToPort="5001",
        SourceSecurityGroupId=Ref("JVBSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    ingress12 = t.add_resource(SecurityGroupIngress(
        'ingress12',
        GroupId=Ref("JVBSecurityGroup"),
        IpProtocol="udp",
        FromPort="4096",
        ToPort="4096",
        CidrIp="10.0.0.0/8"
    ))

    ingress13 = t.add_resource(SecurityGroupIngress(
        'ingress13',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="6222",
        ToPort="6222",
        CidrIp="10.0.0.0/8"
    ))

    ingress14 = t.add_resource(SecurityGroupIngress(
        'ingress14',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="6222",
        ToPort="6222",
        CidrIp="0.0.0.0/0"
    ))

    ingress15 = t.add_resource(SecurityGroupIngress(
        'ingress15',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="6060",
        ToPort="6060",
        CidrIp="10.0.0.0/8"
    ))

    egress2 = t.add_resource(SecurityGroupEgress(
        'egress2',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="-1",
        FromPort="-1",
        ToPort="-1",
        CidrIp="0.0.0.0/0"
    ))

    egress3 = t.add_resource(SecurityGroupEgress(
        'egress3',
        GroupId=Ref("JVBSecurityGroup"),
        IpProtocol="-1",
        FromPort="-1",
        ToPort="-1",
        CidrIp="0.0.0.0/0"
    ))

    sshserver_security_role = t.add_resource(Role(
        'SSHServerSecurityRole',
        AssumeRolePolicyDocument=awacs.aws.Policy(
            Version="2012-10-17",
            Statement=[
                Statement(
                    Effect="Allow",
                    Principal=Principal("Service",["ec2.amazonaws.com"]),
                    Action=[AssumeRole]
                )
            ],
        ),
        Path="/hcvideo/ssh/",
        Policies=[
            Policy(
                PolicyName="SSHServerPolicy",
                PolicyDocument={
                        "Statement": [
                        {
                            "Effect": "Allow",
                            "Action": "ec2:DescribeTags",
                            "Resource": "*"
                        },
                        {
                            "Effect": "Allow",
                            "Action": [
                                "s3:ListBucket"
                            ],
                            "Resource": ["arn:aws:s3:::jitsi-bootstrap-assets"],
                        },
                        {
                            "Effect": "Allow",
                            "Action": [
                                "s3:GetObject"
                                ],
                            "Resource": [
                                "arn:aws:s3:::jitsi-bootstrap-assets/vault-password",
                                "arn:aws:s3:::jitsi-bootstrap-assets/id_rsa_jitsi_deployment",
                            ],
                        }]
                }
                )
            ]
    ))

    sshserver_security_instance_profile = t.add_resource(InstanceProfile(
        'SSHServerSecurityInstanceProfile',
        Path="/",
        Roles=[
            Ref("SSHServerSecurityRole")
        ]
    ))

    ssh_server_dependsOn_prop = [
        "PublicSubnetA",
        "PublicNetworkSecurityGroup",
        "SSHServerSecurityInstanceProfile"
    ]

    if enable_ipv6:
        ssh_server_dependsOn_prop.append('PublicSubnetAVPCIpv6')
        ssh_server_dependsOn_prop.append('PublicSubnetBVPCIpv6')

    sshserver = t.add_resource(Instance(
        'SSHServer',
        DependsOn=ssh_server_dependsOn_prop,
        ImageId=Ref("Ec2ImageId"),
        KeyName=Ref("KeyName"),
        InstanceType=Ref("AppInstanceType"),
        Monitoring=False,
        NetworkInterfaces=[
            NetworkInterfaceProperty(
                AssociatePublicIpAddress=True,
                DeviceIndex="0",
                GroupSet=[
                    Ref("PublicNetworkSecurityGroup")
                ],
                SubnetId=Ref("PublicSubnetA")
            )
        ],
        IamInstanceProfile=Ref("SSHServerSecurityInstanceProfile"),
        Tags=Tags(
            Name=Join("-", [Ref("RegionAlias"), Ref("StackNamePrefix"), "ssh"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            shard_role="ssh",
            environment=Ref("TagEnvironment")
        ),
        UserData=Base64(Join('', [
            "#!/bin/bash -v\n",
            "EXIT_CODE=0\n",
            "set -e\n",
            "set -x\n",

            ". /usr/local/bin/aws_cache.sh\n",
            "CLOUD_NAME=\"",Join("-", [Ref("RegionAlias"), Ref("StackNamePrefix"), "ssh"]),"\"\n",
            "hostname $CLOUD_NAME.infra.jitsi.net\n",
            "export AWS_DEFAULT_REGION=", {"Ref": "AWS::Region"}, "\n",

            "PYTHON_MAJOR=$(python -c 'import platform; print(platform.python_version())' | cut -d '.' -f1)\n",
            "PYTHON_IS_3=false\n",
            "if [[ \"$PYTHON_MAJOR\" -eq 3 ]]; then\n", 
            "PYTHON_IS_3=true\n",
            "fi\n",
            "if $PYTHON_IS_3; then\n",
            "CFN_FILE=\"aws-cfn-bootstrap-py3-latest.tar.gz\"\n",
            "else\n",
            "CFN_FILE=\"aws-cfn-bootstrap-latest.tar.gz\"\n",
            "fi\n",
            "wget -P /root https://s3.amazonaws.com/cloudformation-examples/$CFN_FILE\n",
            "mkdir -p /root/aws-cfn-bootstrap-latest && \\\n",
            "tar xvfz /root/$CFN_FILE --strip-components=1 -C /root/aws-cfn-bootstrap-latest\n",
            "easy_install /root/aws-cfn-bootstrap-latest/\n",

            "/usr/local/bin/aws s3 cp s3://jitsi-bootstrap-assets/vault-password /root/.vault-password --region us-west-2\n",
            "/usr/local/bin/aws s3 cp s3://jitsi-bootstrap-assets/id_rsa_jitsi_deployment /root/.ssh/id_rsa --region us-west-2\n",
            "chmod 400 /root/.ssh/id_rsa\n",
            "echo '[tag_shard","_","role_ssh]' > /root/ansible_inventory\n",
            "echo '127.0.0.1' >> /root/ansible_inventory\n",
            "ansible-pull -v -U git@github.com:8x8Cloud/jitsi-video-infrastructure.git \
            -d /tmp/bootstrap --purge \
            -i \"/root/ansible_inventory\" \
            -e \"hcv_environment=", {"Ref": "TagEnvironment"}, "\" \
            --vault-password-file=/root/.vault-password \
            --accept-host-key \
            -C \"master\" \
            ansible/configure-jumpbox.yml >> /var/log/bootstrap.log 2>&1 || EXIT_CODE=1\n",
            "dhclient -6 -nw\n",
            "# Send signal about finishing configuring server\n",

            "/usr/local/bin/cfn-signal -e $EXIT_CODE -r 'Server configuration' '", {"Ref": "SSHClientWaitHandle"}, "'\n",
            "rm /root/.vault-password /root/.ssh/id_rsa /root/ansible_inventory\n"

        ]))
    ))

    ssh_client_wait_handle = t.add_resource(cloudformation.WaitConditionHandle(
        'SSHClientWaitHandle'
    ))

    ssh_client_wait_condition = t.add_resource(cloudformation.WaitCondition(
        'SSHClientWaitCondition',
        Handle= Ref("SSHClientWaitHandle"),
        Timeout= 3600,
        Count= 1
    ))

    ssh_dns_record = t.add_resource(RecordSetType(
        'SSHDNSRecord',
        HostedZoneId=Ref("PublicDNSHostedZoneId"),
        Comment=Join("", ["SSH server host name for ", Ref("AWS::Region")]),
        Name=Join("", [Join("-", [Ref("RegionAlias"),Ref("StackNamePrefix"), "ssh"]),".", Ref("DomainName"), "."]),
        Type="A",
        TTL=300,
        ResourceRecords=[
            GetAtt("SSHServer","PublicIp")
        ],
        DependsOn=[
            "SSHServer"
        ]
    ))

def add_autoassign_ipv6_custom_resource(t):

    add_custom_resource= t.add_resource(CustomResource(
        "Ipv6AutoAssignOnCreation",
        DependsOn=['JVBSubnetA1VPCIpv6', 'JVBSubnetA2VPCIpv6',
                   'JVBSubnetA3VPCIpv6', 'JVBSubnetA4VPCIpv6',
                   'JVBSubnetA5VPCIpv6', 'JVBSubnetA6VPCIpv6',
                   'JVBSubnetA7VPCIpv6', 'JVBSubnetA8VPCIpv6',
                   'JVBSubnetB1VPCIpv6', 'JVBSubnetB2VPCIpv6',
                   'JVBSubnetB3VPCIpv6', 'JVBSubnetB4VPCIpv6',
                   'JVBSubnetB5VPCIpv6', 'JVBSubnetB6VPCIpv6',
                   'JVBSubnetB7VPCIpv6', 'JVBSubnetB8VPCIpv6',
                   'PublicSubnetAVPCIpv6', 'PublicSubnetBVPCIpv6',
                   'SSHServer'
                   ],
        ServiceToken=Join("", ["arn:aws:lambda:", Ref("AWS::Region"), ":", Ref("AWS::AccountId"), ":function:",
                               Ref("AutoassignIpv6LambdaFunctionName")]),
        StackRegion=Ref("AWS::Region"),
        Subnets=[
            Ref("JVBSubnetA1"), Ref("JVBSubnetA2"),
            Ref("JVBSubnetA3"), Ref("JVBSubnetA4"),
            Ref("JVBSubnetA5"), Ref("JVBSubnetA6"),
            Ref("JVBSubnetA7"), Ref("JVBSubnetA8"),
            Ref("JVBSubnetB1"), Ref("JVBSubnetB2"),
            Ref("JVBSubnetB3"), Ref("JVBSubnetB4"),
            Ref("JVBSubnetB5"), Ref("JVBSubnetB6"),
            Ref("JVBSubnetB7"), Ref("JVBSubnetB8"),
            Ref("PublicSubnetA"), Ref("PublicSubnetB")
        ],
        InstanceTagKey='shard-role',
        InstanceTagValue='ssh'
))

def add_ipv6_network_cft_resources(t):
    enable_ipv6_cidr = t.add_resource(VPCCidrBlock(
        'VPCIpv6',
        DependsOn=['JVBSubnetA1','JVBSubnetA2','JVBSubnetA3','JVBSubnetA4','JVBSubnetA5','JVBSubnetA6','JVBSubnetA7','JVBSubnetA8','JVBSubnetB1','JVBSubnetB2','JVBSubnetB3','JVBSubnetB4','JVBSubnetB5','JVBSubnetB6','JVBSubnetB7','JVBSubnetB8','PublicSubnetA','PublicSubnetA'],
        AmazonProvidedIpv6CidrBlock=True,
        VpcId=Ref("VaasVPC")
    ))

    jvb_subnet_a1_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetA1VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("0", Ref("JVBSubnetACidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetA1')
    ))

    jvb_subnet_a2_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetA2VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("1", Ref("JVBSubnetACidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetA2')
    ))

    jvb_subnet_a3_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetA3VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("2", Ref("JVBSubnetACidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetA3')
    ))

    jvb_subnet_a4_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetA4VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("3", Ref("JVBSubnetACidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetA4')
    ))

    jvb_subnet_a5_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetA5VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("4", Ref("JVBSubnetACidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetA5')
    ))

    jvb_subnet_a6_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetA6VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("5", Ref("JVBSubnetACidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetA6')
    ))

    jvb_subnet_a7_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetA7VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("6", Ref("JVBSubnetACidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetA7')
    ))

    jvb_subnet_a8_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetA8VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("7", Ref("JVBSubnetACidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetA8')
    ))

    jvb_subnet_b1_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetB1VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("0", Ref("JVBSubnetBCidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetB1')
    ))

    jvb_subnet_b2_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetB2VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("1", Ref("JVBSubnetBCidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetB2')
    ))

    jvb_subnet_b3_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetB3VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("2", Ref("JVBSubnetBCidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetB3')
    ))

    jvb_subnet_b4_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetB4VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("3", Ref("JVBSubnetBCidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetB4')
    ))

    jvb_subnet_b5_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetB5VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("4", Ref("JVBSubnetBCidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetB5')
    ))

    jvb_subnet_b6_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetB6VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("5", Ref("JVBSubnetBCidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetB6')
    ))

    jvb_subnet_b7_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetB7VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("6", Ref("JVBSubnetBCidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetB7')
    ))

    jvb_subnet_b8_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JVBSubnetB8VPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Select("7", Ref("JVBSubnetBCidrsIPv6"))
        ]),
        SubnetId=Ref('JVBSubnetB8')
    ))

    public_subnetA_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'PublicSubnetAVPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Ref("PublicSubnetACidrIPv6")
        ]),
        SubnetId=Ref('PublicSubnetA')
    ))

    public_subnetB_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'PublicSubnetBVPCIpv6',
        DependsOn="VPCIpv6",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", Select("0", GetAtt('VaasVPC', 'Ipv6CidrBlocks')))),
            Ref("PublicSubnetBCidrIPv6")
        ]),
        SubnetId=Ref('PublicSubnetB')
    ))

    vass_network_acl_entry_egress_allow_all_ipv6 = t.add_resource(NetworkAclEntry(
        'VaasNetworkACLEntryEgressAllowAllIPv6',
        Ipv6CidrBlock="::/0",
        Egress=True,
        Protocol="-1",
        RuleAction="allow",
        RuleNumber="101",
        NetworkAclId=Ref("VaasNetworkACL")
    ))

    vass_network_acl_entry_ingres_allow_all_ipv6 = t.add_resource(NetworkAclEntry(
        'VaasNetworkACLEntryIngresAllowAllIPv6',
        Ipv6CidrBlock="::/0",
        Protocol="-1",
        RuleAction="allow",
        RuleNumber="101",
        NetworkAclId=Ref("VaasNetworkACL")
    ))

    route1_ipv6 = t.add_resource(Route(
        'route1ipv6',
        DestinationIpv6CidrBlock="::/0",
        RouteTableId=Ref("VaasRouteTablePrivate"),
        GatewayId=Ref("VaasIGW"),
        DependsOn="VaasVPCIGWLink",
    ))

    route2_ipv6 = t.add_resource(Route(
        'route2ipv6',
        DestinationIpv6CidrBlock="::/0",
        RouteTableId=Ref("VaasRouteTablePublic"),
        GatewayId=Ref("VaasIGW"),
        DependsOn="VaasVPCIGWLink",
    ))

    ingress8ipv6 = t.add_resource(SecurityGroupIngress(
        'ingress8ipv6',
        GroupId=Ref("JVBSecurityGroup"),
        IpProtocol="udp",
        FromPort="10000",
        ToPort="20000",
        CidrIpv6="::/0",
    ))

    ingress9ipv6 = t.add_resource(SecurityGroupIngress(
        'ingress9ipv6',
        GroupId=Ref("JVBSecurityGroup"),
        IpProtocol="tcp",
        FromPort="443",
        ToPort="443",
        CidrIpv6="::/0",
    ))

    ingress10ipv6 = t.add_resource(SecurityGroupIngress(
        'ingress10ipv6',
        GroupId=Ref("JVBSecurityGroup"),
        IpProtocol="icmpv6",
        FromPort="-1",
        ToPort="-1",
        CidrIpv6="::/0",
    ))

    ingress0ipv6 = t.add_resource(SecurityGroupIngress(
        'ingress0ipv6',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="80",
        ToPort="80",
        CidrIpv6="::/0"
    ))

    ingress4ipv6 = t.add_resource(SecurityGroupIngress(
        'ingress4ipv6',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="443",
        ToPort="443",
        CidrIpv6="::/0"
    ))

    ingress5ipv6 = t.add_resource(SecurityGroupIngress(
        'ingress5ipv6',
        GroupId=Ref("SignalSecurityGroup"),
        IpProtocol="tcp",
        FromPort="5222",
        ToPort="5222",
        CidrIpv6="::/0"
    ))

    ingress6ipv6 = t.add_resource(SecurityGroupIngress(
        'ingress6ipv6',
        GroupId=Ref("PublicNetworkSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        CidrIpv6="::/0"
    ))

# this generates a CFT which builds base network stack
def create_network_template(filepath, enable_ipv6=False):
    t = create_template()
    add_default_tag_parameters(t)
    add_stack_name_region_alias_parameters(t)
    add_stack_key_parameters(t)
    add_stack_domain_parameters(t)
    add_stack_virtualization_parameters(t)
    if enable_ipv6:
        add_ipv6_network_cft_resources(t)
        add_autoassign_ipv6_custom_resource(t)
    add_network_cft_parameters(t)
    add_network_cft_resources(t, enable_ipv6)

    add_network_output(t, enable_ipv6)
    write_template_json(filepath, t)


def main():
    parser = argparse.ArgumentParser(description='Create Network stack template')

    parser.add_argument('--filepath', action='store',
                        help='Path to template file', default=None, required=False)
    # parser.add_argument('--skip_template_generation', action='store_true', default=False,
    #                     help='Skip network CFT generation')
    parser.add_argument('--enable_ipv6', action='store', type=distutils.util.strtobool, help='Enable IPv6',
                        default=False)
    # parser.add_argument('--region', action='store',
    #                     help='AWS region)', default=None, required=False)
    # parser.add_argument('--regionalias', action='store',
    #                     help='AWS region alias)', default=None)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', type=str, default=None, required=False)
    # parser.add_argument('--autoassign_ipv6_on_creation', action='store_true', default=False, required=False,
    #                     help='Enable autoassign IPV6 on creation')
    # parser.add_argument('--pull_network', action='store_true', default=False, required=False,
    #                     help='Pull network stack data')

    args = parser.parse_args()

    args.enable_ipv6 = bool(args.enable_ipv6)

    if not args.filepath:
        print ('No path to template file')
        exit(1)

    #if args.pull_network:
     #   if not args.regionalias:
     #       regionalias = args.region
     #   else:
     #       regionalias = args.regionalias

    #     opts = pull_network_stack_vars(region=args.region, stackprefix=args.stackprefix, regionalias=regionalias)
    # else:
    #     opts = None

    # if args.autoassign_ipv6_on_creation:
        #autoassign_ipv6_on_creation(region=args.region, vpc_id=opts['vpc_id'], enable_autoassign_ipv6=args.enable_ipv6)

    # if not args.skip_template_generation:
    create_network_template(filepath=args.filepath, enable_ipv6=args.enable_ipv6)


if __name__ == '__main__':
    main()
