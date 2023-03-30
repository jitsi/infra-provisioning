#!/usr/bin/env python3
# pip install oci

import argparse
import sys
import oci
import json
import datetime

from hcvlib import delete_image, get_oracle_image_list_by_search, update_image_tags, get_oracle_image_by_id

OPERATING_SYSTEM = 'Canonical Ubuntu'
OPERATING_SYSTEM_VERSIONS = ['18.04', '20.04', '22.04']
IMAGE_LIFECYCLE_STATE = "AVAILABLE"

def warning(warn_str):
    sys.stderr.write(warn_str)

def date_time_converter(o):
    if isinstance(o, datetime.datetime):
        return o.__str__()

def image_data_from_image_obj(image, tag_namespace):
    # look for jitsi tags if environment tags aren't found
    if not tag_namespace in image.defined_tags:
        if 'jitsi' in image.defined_tags:
            image_tags = image.defined_tags['jitsi']
        else:
            image_tags = []
    else:
        image_tags = image.defined_tags[tag_namespace] or []

    return {'image_ts': image.time_created,
            'image_epoch_ts':image_tags.get('TS'),
            'image_type':image_tags.get('Type'),
            'image_base_type': image_tags.get('BaseImageType'),
            'image_base_ocid': image_tags.get('BaseImageOCID'),
            'image_version':image_tags.get('Version'),
            'image_build':image_tags.get('build_id'),
            'image_environment_type':image_tags.get('environment_type'),
            'image_meta_version':image_tags.get('MetaVersion'),
            'image_version':image_tags.get('Version'),
            'image_name': image.display_name,
            'image_id': image.id,
            'image_status': image.lifecycle_state,
            'image_compartment_id':image.compartment_id
            }


def tag_for_image_ns(tags,tag_name, tag_value,tag_namespace):
    if tag_namespace in tags and tag_name in tags[tag_namespace]:
        if tags[tag_namespace][tag_name] == tag_value:
            return True

    return False

def tag_for_image(image, tag_name, tag_value, tag_namespace):
    if tag_for_image_ns(image.defined_tags, tag_name, tag_value, tag_namespace):
        return True
    else:
        if tag_for_image_ns(image.defined_tags, tag_name, tag_value,'jitsi'):
            return True        
        else:
            return False

def list_images_paginated(compute, compartment_id):
    images = []
    for os in OPERATING_SYSTEM_VERSIONS:
        # Listing images is a paginated call, so we can use the oci.pagination module to get all results without having to manually handle page tokens
        list_images_response = oci.pagination.list_call_get_all_results(
            compute.list_images,
            compartment_id,
            operating_system=OPERATING_SYSTEM,
            operating_system_version=os,
            lifecycle_state=IMAGE_LIFECYCLE_STATE
        )
        images = images + list_images_response.data
    return images

def get_image_list(compute, compartment_id, tenancy_id, tag_namespace, type, version):
    tenancy_images = list_images_paginated(compute, tenancy_id)
    compartment_images = list_images_paginated(compute, compartment_id)
    images = tenancy_images + compartment_images

    return filter_images(images, tag_namespace=tag_namespace, type=type, version=version)

    # filter images based on type and version
def filter_images(images, tag_namespace, type, version):
    filtered_images = []
    for image in images:
        if tag_for_image(image, tag_name="Type", tag_value=type, tag_namespace=tag_namespace):
            if version == "latest":
                filtered_images.append(image)
            else:
                if tag_for_image(image, tag_name="Version", tag_value=version, tag_namespace=tag_namespace):
                    filtered_images.append(image)

    # sort images desc by creation date
    filtered_images_by_ts = []
    for filtered_image in filtered_images:
        filtered_images_by_ts.append(image_data_from_image_obj(filtered_image, tag_namespace))

    filtered_images_by_ts=sorted(filtered_images_by_ts,key=lambda timg: timg['image_ts'], reverse=True)

    # return filtered and sorted images
    return filtered_images_by_ts


parser = argparse.ArgumentParser(description='Produce a list of oracle custom images for use in jitsi infrastructure')
parser.add_argument('--type', action='store',
                    help='Type of images (JVB or Base)', default='JVB')
