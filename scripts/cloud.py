#!/usr/bin/env python

import argparse
import botocore
from hcvlib import *


parser = argparse.ArgumentParser(description='Produce a list of AMIs for use in jitsi infrastructure')
parser.add_argument('--batch', action='store_true', default=False,
                   help='Outputs only the AMI id matching version and type.  Meant for use in other tools')
parser.add_argument('--name', action='store',
                   help='Name of cloud', default=None)
parser.add_argument('--region', action='store',
                   help='AWS Region', default=None)
parser.add_argument('--region_alias', action='store',
                   help='Region alias', default=None)
parser.add_argument('--prefix', action='store',
                   help='Stack Prefix', default=None)
parser.add_argument('--action', action='store',
                   help='Action to perform', default='list')

args = parser.parse_args()

if args.action == 'list':
    cl = get_cloud_list()
    cl.sort(reverse=False, key=lambda x: x['name'])
    for c in cl:
        print(("%s"%c['name']))

if args.action == 'export':
    if not args.name:
        print('No cloud name specified, exiting...')
    if not args.region:
        print('No region provided, exiting...')
    else:        
        regionalias = os.environ.get('REGION_ALIAS')
        stackprefix = os.environ.get('CLOUD_PREFIX')
        if args.region_alias:
            regionalias = args.region_alias
        if args.prefix:
            stackprefix = args.prefix

        if not stackprefix:
            stackprefix=args.name.split('-')[-1]

        if not regionalias:
            regionalias = args.region

        outputs = pull_network_stack_outputs(args.region, regionalias, stackprefix)
        for o in outputs:
            print(('export %s=%s'%(o,outputs[o])))

