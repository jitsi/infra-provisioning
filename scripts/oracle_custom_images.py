#!/usr/bin/env python3
# pip install oci

import argparse
import sys
import oci
import json
import datetime

from hcvlib import delete_image, get_oracle_image_list_by_search, update_image_tags, get_oracle_image_by_id, update_image_shapes, get_image_shapes

OPERATING_SYSTEM = 'Canonical Ubuntu'
OPERATING_SYSTEM_VERSIONS = ['18.04', '20.04', '22.04', '24.04']
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
            'image_architecture': image_tags.get('Arch'),
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
parser.add_argument('--architecture', action='store', help='Architecture', default='x86_64')
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
parser.add_argument('--get_shape_compatibility', action='store_true',
                   help='Show shapes for image compatibility', default=False)
parser.add_argument('--add_shape_compatibility', action='store_true',
                   help='Add shapes for image compatibility', default=False)
parser.add_argument('--image_id', action='store',
                   help='Image ID to tag or update', default='')
parser.add_argument('--update_version_tags', action='store_true',
                   help='Update version tags on an existing image with actual installed versions', default=False)
parser.add_argument('--jicofo_version', action='store',
                   help='Jicofo version for tag update', default='')
parser.add_argument('--jitsi_meet_version', action='store',
                   help='Jitsi Meet version for tag update', default='')
parser.add_argument('--prosody_version', action='store',
                   help='Prosody version for tag update', default='')
parser.add_argument('--get_image_details_by_id', action='store_true',
                   help='Get image details by image_id (use with --image_id)', default=False)

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
    found_images = get_oracle_image_list_by_search(args.type, version, [args.region], config, args.architecture)

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

elif args.get_shape_compatibility:
    shapes=['VM.Standard.E3.Flex', 'VM.Standard.E4.Flex', 'VM.Standard.E5.Flex', 'VM.Standard.E6.Flex', 'VM.GPU.A10.1','VM.GPU.A10.2', 'VM.GPU2.1']
    if not args.image_id:
        print("No image_id provided, exiting...")
        exit(2)
    else:
        found_image = get_oracle_image_by_id(args.image_id, args.region)
        print(found_image)
        # entries = get_image_shapes(found_image)
        # for e in entries:
        #     print(e)

elif args.add_shape_compatibility:
    shapes_by_arch={
        'x86_64': ['VM.Standard.E3.Flex', 'VM.Standard.E4.Flex', 'VM.Standard.E5.Flex', 'VM.Standard.E6.Flex', 'VM.GPU.A10.1','VM.GPU.A10.2', 'VM.GPU2.1'],
        'aarch64': ['VM.Standard.A1.Flex','VM.Standard.A2.Flex']
    }
    if not args.image_id:
        print("No image_id provided, exiting...")
        exit(2)
    else:
        found_image = get_oracle_image_by_id(args.image_id, args.region)
        if found_image:
            if found_image.defined_tags['jitsi'] and 'Arch' in found_image.defined_tags['jitsi']:
                arch = found_image.defined_tags['jitsi']['Arch']
            else:
                arch = 'x86_64'

            if arch in shapes_by_arch:
                if update_image_shapes(found_image, shapes_by_arch[arch]):
                    print('Updated compatible shapes for image {}'.format(found_image.display_name))
                else:
                    print('No shape compatibility updates needed for image {}'.format(found_image.display_name))

elif args.tag_production:
    if not args.image_id:
        print("No image_id provided, exiting...")
        exit(2)
    else:
        found_image = get_oracle_image_by_id(args.image_id, args.region)

        update_image_tags(found_image, {'production-image': 'true'})

elif args.update_version_tags:
    if not args.image_id:
        print("No image_id provided, exiting...")
        exit(2)

    found_image = get_oracle_image_by_id(args.image_id, args.region)
    if not found_image:
        print(f"Image not found: {args.image_id}")
        exit(3)

    # Build new version string
    signal_version = f"{args.jicofo_version}-{args.jitsi_meet_version}-{args.prosody_version}"

    # Build new image name with actual versions
    # Parse existing name to replace version components
    old_name = found_image.display_name
    # Name format: BuildSignal-{region}-{env}-{jicofo}-{meet}-{prosody}-{timestamp}
    parts = old_name.split('-')
    if len(parts) >= 7:
        # Reconstruct with actual versions (keep timestamp at end)
        parts[-4] = args.jicofo_version
        parts[-3] = args.jitsi_meet_version
        parts[-2] = args.prosody_version
        new_name = '-'.join(parts)
    else:
        new_name = old_name  # Keep original if parsing fails

    # Get the tag namespace to use
    tag_ns = args.tag_namespace

    # Update defined tags with actual versions
    new_defined_tags = {
        tag_ns: {
            'Version': signal_version,
            'Name': new_name
        }
    }

    print(f"Updating image {args.image_id}")
    print(f"  Old version tag: {found_image.defined_tags.get(tag_ns, {}).get('Version', 'N/A')}")
    print(f"  New version tag: {signal_version}")
    print(f"  Old name: {old_name}")
    print(f"  New name: {new_name}")

    # Update using OCI API
    compute = oci.core.ComputeClient(config)
    compute.base_client.set_region(args.region)

    update_details = {
        'display_name': new_name,
        'defined_tags': found_image.defined_tags,
        'freeform_tags': found_image.freeform_tags,
        'operating_system': found_image.operating_system,
        'operating_system_version': found_image.operating_system_version
    }

    # Merge new tags into existing defined_tags
    for ns in new_defined_tags:
        if ns not in update_details['defined_tags']:
            update_details['defined_tags'][ns] = {}
        update_details['defined_tags'][ns].update(new_defined_tags[ns])

    details = oci.core.models.UpdateImageDetails(**update_details)
    resp = compute.update_image(found_image.id, details)
    print(f"Image updated: {resp.data.display_name}")

