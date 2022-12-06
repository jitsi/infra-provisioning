#!/usr/bin/env python

from templatelib import *

import boto3, argparse, json
from troposphere import Parameter, Ref

from troposphere.ec2 import Route

def add_route_resources(t,route_tables,cidrs):
    for rt in route_tables:
        for cidr in cidrs:
            if cidr:
                resource_name='{}N{}'.format(rt.replace('-',''),cidr.replace('.','d').replace('/','S'))
                t.add_resource(Route(
                    resource_name,
                    DestinationCidrBlock=cidr,
                    RouteTableId=rt,
                    TransitGatewayId=Ref("TransitGatewayId")
                ))

def create_transit_gateway_vpc_routes_template(filepath,route_tables,cidrs):
    t  = create_template()

    t.add_parameter(Parameter(
        "TransitGatewayId",
        Description="Transit Gateway ID for routes",
        Type="String"
    ))
    add_route_resources(t,route_tables,cidrs)

    write_template_json(filepath,t)

def main():
    parser = argparse.ArgumentParser(description='Create transit gateway routes template')
    parser.add_argument('--filepath', action='store',
                        help='Path to template file', default=False, required=False)
    parser.add_argument('--cidrs', action='store',
                        help='List of cidrs to route', required=True)                        
    parser.add_argument('--tables', action='store',
                        help='List of route table IDs to add routes to', required=True)

    args = parser.parse_args()

    if not args.filepath:
        print ('No path to template file')
        exit(2)
    else:
        route_tables = args.tables.split(',')
        cidrs = args.cidrs.split(',')

        create_transit_gateway_vpc_routes_template(filepath=args.filepath,route_tables=route_tables,cidrs=cidrs)

if __name__ == '__main__':
    main()
