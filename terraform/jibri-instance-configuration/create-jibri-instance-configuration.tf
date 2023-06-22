variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "oracle_region" {}
variable "instance_config_name" {}
variable "shape" {}
variable "vcn_name" {}
variable "subnet_name" {}
variable "image_ocid" {}

variable "tag_namespace" {}
variable "environment" {}
variable "environment_type" {}
variable "git_branch" {}
variable "domain" {}
variable "shard_role" {}
variable "jibri_release_number" {}
variable "aws_cloud_name" {}
variable "aws_auto_scale_group" {
  default = ""
}
variable "name" {}
variable "user_public_key_path" {}
variable "memory_in_gbs" {}
variable "ocpus" {}
variable "user_data_lib_path" {
  default = "terraform/lib"
}
variable "user_data_file" {
  default = "terraform/jibri-instance-configuration/user-data/postinstall-runner-oracle.sh"
}
variable "infra_configuration_repo" {}
variable "infra_customizations_repo" {}
variable "nomad_flag" {
  default = false
}



locals {
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.environment_type" = var.environment_type
    "${var.tag_namespace}.git_branch" = var.git_branch
    "${var.tag_namespace}.domain" = var.domain
    "${var.tag_namespace}.Name" = var.name
    "${var.tag_namespace}.shard-role" = var.shard_role
    "${var.tag_namespace}.jibri_release_number" = var.jibri_release_number
    "${var.tag_namespace}.aws_cloud_name" = var.aws_cloud_name
    "${var.tag_namespace}.aws_auto_scale_group" = var.aws_auto_scale_group
  }
}

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

data "oci_core_vcns" "vcns" {
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}

data "oci_core_subnets" "jibri_subnets" {
  compartment_id = var.compartment_ocid
  display_name = var.subnet_name
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
}

data "oci_core_network_security_groups" "network_security_groups" {
  compartment_id = var.compartment_ocid
  filter {
    name = "display_name"
    values = [ var.shard_role == "java-jibri" ? ".*-JibriCustomSecurityGroup" :  ".*-SipJibriCustomSecurityGroup"]
    regex = true
  }
}

resource "oci_core_instance_configuration" "oci_instance_configuration" {
  compartment_id = var.compartment_ocid
  display_name = var.instance_config_name

  lifecycle {
    prevent_destroy = true
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
        subnet_id = data.oci_core_subnets.jibri_subnets.subnets[0].id
        nsg_ids = [
          data.oci_core_network_security_groups.network_security_groups.network_security_groups[0].id]
        # disable auto-assignment of public IP for instance
        assign_public_ip = false
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
          "\nexport NOMAD_FLAG=${var.nomad_flag}\n", #nomad variable
          "\nfunction postinstall_jibri() {\n", # default postinstall
          file("${path.cwd}/../infra-configuration/ansible/roles/jibri-java/files/postinstall-jibri-oracle.sh"), # load the lib
          "\n}\n", # end default postinstall
          "\nfunction configure_jibri() {\n", # default reconfigure
          file("${path.cwd}/../infra-configuration/ansible/roles/jibri-java/files/configure-jibri-local-oracle.sh"), # load the lib
          "\n}\n", # end default reconfigure
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