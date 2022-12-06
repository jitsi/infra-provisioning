#!/usr/bin/env python
import boto3, re, argparse, json, os, awacs

from templatelib import *
from awacs.aws import Statement, Principal
from awacs.sts import AssumeRole
from troposphere import Parameter, Ref, Join, Tags, Base64, Output, GetAtt, Export, Select, Split
from troposphere.route53 import RecordSetType
from troposphere.iam import Role, InstanceProfile, Policy
from troposphere.ec2 import Subnet, SubnetNetworkAclAssociation, SubnetRouteTableAssociation, \
    RouteTable, Route, VPC, InternetGateway, DHCPOptions, NetworkAcl, NetworkAclEntry, VPCGatewayAttachment, \
    VPCDHCPOptionsAssociation, SecurityGroupRule, SecurityGroupEgress,Instance, SubnetCidrBlock


def add_network_jigasi_output(t):
    t.add_output([
        Output(
            'JigasiSubnetA',
            Description="The subnet IDs for Jigasi in first AZ",
            Value=Join(",",[Ref("JigasiSubnetA"), Ref("JigasiSubnetA2")]),
        ),
        Output(
            'JigasiSubnetB',
            Description="The subnet IDs for Jigasi in second AZ",
            Value=Join(",",[Ref("JigasiSubnetB"), Ref("JigasiSubnetB2")]),
        ),
        Output(
            'JigasiSubnetsIds',
            Description= "The Subnets IDs for the Jigasi Subnets",
            Value=Join(",",[Ref("JigasiSubnetA"), Ref("JigasiSubnetB"),Ref("JigasiSubnetA2"), Ref("JigasiSubnetB2")]),
        ),
        
    ])

def add_network_jigasi_cft_parameters(t):
    
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
    
    param_jigasi_cidr_publicsubnetA = t.add_parameter(Parameter(
        "JigasiSubnetACidr",
        Description="CIDR for private subnet in the 1st AvailabilityZone",
        ConstraintDescription="Should look like 10.0.3.0/27",
        Type="String",
        Default="10.0.3.0/27"
    ))
    
    param_jigasi_cidr_publicsubnetB = t.add_parameter(Parameter(
        "JigasiSubnetBCidr",
        Description="CIDR for private subnet in the 2nd AvailabilityZone",
        ConstraintDescription="Should look like 10.0.4.32/27",
        Type="String",
        Default="10.0.4.32/27"
    ))

    param_jigasi_cidr_publicsubnetA2 = t.add_parameter(Parameter(
        "JigasiSubnetA2Cidr",
        Description="CIDR for second private subnet in the 1st AvailabilityZone",
        ConstraintDescription="Should look like 10.0.19.0/24",
        Type="String",
        Default="10.0.19.0/24"
    ))
    
    param_jigasi_cidr_publicsubnetB2 = t.add_parameter(Parameter(
        "JigasiSubnetB2Cidr",
        Description="CIDR for second private subnet in the 2nd AvailabilityZone",
        ConstraintDescription="Should look like 10.0.20.0/24",
        Type="String",
        Default="10.0.20.0/24"
    ))

    param_jigasi_subnet_map_publicip = t.add_parameter(Parameter(
        "JigasiSubnetMapPublicIp",
        Description="Indicates whether JVB subnets should receive an AWS public IP address",
        Type="String",
        Default="false"
    ))
    
    tag_environment_param = t.add_parameter(Parameter(
        "TagEnvironment",
        Description="Tag: environment",
        Type="String",
        Default="all"
    ))

    param_cidr_subnetA_ipv6 = t.add_parameter(Parameter(
        "JigasiSubnetACidrIPv6",
        Description="CIDR for IPv6 public subnet in the 1st AvailabilityZone",
        ConstraintDescription="Should look like 05::/64",
        Type="String",
        Default="05::/64"
    ))

    param_cidr_subnetB_ipv6 = t.add_parameter(Parameter(
        "JigasiSubnetBCidrIPv6",
        Description="CIDR for IPv6 public subnet in the 2nd AvailabilityZone",
        ConstraintDescription="Should look like 06::/64",
        Type="String",
        Default="06::/64"
    ))

    param_cidr_subnetA_ipv6 = t.add_parameter(Parameter(
        "JigasiSubnetA2CidrIPv6",
        Description="CIDR for IPv6 public subnet in the 1st AvailabilityZone",
        ConstraintDescription="Should look like 05::/64",
        Type="String",
        Default="19::/64"
    ))

    param_cidr_subnetB_ipv6 = t.add_parameter(Parameter(
        "JigasiSubnetB2CidrIPv6",
        Description="CIDR for IPv6 public subnet in the 2nd AvailabilityZone",
        ConstraintDescription="Should look like 06::/64",
        Type="String",
        Default="20::/64"
    ))

