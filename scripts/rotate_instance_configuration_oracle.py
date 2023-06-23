#!/usr/bin/env python
import argparse
import base64
import io
import functools

import oci
from oci.core import ComputeManagementClient
from oci.core.models import CreateInstanceConfigurationDetails, \
    InstanceConfigurationLaunchInstanceDetails, \
    InstanceConfigurationLaunchInstanceShapeConfigDetails, \
    InstanceConfigurationInstanceSourceViaImageDetails, \
    ComputeInstanceDetails, \
    UpdateInstancePoolDetails

parser = argparse.ArgumentParser(description='Create a new instance configuration and assigned it to the instance pool')

parser.add_argument('--region', action='store', help='Oracle Region', default=False)

parser.add_argument('--image_id', action='store', help='Image OCID',
                    default=False)

parser.add_argument('--jibri_release_number', action='store', help='Jibri release number',
                    default=False)

parser.add_argument('--display_name', action='store', help='Config display name',
                    default=False)

parser.add_argument('--jvb_release_number', action='store', help='JVB release number',
                    default=False)

parser.add_argument('--jigasi_release_number', action='store', help='Jigasi release number',
                    default=False)

parser.add_argument('--release_number', action='store', help='release number',
                    default=False)

parser.add_argument('--git_branch', action='store', help='Jibri git branch',
                    default=False)

parser.add_argument('--aws_auto_scale_group', action='store', help='Jibri AWS autoscale group',
                    default=None)

parser.add_argument('--instance_pool_id', action='store', help='Instance pool id',
                    default=False)

parser.add_argument('--instance_configuration_id', action='store', help='Instance configuration id',
                    default=False)

parser.add_argument('--tag_namespace', action='store', help='Tag namespace',
                    default=False)

parser.add_argument('--user_public_key_path', action='store', help='User public key',
                    default=False)

parser.add_argument('--metadata_eip', action='store_true', help='Include EIP lib in metadata',
                    default=False)

parser.add_argument('--metadata_path', action='store', help='Metadata to be used by Cloud-Init to run',
                    default=False)

parser.add_argument('--metadata_lib_path', action='store', help='Metadata library path to be used by Cloud-Init to run',
                    default=False)

parser.add_argument('--metadata_extra', action='store', help='Metadata string to append to the cloud init scripts',
                    default=False)

parser.add_argument('--custom_autoscaler', action='store_true',
                    help='Used to rotate instance configuration for the custom autoscaler',
                    default=False)

parser.add_argument('--shape', action='store', help='Instance shape',
                    default=False)

parser.add_argument('--ocpus', action='store', help='Instance CPUS',
                    default=False)

parser.add_argument('--memory', action='store', help='Instance Memory in GBs',
                    default=False)

parser.add_argument('--infra_configuration_repo', action='store', help='Repo for instance configuration',
                    default=False)

parser.add_argument('--infra_customizations_repo', action='store', help='Repo for instance customizations',
                    default=False)

args = parser.parse_args()

config = oci.config.from_file()
compute_management_client = ComputeManagementClient(config)
compute_management_client.base_client.set_region(args.region)

if args.custom_autoscaler:
    existing_instance_configuration_details = compute_management_client.get_instance_configuration(
        args.instance_configuration_id)
else:
    existing_instance_pool_details = compute_management_client.get_instance_pool(args.instance_pool_id)
    existing_instance_configuration_details = compute_management_client.get_instance_configuration(
        existing_instance_pool_details.data.instance_configuration_id)

if not args.tag_namespace in existing_instance_configuration_details.data.defined_tags:
    existing_instance_configuration_details.data.defined_tags[args.tag_namespace] = {}

if args.jigasi_release_number:
    existing_instance_configuration_details.data.defined_tags[args.tag_namespace][
        'jigasi_release_number'] = args.jigasi_release_number

if args.jibri_release_number:
    existing_instance_configuration_details.data.defined_tags[args.tag_namespace][
        'jibri_release_number'] = args.jibri_release_number

if args.jvb_release_number:
    existing_instance_configuration_details.data.defined_tags[args.tag_namespace][
        'jvb_release_number'] = args.jvb_release_number

if args.release_number:
    existing_instance_configuration_details.data.defined_tags[args.tag_namespace][
        'release_number'] = args.release_number

existing_instance_configuration_details.data.defined_tags[args.tag_namespace][
    'git_branch'] = args.git_branch
if args.aws_auto_scale_group:
    existing_instance_configuration_details.data.defined_tags[args.tag_namespace][
        'aws_auto_scale_group'] = args.aws_auto_scale_group
else:
    existing_instance_configuration_details.data.defined_tags[args.tag_namespace][
        'aws_auto_scale_group'] = ''

