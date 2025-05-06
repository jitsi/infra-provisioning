variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "vcn_name" {}
variable "subnet_name" {}
variable "security_group_name" {}
variable "image_ocid" {}
variable "oracle_region" {}
variable "environment" {}
variable "shape" {}
variable "git_branch" {}
variable "name" {}
variable "shard_role" {}
variable "domain" {}
variable "jigasi_release_number" {}
variable "aws_cloud_name" {}
variable "instance_config_name" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "user_public_key_path" {}
variable "memory_in_gbs" {}
variable "ocpus" {}
variable "user_data_file" {
  default = "terraform/create-jigasi-instance-configuration/user-data/postinstall-runner-oracle.sh"
}
variable "user_data_lib_path" {
  default = "terraform/lib"
}
variable "infra_configuration_repo" {}
variable "infra_customizations_repo" {}


provider "oci" {
  region = var.oracle_region
  tenancy_ocid = var.tenancy_ocid
}

terraform {
  backend "s3" {
    skip_region_validation = true
    skip_credentials_validation = true
    skip_metadata_api_check = true
    force_path_style = true
  }
  required_providers {
      oci = {
          source  = "oracle/oci"
      }
  }
}

locals {
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.environment_type" = var.environment_type
    "${var.tag_namespace}.git_branch" = var.git_branch
    "${var.tag_namespace}.domain" = var.domain
    "${var.tag_namespace}.shard-role" = var.shard_role
    "${var.tag_namespace}.Name" = var.name
    "${var.tag_namespace}.aws_cloud_name" = var.aws_cloud_name
    "${var.tag_namespace}.jigasi_release_number" = var.jigasi_release_number
  }
}

data "oci_core_vcns" "vcns" {
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}

data "oci_core_subnets" "jigasi_subnets" {
  compartment_id = var.compartment_ocid
  display_name = var.subnet_name
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
}
data "oci_core_network_security_groups" "network_security_groups" {
  compartment_id = var.compartment_ocid
  display_name = var.security_group_name
}
resource "oci_core_instance_configuration" "oci_instance_configuration" {
  compartment_id = var.compartment_ocid
  display_name = var.instance_config_name

  lifecycle {
    create_before_destroy = true
  }

  defined_tags = local.common_tags

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id = var.compartment_ocid
      shape = var.shape

      shape_config {
        memory_in_gbs = var.memory_in_gbs
        ocpus = var.ocpus
      }

      create_vnic_details {
        assign_public_ip = false
        subnet_id = data.oci_core_subnets.jigasi_subnets.subnets[0].id
        nsg_ids = [
          data.oci_core_network_security_groups.network_security_groups.network_security_groups[0].id]
      }

      source_details {
        source_type = "image"
        image_id = var.image_ocid
      }

      metadata = {
        user_data = base64encode(join("",[
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-header.sh"), # load the header
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-lib.sh"), # load the lib
          "\nexport INFRA_CONFIGURATION_REPO=${var.infra_configuration_repo}\nexport INFRA_CUSTOMIZATIONS_REPO=${var.infra_customizations_repo}\n", #repo variables
          file("${path.cwd}/${var.user_data_file}"), # load our customizations
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-footer.sh") # load the footer
        ]))
        ssh_authorized_keys = file(var.user_public_key_path)
      }

      defined_tags = local.common_tags
      freeform_tags = {
        configuration_repo = var.infra_configuration_repo
        customizations_repo = var.infra_customizations_repo
        shape = var.shape
      }
    }
  }
}

