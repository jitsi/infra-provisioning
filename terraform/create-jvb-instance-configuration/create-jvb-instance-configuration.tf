variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "subnet_ocid" {}
variable "private_subnet_ocid" {}
variable "security_group_ocid" {}
variable "image_ocid" {}
variable "oracle_region" {}
variable "environment" {}
variable "shape" {}
variable "git_branch" {}
variable "name" {}
variable "shard" {}
variable "shard_role" {}
variable "domain" {}
variable "xmpp_host_public_ip_address" {}
variable "release_number" {}
variable "jvb_release_number" {}
variable "jvb_pool_mode" {}
variable "aws_cloud_name" {}
variable "instance_config_name" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "user_public_key_path" {}
variable "secondary_vnic_name" {}
variable "use_eip" {}
variable "autoscaler_sidecar_jvb_flag" {}
variable "memory_in_gbs" {}
variable "ocpus" {}
variable "user_data_file" {
  default = "terraform/create-jvb-instance-configuration/user-data/postinstall-runner-oracle.sh"
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
    "${var.tag_namespace}.shard" = var.shard
    "${var.tag_namespace}.shard-role" = var.shard_role
    "${var.tag_namespace}.Name" = var.name
    "${var.tag_namespace}.xmpp_host_public_ip_address" = var.xmpp_host_public_ip_address
    "${var.tag_namespace}.aws_cloud_name" = var.aws_cloud_name
    "${var.tag_namespace}.release_number" = var.release_number
    "${var.tag_namespace}.jvb_release_number" = var.jvb_release_number
    "${var.tag_namespace}.jvb_pool_mode" = var.jvb_pool_mode
    "${var.tag_namespace}.use_eip" = var.use_eip
    "${var.tag_namespace}.autoscaler_sidecar_jvb_flag" = var.autoscaler_sidecar_jvb_flag
  }
}

resource "oci_core_instance_configuration" "oci_instance_configuration" {
  count = var.use_eip ? 0:1
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
        subnet_id = var.subnet_ocid
        nsg_ids = [
          var.security_group_ocid]
      }

      source_details {
        source_type = "image"
        image_id = var.image_ocid
      }

      metadata = {
        user_data = base64encode(join("",[
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-header.sh"), # load the header
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-lib.sh"), # load the lib
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-eip-lib.sh"), # load the EIP lib
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
      }
    }
  }
}

resource "oci_core_instance_configuration" "oci_instance_configuration_use_eip" {
  count = var.use_eip ? 1:0
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
        subnet_id = var.subnet_ocid
        nsg_ids = [
          var.security_group_ocid]
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
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-eip-lib.sh"), # load the EIP lib
          file("${path.cwd}/${var.user_data_file}"), # load our customizations
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-footer.sh") # load the footer
        ]))
        ssh_authorized_keys = file(var.user_public_key_path)
      }

      defined_tags = local.common_tags
    }
    secondary_vnics {
      display_name = var.secondary_vnic_name

      create_vnic_details {
        assign_public_ip = false
        display_name = var.secondary_vnic_name
        subnet_id = var.private_subnet_ocid
        nsg_ids = [
          var.security_group_ocid]

        defined_tags = local.common_tags
      }
    }
  }
}




