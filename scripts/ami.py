#!/usr/bin/env python

# pip install boto3 awscli

import argparse
import botocore
from hcvlib import *


parser = argparse.ArgumentParser(description='Produce a list of AMIs for use in jitsi infrastructure')
parser.add_argument('--batch', action='store_true', default=False,
                   help='Outputs only the AMI id matching version and type.  Meant for use in other tools')
parser.add_argument('--type', action='store',
                   help='Type of images (JVB or Signal)', default='JVB')
parser.add_argument('--version', action='store',
                   help='Version of package (defaults to most recent)', default='latest')
parser.add_argument('--region', action='store',
                   help='AWS Region', default=None)
parser.add_argument('--ami', action='store',
                   help='AMI to check state for', default=None)
parser.add_argument('--architecture', action='store',
                   help='Architecture filter (arm64 or x64_64)', default='x86_64')
parser.add_argument('--state', action='store_true',
                   help='Output AMI state', default=False)
parser.add_argument('--list', action='store_true',
                   help='List AMIs matching criteria', default=True)
parser.add_argument('--name', action='store_true',
                   help='Show AMI name for specified image with --ami', default=False)
parser.add_argument('--list_all', action='store_true',
                   help='List AMIs matching criteria', default=False)
parser.add_argument('--clean', action='store',
                   help='Count of AMIs to leave (not counting stable versions)', default=None)
parser.add_argument('--clean_date', action='store',
                   help='Earliest Date of AMIs to leave', default=None)
parser.add_argument('--add_tags', action='store_true',
                    help='Add tag to AMI',default=False)
parser.add_argument('--delete', action='store_true',
                   help='Delete AMIs during clean operation', default=False)


args = parser.parse_args()

dryRun=False

if not args.region:
    args.region=AWS_DEFAULT_REGION

if args.region == 'all':
    regions = AWS_REGIONS
else:
    regions = [ args.region ]

for region in regions:
    ec2 = boto3.resource('ec2', region_name=region)

    if args.clean_date:
        clean_ts = int(args.clean_date)

        print(('Region: %s'%region))
        #clean out all but this many images
        name_filter = args.type

        images = get_image_list(ec2, name_filter, architecture=args.architecture)

#        pprint.pprint(images)

        clean_images = [ i for i in images if int(i['image_epoch_ts']) < clean_ts ]
        if len(clean_images) > 0:
            deregistered_images=[]

            for i in clean_images:
                if args.delete:
                    image = ec2.Image(i['image_id'])
                    print(('clean is deleting %s %s (%s)'%(args.type,i['image_version'],i['image_id'])))
                    deregistered_images.append(i['image_id'])
                    try:
                        image.deregister(DryRun=dryRun)
                    except botocore.exceptions.ClientError as e:
                        pprint.pprint(e)
                        if e.response['Error']['Code']=='DryRunOperation':
                            pass
                        else:
                            raise e
                else:
                    print(('clean candidate %s %s (%s) %s'%(args.type,i['image_version'],i['image_id'],i['image_ts'])))

                for snapshot in ec2.snapshots.filter(OwnerIds=['self']):
                    r = re.match(r".*for( DestinationAmi)? (ami-.*) from.*", snapshot.description)
                    if r:
                        if r.groups()[1] in deregistered_images:
                            print(('deleting snapshot %s desc: %s'%(snapshot.id,snapshot.description)))
                            try:
                                snapshot.delete(DryRun=dryRun)
                            except botocore.exceptions.ClientError as e:
                                pprint.pprint(e)
                                if e.response['Error']['Code']=='DryRunOperation':
                                    pass
                                else:
                                    raise e

        else:
            print(("No cleanup needed for %s, %s younger images found"%(args.type,len(images))))

    if args.clean:
        print(('Region: %s'%region))
        #clean out all but this many images
        name_filter = args.type

        images = get_image_list(ec2, name_filter, architecture=args.architecture)

        images.sort(key=lambda x: x['image_ts'],reverse=True)

        #get the list of stable builds (from somewhere, hardcoded for now)
        stable_versions=get_stable_versions(args.type)


    #    pprint.pprint(stable_versions)
        #pull out stable images for the list, since we always keep those
        images = [ i for i in images if i['image_version'] not in stable_versions ]

    #    pprint.pprint(images)

        #if we have more images than we've been told to keep
        clean_count = int(args.clean)
        if len(images) > clean_count:
            deregistered_images=[]
            #now take the bottom args.clean->N items and delete them (or output them)
            for i in images[clean_count:]:
                if args.delete:
                    image = ec2.Image(i['image_id'])
                    print(('clean is deleting %s %s (%s)'%(args.type,i['image_version'],i['image_id'])))
                    deregistered_images.append(i['image_id'])
                    try:
                        image.deregister(DryRun=dryRun)
                    except botocore.exceptions.ClientError as e:
                        pprint.pprint(e)
                        if e.response['Error']['Code']=='DryRunOperation':
                            pass
                        else:
                            raise e
                else:
                    print(('clean candidate %s %s (%s) %s'%(args.type,i['image_version'],i['image_id'],i['image_ts'])))

            for snapshot in ec2.snapshots.filter(OwnerIds=['self']):
                r = re.match(r".*for( DestinationAmi)? (ami-.*) from.*", snapshot.description)
                if r:
                    if r.groups()[1] in deregistered_images:
                        print(('deleting snapshot %s desc: %s'%(snapshot.id,snapshot.description)))
                        try:
                            snapshot.delete(DryRun=dryRun)
                        except botocore.exceptions.ClientError as e:
                            pprint.pprint(e)
                            if e.response['Error']['Code']=='DryRunOperation':
                                pass
                            else:
                                raise e

        else:
            print(("No cleanup needed for %s, only %s images found"%(args.type,len(images))))


    elif args.list:
        if not args.ami:
            name_filter = args.type

            if args.version == 'latest':
                images = get_image_list(ec2, name_filter, architecture=args.architecture)
            else:
                images = get_image_list(ec2,name_filter,args.version, architecture=args.architecture)

            if len(images) >0:
                found_image = images[0]
            else:
                found_image = False

        if args.batch:
            if not args.list_all:
                if found_image:
                    #success, so simply print the image ID
                    print((found_image['image_id']))

                else:
                    #print 'No image found'
                    #didn't find version requested, so print to stderr and exit
                    warning('No image found matching version: '+args.version)
                    exit(1)
            else:
                print((' '.join([image['image_id'] for image in images])))
        elif args.state:
            if not args.ami:
                if found_image:
                    args.ami = found_image['image_id']
                else:
                    warning('No AMI found or provided to find state for')
                    exit(1)

            state = ''
            try:
                image = ec2.Image(args.ami)
                state = image.state
            except botocore.exceptions.ClientError as e:
                warning('Client Exception: %s'%e)
            print(state)
        elif args.name:
            if not args.ami:
                if found_image:
                    args.ami = found_image['image_id']
                else:
                    warning('No AMI found or provided to find name for')
                    exit(1)

            name = ''
            try:
                image = ec2.Image(args.ami)
                name = image.name
            except botocore.exceptions.ClientError as e:
                warning('Client Exception: %s'%e)
            print(name)
        elif args.add_tags:
            print(('Region: %s' % region))
            # add tags to AMI
            if args.type:
                name_filter = args.type
                print(('Adding tags for images of type: %s'%name_filter))
                images = add_image_tag(ec2, name_filter)
                if (images):
                    print_image_list(images)
                else:
                    print('No images found to tag')
            else:
                warning('No type specified, no tags created')
                exit(1)

        else:
            print(('Region: %s'%region))
            print_image_list(images)