parser.add_argument('--version', action='store',
                    help='Version of package (defaults to most recent)', default='latest')
parser.add_argument('--region', action='store', help='Oracle Region', default='eu-frankfurt-1')
parser.add_argument('--compartment_id', action='store', help='Oracle Compartment Id', default='ocid1.compartment.oc1..aaaaaaaaqhjkvm74j5cz4cfbs5r3mumnvbujxbmn2vmjqzpeuzizfdtm4i4a')
parser.add_argument('--tenancy_id', action='store', help='Oracle tenancy', default='ocid1.tenancy.oc1..aaaaaaaakxqd22zn5pin6sjgluadmjovlxqrd7sakqm2suiy3xkgg2bac3hq')
parser.add_argument('--tag_namespace', action='store', help='Oracle Compartment Id', default='jitsi')
parser.add_argument('--image_details', action='store', help='Oracle Image Details', default=False)
parser.add_argument('--clean', action='store',
                   help='Count of images (JVB or Base) to leave', default=None)
parser.add_argument('--delete', action='store_true',
                   help='Delete images (JVB or Base) during clean operation', default=False)
parser.add_argument('--tag_production', action='store_true',
                   help='Tag image as having been used in production', default=False)
parser.add_argument('--image_id', action='store',
                   help='Image ID to tag', default='')

args = parser.parse_args()

if args.version != "latest" and not args.version.endswith("-1") and not args.type=='Signal':
    args.version = args.version + "-1"

config = oci.config.from_file()
compute_client = oci.core.ComputeClient(config)
compute_client.base_client.set_region(args.region)


version = args.version


if args.clean:
    # if we are cleaning do not filter by version
    version = False

    # old way, now deprecated in favor of search API
#    found_images = get_image_list(compute_client, args.compartment_id, args.tenancy_id, args.tag_namespace, args.type, version)
    # only clean images that are not tagged with freeform-tag  'production-image'
    found_images = get_oracle_image_list_by_search(args.type, version, [args.region], config)

    non_prod_images = [ x for x in found_images if not x['image_production'] ]
    prod_images = [ x for x in found_images if x['image_production'] ]

    #if we have more images than we've been told to keep
    clean_count = int(args.clean)
    if len(non_prod_images) > clean_count:
        #now take the bottom args.clean->N items and delete them
        for i in non_prod_images[clean_count:]:
           # now search for active instance configurations referencing this image
            if args.delete:
                print(("Delete non_prod_images %s image, image_id %s"%(args.type,i['image_name'])))
                delete_image(compute_client, i['image_id'])
            else:
               print(('Clean non_prod_images candidate %s %s (%s) %s'%(args.type,i['image_version'],i['image_id'],i['image_ts'])))
    else:
       print(("No non_prod_images cleanup needed for %s, only %s images found"%(args.type,len(non_prod_images))))

    if len(prod_images) > clean_count:
        #now take the bottom args.clean->N items and delete them
        for i in prod_images[clean_count:]:
           # now search for active instance configurations referencing this image
            if args.delete:
                print(("Delete prod_images %s image, image_id %s"%(args.type,i['image_name'])))
                delete_image(compute_client, i['image_id'])
            else:
               print(('Clean prod_images candidate %s %s (%s) %s'%(args.type,i['image_version'],i['image_id'],i['image_ts'])))
    else:
       print(("No prod_images cleanup needed for %s, only %s images found"%(args.type,len(prod_images))))


elif args.tag_production:
    if not args.image_id:
        print("No image_id provided, exiting...")
        exit(2)
    else:
        found_image = get_oracle_image_by_id(args.image_id, args.region)

        update_image_tags(found_image, {'production-image': 'true'})
else:
    # new way, using search API instead of brute force dump of all images
    found_images = get_oracle_image_list_by_search(args.type, version, [args.region], config)

    if len(found_images) > 0:
        if args.image_details:
            print(json.dumps(found_images[0], default = date_time_converter))
        else:
            print(found_images[0]['image_id'])
    else:
        warning('No image found matching type {} and version {}'.format(args.type, args.version))
        exit(1)
