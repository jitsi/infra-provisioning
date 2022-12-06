#!/usr/bin/env python

from templatelib import *

import argparse, json
from troposphere import Parameter, Ref


from troposphere.ec2 import  TransitGatewayRoute

def filter_cidrs(cidrs):
    out_cidrs=[]
    for cidr in cidrs:
        # skip any cidr not starting with 10
        if cidr.startswith('10.'):
            out_cidrs.append('.'.join(cidr.split('.')[:2])+'.0.0/16')

    out_cidrs=list(set(out_cidrs))

    return out_cidrs


def add_link_cft_resources(t,link_gateways):
    for g in link_gateways:
        for cidr in filter_cidrs(g['cidrs']):
            resource_name='TGA{}N{}'.format(g['cloud'].replace('-',''),cidr.replace('.','d').replace('/','S'))
            t.add_resource(TransitGatewayRoute(
                resource_name,
                DestinationCidrBlock=cidr,
                TransitGatewayAttachmentId=g['attachment_id'],
                TransitGatewayRouteTableId=Ref("TransitGatewayRouteTableId")
            ))

def create_transit_gateway_routes_template(filepath,link_gateways):
    t  = create_template()

    t.add_parameter(Parameter(
        "TransitGatewayRouteTableId",
        Description="Route Table for Transit Gateway",
        Type="String"
    ))
    add_link_cft_resources(t,link_gateways)

    write_template_json(filepath,t)

def read_mesh_json(meshpath):
    data = {}
    with open(meshpath) as f:
        data = json.load(f)

    return data


def main():
    parser = argparse.ArgumentParser(description='Create transit gateway routes template')
    parser.add_argument('--filepath', action='store',
                        help='Path to template file', default=False, required=False)
    parser.add_argument('--meshpath', action='store',
                        help='Path to mesh json input file', required=True)                        

    args = parser.parse_args()

    if not args.filepath:
        print ('No path to template file')
        exit(2)
    else:
        link_gateways=[]
        mesh=read_mesh_json(args.meshpath)
        for m in mesh:
            if 'attachment_id' in m:
                link_gateways.append(m)

        create_transit_gateway_routes_template(filepath=args.filepath,link_gateways=link_gateways)

if __name__ == '__main__':
    main()