with io.open(args.metadata_path, "rb") as metadata_file:
    metadata_file_contents = metadata_file.read()

if args.metadata_lib_path:
    with io.open(args.metadata_lib_path+"/postinstall-header.sh", "rb") as mf:
        metadata_header_contents = mf.read()

    with io.open(args.metadata_lib_path+"/postinstall-lib.sh", "rb") as mf:
        metadata_lib_file_contents = mf.read()

    with io.open(args.metadata_lib_path+"/postinstall-eip-lib.sh", "rb") as mf:
        metadata_eip_lib_file_contents = mf.read()

    with io.open(args.metadata_lib_path+"/postinstall-footer.sh", "rb") as mf:
        metadata_footer_contents = mf.read()

metadata_files=[metadata_header_contents,metadata_lib_file_contents]
#only append eip library if flag is set (JVB and coturn)
if args.metadata_eip:
    metadata_files.append(metadata_eip_lib_file_contents)

if args.infra_configuration_repo and args.infra_customizations_repo:
    existing_instance_configuration_details.data.freeform_tags['configuration_repo'] = args.infra_configuration_repo
    existing_instance_configuration_details.data.freeform_tags['customizations_repo'] = args.infra_customizations_repo
    metadata_files.append(bytes("\nexport INFRA_CONFIGURATION_REPO=\"{}\"\nexport INFRA_CUSTOMIZATIONS_REPO=\"{}\"\n".format(args.infra_configuration_repo,args.infra_customizations_repo),"utf8"))

if args.metadata_extras:
    metadata_files.append(bytes("\n{}\n".format(args.metadata_extras),"utf8"))

metadata_files.extend([metadata_file_contents,metadata_footer_contents])

encoded_user_data = base64.b64encode(functools.reduce(lambda a,b: a+b, metadata_files))

with io.open(args.user_public_key_path, "r") as user_public_key_file:
    user_public_key = user_public_key_file.read()

shape = existing_instance_configuration_details.data.instance_details.launch_details.shape
if args.shape:
    shape = args.shape

shape_config = existing_instance_configuration_details.data.instance_details.launch_details.shape_config
ocpus=None
memory_in_gbs=None

if shape_config:
    ocpus = shape_config.ocpus
    memory_in_gbs = shape_config.memory_in_gbs

if args.ocpus:
    ocpus = int(args.ocpus)
if args.memory:
    memory_in_gbs=int(args.memory)

if memory_in_gbs and ocpus:
    shape_config=InstanceConfigurationLaunchInstanceShapeConfigDetails(memory_in_gbs=memory_in_gbs, ocpus=ocpus)

if args.display_name:
    display_name = args.display_name
else:
    display_name = existing_instance_configuration_details.data.display_name

freeform_tags = existing_instance_configuration_details.data.freeform_tags
freeform_tags['shape'] = shape

secondary_vnics = []
if existing_instance_configuration_details.data.instance_details.secondary_vnics:
    secondary_vnics = existing_instance_configuration_details.data.instance_details.secondary_vnics

launch_details = InstanceConfigurationLaunchInstanceDetails(
    compartment_id=existing_instance_configuration_details.data.compartment_id,
    shape=shape,
    shape_config=shape_config,
    source_details=InstanceConfigurationInstanceSourceViaImageDetails(
        image_id=args.image_id
    ),
    metadata=dict(
        ssh_authorized_keys=user_public_key,
        user_data=encoded_user_data.decode('utf-8')
    ),
    defined_tags=existing_instance_configuration_details.data.defined_tags,
    freeform_tags=freeform_tags,
    create_vnic_details=existing_instance_configuration_details.data.instance_details.launch_details.create_vnic_details
)

instance_details = ComputeInstanceDetails(
    launch_details=launch_details,
    secondary_vnics=secondary_vnics
)

instance_config_details = CreateInstanceConfigurationDetails(
    display_name=display_name,
    compartment_id=existing_instance_configuration_details.data.compartment_id,
    instance_details=instance_details,
    defined_tags=existing_instance_configuration_details.data.defined_tags,
    freeform_tags=existing_instance_configuration_details.data.freeform_tags
)

new_instance_configuration_details = compute_management_client.create_instance_configuration(instance_config_details)

if not args.custom_autoscaler:
    instance_pool_details = UpdateInstancePoolDetails(
        defined_tags=existing_instance_configuration_details.data.defined_tags,
        freeform_tags=existing_instance_configuration_details.data.freeform_tags,
        instance_configuration_id=new_instance_configuration_details.data.id
    )

    updated_instance_pool = compute_management_client.update_instance_pool(args.instance_pool_id, instance_pool_details)

    deleted_old_instance_configuration = compute_management_client.delete_instance_configuration(
        existing_instance_configuration_details.data.id)

print(new_instance_configuration_details.data.id)