def add_network_jigasi_cft_resources(t,opts):

    jigasi_subnetA = t.add_resource(Subnet(
        'JigasiSubnetA',
        CidrBlock=Ref("JigasiSubnetACidr"),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=Ref("JigasiSubnetMapPublicIp"),
        VpcId=opts.get('vpc_id'),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-JigasiSubnet"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='Jigasi'
        )
    ))

    jigasi_subnetA = t.add_resource(Subnet(
        'JigasiSubnetA2',
        CidrBlock=Ref("JigasiSubnetA2Cidr"),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=Ref("JigasiSubnetMapPublicIp"),
        VpcId=opts.get('vpc_id'),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-JigasiSubnet2"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='Jigasi'
        )
    ))

    public_subnetB = t.add_resource(Subnet(
        'JigasiSubnetB',
        CidrBlock=Ref("JigasiSubnetBCidr"),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=Ref("JigasiSubnetMapPublicIp"),
        VpcId=opts.get('vpc_id'),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-JigasiSubnet"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='Jigasi'
        )
    ))

    public_subnetB = t.add_resource(Subnet(
        'JigasiSubnetB2',
        CidrBlock=Ref("JigasiSubnetB2Cidr"),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=Ref("JigasiSubnetMapPublicIp"),
        VpcId=opts.get('vpc_id'),
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-JigasiSubnet2"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role='Jigasi'
        )
    ))

    subnetacl7 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl7',
        NetworkAclId=opts.get('network_acl_id'),
        SubnetId=Ref("JigasiSubnetA")
    ))

    subnetacl8 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl8',
        NetworkAclId=opts.get('network_acl_id'),
        SubnetId=Ref("JigasiSubnetB")
    ))

    subnetacl7 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl9',
        NetworkAclId=opts.get('network_acl_id'),
        SubnetId=Ref("JigasiSubnetA2")
    ))

    subnetacl8 = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl10',
        NetworkAclId=opts.get('network_acl_id'),
        SubnetId=Ref("JigasiSubnetB2")
    ))

    subnetroute7 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute7',
        RouteTableId=opts.get('nat_routetableA'),
        SubnetId=Ref("JigasiSubnetA")
    ))
    
    subnetroute8 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute8',
        RouteTableId=opts.get('nat_routetableB'),
        SubnetId=Ref("JigasiSubnetB")
    ))


    subnetroute7 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute9',
        RouteTableId=opts.get('nat_routetableA'),
        SubnetId=Ref("JigasiSubnetA2")
    ))
    
    subnetroute8 = t.add_resource(SubnetRouteTableAssociation(
        'subnetroute10',
        RouteTableId=opts.get('nat_routetableB'),
        SubnetId=Ref("JigasiSubnetB2")
    ))

    jigasi_subnet_a_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JigasiSubnetAVPCIpv6',
        DependsOn="JigasiSubnetA",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", opts['ipv6_cidr'])),
            Ref("JigasiSubnetACidrIPv6")
        ]),
        SubnetId=Ref('JigasiSubnetA')
    ))

    jigasi_subnet_b_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JigasiSubnetBVPCIpv6',
        DependsOn="JigasiSubnetB",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", opts['ipv6_cidr'])),
            Ref("JigasiSubnetBCidrIPv6")
        ]),
        SubnetId=Ref('JigasiSubnetB')
    ))

    jigasi_subnet_a_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JigasiSubnetA2VPCIpv6',
        DependsOn="JigasiSubnetA2",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", opts['ipv6_cidr'])),
            Ref("JigasiSubnetA2CidrIPv6")
        ]),
        SubnetId=Ref('JigasiSubnetA2')
    ))

    jigasi_subnet_b_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'JigasiSubnetB2VPCIpv6',
        DependsOn="JigasiSubnetB2",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", opts['ipv6_cidr'])),
            Ref("JigasiSubnetB2CidrIPv6")
        ]),
        SubnetId=Ref('JigasiSubnetB2')
    ))

#this generates a CFT which builds base network stack
def create_network_jigasi_template(filepath, opts):
    t  = create_template()
    add_default_tag_parameters(t)
    add_stack_name_region_alias_parameters(t)

    add_network_jigasi_cft_parameters(t)
    add_network_jigasi_cft_resources(t, opts)
    
    add_network_jigasi_output(t)
    write_template_json(filepath,t)

def main():
    parser = argparse.ArgumentParser(description='Create Jigasi network stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region alias)', default=False)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', default=False, required=False)
    parser.add_argument('--filepath', action='store',
                        help='Path to template file', default=False, required=False)
    parser.add_argument('--pull_network_stack', action='store',
                        help='Pull network variables from a network stack', default='true', required=False)

    args = parser.parse_args()

    if not args.region:
        print('No AWS region specified, exiting...')
        exit(1)
    elif not args.filepath:
        print ('No path to template file')
        exit(2)
    else:
        if not args.regionalias:
            regionalias = args.region
        else:
            regionalias=args.regionalias

        if args.pull_network_stack.lower() == "true":
            opts=pull_network_stack_vars(region=args.region, regionalias=regionalias, stackprefix=args.stackprefix)
            opts=fill_in_bash_network_vars(opts)
        else:
            opts=pull_bash_network_vars()
            
        create_network_jigasi_template(filepath=args.filepath,opts=opts)

if __name__ == '__main__':
    main()
