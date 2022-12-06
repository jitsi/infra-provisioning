#!/usr/bin/env python

from templatelib import *

import boto3, re, argparse, json, os
from troposphere import Parameter, Ref, Template, Join, Tags, Base64, Output, GetAtt, cloudformation, Select, Split

from troposphere.ec2 import EIP, NatGateway, Subnet, SubnetNetworkAclAssociation, SubnetRouteTableAssociation, RouteTable, Route, EgressOnlyInternetGateway, SubnetCidrBlock


def add_nat_network_output(t, opts):
    t.add_output([
        Output(
            'NATNetworkVPCId',
            Description="Stack VPC Id",
            Value=opts['vpc_id'],
        ),
        Output(
            'EgressOnlyInternetGateway',
            Description="Stack VPC Id",
            Value=Ref("EgressOnlyInternetGateway"),
        ),
        Output(
            'NATSubnetA',
            Description= "Subnet ID for the first AZ",
            Value= Ref("NATSubnetA"),
        ),
        Output(
            'NATSubnetB',
            Description= "Subnet ID for the second AZ",
            Value= Ref("NATSubnetB"),
        ),
        Output(
            'NATRouteTableA',
            Description= "Route Table for first AZ",
            Value= Ref("NATARouteTable"),
        ),
        Output(
            'NATRouteTableB',
            Description= "Route Table for second AZ",
            Value= Ref("NATBRouteTable"),
        ),
    ])


def add_nat_network_cft_parameters(t, opts):
    param_az1_letter_param = t.add_parameter(Parameter(
        "AZ1Letter",
        Description="Ending letter for initial availability zone in region",
        Type="String",
        Default="a"
    ))
    param_az2_letter_param = t.add_parameter(Parameter(
        "AZ2Letter",
        Description="Ending letter for second availability zone in region",
        Type="String",
        Default="b"
    ))
    param_cidr_subnetA_param = t.add_parameter(Parameter(
        "NATSubnetACidr",
        Description="CIDR for NAT Subnet in the initial availability zone",
        ConstraintDescription="Should look like 10.0.64.0/18",
        Type="String",
        Default="10.0.64.0/18"
    ))
    param_cidr_subnetB_param = t.add_parameter(Parameter(
        "NATSubnetBCidr",
        Description="CIDR for NAT Subnet in the second availability zone",
        ConstraintDescription="Should look like 10.0.128.0/18",
        Type="String",
        Default="10.0.128.0/18"
    ))

    param_cidr_natsubnetA_ipv6 = t.add_parameter(Parameter(
        "NATSubnetACidrIPv6",
        Description="CIDR for IPv6 public subnet in the 1st AvailabilityZone",
        ConstraintDescription="Should look like 03::/64",
        Type="String",
        Default="03::/64"
    ))

    param_cidr_natsubnetB_ipv6 = t.add_parameter(Parameter(
        "NATSubnetBCidrIPv6",
        Description="CIDR for IPv6 public subnet in the 2nd AvailabilityZone",
        ConstraintDescription="Should look like 04::/64",
        Type="String",
        Default="04::/64"
    ))