elif args.get_image_details_by_id:
    if not args.image_id:
        print("No image_id provided, exiting...")
        exit(2)

    found_image = get_oracle_image_by_id(args.image_id, args.region)
    if not found_image:
        warning(f"Image not found: {args.image_id}")
        exit(1)

    # Convert to same format as search results
    image_data = image_data_from_image_obj(found_image, args.tag_namespace)
    print(json.dumps(image_data, default=date_time_converter))

else:
    # For Signal images, support searching by individual component versions
    search_version = version

    # Helper function for filtering Signal images with mixed 'latest' components
    def filter_signal_images_with_latest(jicofo, jitsi_meet, prosody):
        # Get all recent images and filter client-side
        all_images = get_oracle_image_list_by_search(args.type, 'latest', [args.region], config, args.architecture)

        matched_images = []
        for img in all_images:
            img_version = img.get('image_version', '')
            if not img_version:
                continue
            parts = img_version.split('-')
            if len(parts) >= 3:
                img_jicofo, img_meet, img_prosody = parts[0], parts[1], parts[2]
                # Check each component: match if specified version equals image's version OR if we want 'latest'
                jicofo_match = (jicofo == 'latest' or img_jicofo == jicofo)
                meet_match = (jitsi_meet == 'latest' or img_meet == jitsi_meet)
                prosody_match = (prosody == 'latest' or img_prosody == prosody)

                if jicofo_match and meet_match and prosody_match:
                    matched_images.append(img)

        # Output result and exit
        if len(matched_images) > 0:
            if args.image_details:
                print(json.dumps(matched_images[0], default=date_time_converter))
            else:
                print(matched_images[0]['image_id'])
        else:
            warning('No image found matching type {} with jicofo={}, jitsi_meet={}, prosody={} and arch {}'.format(
                args.type, jicofo, jitsi_meet, prosody, args.architecture))
            exit(1)
        exit(0)

    if args.type == 'Signal' and (args.jicofo_version or args.jitsi_meet_version or args.prosody_version):
        jicofo = args.jicofo_version or 'latest'
        jitsi_meet = args.jitsi_meet_version or 'latest'
        prosody = args.prosody_version or 'latest'

        # Check if any component is 'latest'
        has_latest = jicofo == 'latest' or jitsi_meet == 'latest' or prosody == 'latest'

        if jicofo == 'latest' and jitsi_meet == 'latest' and prosody == 'latest':
            # All are latest - just search for latest
            search_version = 'latest'
        elif has_latest:
            # Mixed: some specific, some 'latest' - filter client-side
            filter_signal_images_with_latest(jicofo, jitsi_meet, prosody)
        else:
            # All components are specific versions - use exact search
            search_version = f"{jicofo}-{jitsi_meet}-{prosody}"

    # Also handle when --version is passed directly with 'latest' or empty components (e.g., "1169-9017-latest" or "1169-9017-")
    elif args.type == 'Signal' and version and version != 'latest':
        # Check if version contains 'latest' or has empty components (trailing/double dashes)
        has_latest_or_empty = 'latest' in version or version.endswith('-') or '--' in version
        if has_latest_or_empty:
            # Parse the version string to extract components
            parts = version.split('-')
            if len(parts) >= 3:
                jicofo = parts[0] or 'latest'
                jitsi_meet = parts[1] or 'latest'
                prosody = parts[2] or 'latest'

                has_latest = jicofo == 'latest' or jitsi_meet == 'latest' or prosody == 'latest'
                if has_latest:
                    # Mixed: some specific, some 'latest' - filter client-side
                    filter_signal_images_with_latest(jicofo, jitsi_meet, prosody)
                # If no 'latest' components, fall through to normal search

    # new way, using search API instead of brute force dump of all images
    found_images = get_oracle_image_list_by_search(args.type, search_version, [args.region], config, args.architecture)

    if len(found_images) > 0:
        if args.image_details:
            print(json.dumps(found_images[0], default = date_time_converter))
        else:
            print(found_images[0]['image_id'])
    else:
        warning('No image found matching type {} and version {} and arch {}'.format(args.type, search_version, args.architecture))
        exit(1)