def add_nat_network_cft_resources(t,opts):

    #add an EIP for both nat gateways
    if not 'use_nat_gateway' in opts:
        opts['use_nat_gateway'] = True

    if opts['use_nat_gateway']:
        nat_gateway_eip_a = t.add_resource(EIP(
            'NATGWEIPA',
        ))

        nat_gateway_eip_b = t.add_resource(EIP(
            'NATGWEIPB',
        ))

        nat_gateway_a = t.add_resource(NatGateway(
            'NATAGateway',
            AllocationId=GetAtt("NATGWEIPA", "AllocationId"),
            SubnetId=opts['public_subnetA']
        ))

        nat_gateway_b = t.add_resource(NatGateway(
            'NATBGateway',
            AllocationId=GetAtt("NATGWEIPB", "AllocationId"),
            SubnetId=opts['public_subnetB']
        ))

        egress_internet_gateway_a = t.add_resource(EgressOnlyInternetGateway(
            'EgressOnlyInternetGateway',
            VpcId=opts['vpc_id']
        ))

    nat_subnet_a = t.add_resource(Subnet(
        'NATSubnetA',
        CidrBlock=Ref("NATSubnetACidr"),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),
        MapPublicIpOnLaunch=False,
        VpcId=opts['vpc_id'],
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-NATSubnet"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            role='NAT'
        )
    ))
    nat_subnet_b = t.add_resource(Subnet(
        'NATSubnetB',
        CidrBlock=Ref("NATSubnetBCidr"),
        AvailabilityZone=Join("",[Ref("AWS::Region"),Ref("AZ2Letter")]),
        MapPublicIpOnLaunch=False,
        VpcId=opts['vpc_id'],
        Tags=Tags(
            Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-NATSubnet"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            role='NAT'
        )
    ))
    nat_subnet_a_acl_association = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl1',
        NetworkAclId=opts['network_acl_id'],
        SubnetId=Ref("NATSubnetA"),
        DependsOn="NATSubnetA"
    ))
    nat_subnet_b_acl_association = t.add_resource(SubnetNetworkAclAssociation(
        'subnetacl2',
        NetworkAclId=opts['network_acl_id'],
        SubnetId=Ref("NATSubnetB"),
        DependsOn="NATSubnetB"
    ))


    net_subnet_a_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'NATSubnetAVPCIpv6',
        DependsOn="NATSubnetA",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", opts['ipv6_cidr'])),
            Ref("NATSubnetACidrIPv6")
        ]),
        SubnetId=Ref('NATSubnetA')
    ))

    net_subnet_b_enable_ipv6 = t.add_resource(SubnetCidrBlock(
        'NATSubnetBVPCIpv6',
        DependsOn="NATSubnetB",
        Ipv6CidrBlock=Join('', [
            Select("0", Split("00::/56", opts['ipv6_cidr'])),
            Ref("NATSubnetBCidrIPv6")
        ]),
        SubnetId=Ref('NATSubnetB')
    ))

    if opts['use_nat_gateway']:
        nat_a_route_table = t.add_resource(RouteTable(
            'NATARouteTable',
            VpcId=opts['vpc_id'],
            Tags=Tags(
                Name=Join("", [Ref("RegionAlias"),Ref("AZ1Letter"),"-",Ref("StackNamePrefix"),"-NATRouteTable"]),
                Environment=Ref("TagEnvironmentType"),
                Service=Ref("TagService"),
                Owner=Ref("TagOwner"),
                Team=Ref("TagTeam"),
                Product=Ref("TagProduct"),
                role='NAT'
            )
        ))
        nat_b_route_table = t.add_resource(RouteTable(
            'NATBRouteTable',
            VpcId=opts['vpc_id'],
            Tags=Tags(
                Name=Join("", [Ref("RegionAlias"),Ref("AZ2Letter"),"-",Ref("StackNamePrefix"),"-NATRouteTable"]),
                Environment=Ref("TagEnvironmentType"),
                Service=Ref("TagService"),
                Owner=Ref("TagOwner"),
                Team=Ref("TagTeam"),
                Product=Ref("TagProduct"),
                role='NAT'
            )        
        ))

        nat_a_route = t.add_resource(Route(
            'NATARoute',
            DestinationCidrBlock='0.0.0.0/0',
            RouteTableId=Ref("NATARouteTable"),
            NatGatewayId=Ref("NATAGateway"),
            DependsOn=["NATAGateway","NATARouteTable"]
        ))

        nat_b_route = t.add_resource(Route(
            'NATBRoute',
            DestinationCidrBlock='0.0.0.0/0',
            RouteTableId=Ref("NATBRouteTable"),
            NatGatewayId=Ref("NATBGateway"),
            DependsOn=["NATBGateway","NATBRouteTable"]
        ))

        nat_a_ipv6_route = t.add_resource(Route(
            'NATAIPv6Route',
            DestinationIpv6CidrBlock='::/0',
            RouteTableId=Ref("NATARouteTable"),
            EgressOnlyInternetGatewayId=Ref("EgressOnlyInternetGateway"),
            DependsOn=["EgressOnlyInternetGateway","NATARouteTable"]
        ))

        nat_b_ipv6_route = t.add_resource(Route(
            'NATBIPv6Route',
            DestinationIpv6CidrBlock='::/0',
            RouteTableId=Ref("NATBRouteTable"),
            EgressOnlyInternetGatewayId=Ref("EgressOnlyInternetGateway"),
            DependsOn=["EgressOnlyInternetGateway","NATBRouteTable"]
        ))


        nat_subnet_a_route_association = t.add_resource(SubnetRouteTableAssociation(
            'subnetroute1',
            RouteTableId=Ref("NATARouteTable"),
            SubnetId=Ref("NATSubnetA"),
            DependsOn=["NATSubnetA","NATARouteTable"]
        ))

        nat_subnet_b_route_association = t.add_resource(SubnetRouteTableAssociation(
            'subnetroute2',
            RouteTableId=Ref("NATBRouteTable"),
            SubnetId=Ref("NATSubnetB"),
            DependsOn=["NATSubnetB","NATBRouteTable"]
        ))
    else:
        nat_subnet_a_route_association = t.add_resource(SubnetRouteTableAssociation(
            'subnetroute1',
            RouteTableId=Ref("NATRouteTable"),
            SubnetId=Ref("NATSubnetA"),
            DependsOn=["NATSubnetA"]
        ))

        nat_subnet_b_route_association = t.add_resource(SubnetRouteTableAssociation(
            'subnetroute2',
            RouteTableId=Ref("NATRouteTable"),
            SubnetId=Ref("NATSubnetB"),
            DependsOn=["NATSubnetB"]
        ))





#this generates a CFT which builds two large NAT subnets behind a NAT gateway for use with services that do not require public IP addresses
def create_nat_network_template(filepath,opts):
    t  = create_template()
    add_default_tag_parameters(t)
    add_stack_name_region_alias_parameters(t)
    add_nat_network_cft_parameters(t,opts)
    add_nat_network_cft_resources(t,opts)

    add_nat_network_output(t,opts)
    write_template_json(filepath,t)



def main():
    parser = argparse.ArgumentParser(description='Create Nat network stack template')
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
        create_nat_network_template(filepath=args.filepath,opts=opts)

if __name__ == '__main__':
    main()
