variable "name" {}
variable "resource_name_root" {}
variable "vcn_name" {}
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}

variable "environment" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "jitsi_tag_namespace" {}
variable "git_branch" {}
variable "role" {}
variable "grid_name" {}

variable "subnet_ocid" {}

variable "shape_x86" {}
variable "shape_arm" {}
variable "image_ocid_x86" {}
variable "image_ocid_arm" {}
variable "user_public_key_path" {}
variable "node_security_group_id" {}
variable "memory_in_gbs_x86" {}
variable "memory_in_gbs_arm" {}
variable "ocpus_x86" {}
variable "ocpus_arm" {}

variable "user_data_lib_path" {
  default = "terraform/lib"
}
variable "user_data_file" {
  default = "terraform/selenium-grid/user-data/postinstall-runner-oracle.sh"
}
variable "infra_configuration_repo" {}
variable "infra_customizations_repo" {}
variable "autoscaler_enabled" {
  default = "false"
}

locals {

  node_tags = {
    "${var.tag_namespace}.git_branch" = var.git_branch
    "${var.tag_namespace}.role" = var.role
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.shard-role" = var.role
    "${var.tag_namespace}.grid-role" = "node"
    "${var.tag_namespace}.grid" = var.grid_name
    "${var.tag_namespace}.Name" = var.name
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

resource "oci_core_instance_configuration" "oci_instance_configuration_node_arm" {
  lifecycle {
      create_before_destroy = true
  }

  compartment_id = var.compartment_ocid
  display_name = "${var.resource_name_root}-NodeARMInstanceConfiguration"

  defined_tags = local.node_tags

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id = var.compartment_ocid
      shape = var.shape_arm

      shape_config {
        memory_in_gbs = var.memory_in_gbs_arm
        ocpus = var.ocpus_arm
      }

      create_vnic_details {
        assign_public_ip = false
        subnet_id = var.subnet_ocid
        nsg_ids = [var.node_security_group_id]
      }

      source_details {
        source_type = "image"
        image_id = var.image_ocid_arm
      }

      metadata = {
        user_data = base64encode(join("",[
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-header.sh"), # load the header
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-lib.sh"), # load the lib
          "\nexport INFRA_CONFIGURATION_REPO=${var.infra_configuration_repo}\nexport INFRA_CUSTOMIZATIONS_REPO=${var.infra_customizations_repo}\nexport SELENIUM_GRID_AUTOSCALER_ENABLED=${var.autoscaler_enabled}\n", #repo variables
          file("${path.cwd}/${var.user_data_file}"), # load our customizations
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-footer.sh") # load the footer
        ]))
        ssh_authorized_keys = file(var.user_public_key_path)
      }

      defined_tags = local.node_tags
      freeform_tags = {
        configuration_repo = var.infra_configuration_repo
        customizations_repo = var.infra_customizations_repo
        shape = var.shape_arm
        arch = "aarch64"
        nomad = "true"
      }
    }
  }
}

resource "oci_core_instance_configuration" "oci_instance_configuration_node_x86" {
  lifecycle {
      create_before_destroy = true
  }

  compartment_id = var.compartment_ocid
  display_name = "${var.resource_name_root}-Nodex86InstanceConfiguration"

  defined_tags = local.node_tags

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id = var.compartment_ocid
      shape = var.shape_x86

      shape_config {
        memory_in_gbs = var.memory_in_gbs_x86
        ocpus = var.ocpus_x86
      }

      create_vnic_details {
        assign_public_ip = false
        subnet_id = var.subnet_ocid
        nsg_ids = [var.node_security_group_id]
      }

      source_details {
        source_type = "image"
        image_id = var.image_ocid_x86
      }

      metadata = {
        user_data = base64encode(join("",[
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-header.sh"), # load the header
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-lib.sh"), # load the lib
          "\nexport INFRA_CONFIGURATION_REPO=${var.infra_configuration_repo}\nexport INFRA_CUSTOMIZATIONS_REPO=${var.infra_customizations_repo}\nexport SELENIUM_GRID_AUTOSCALER_ENABLED=${var.autoscaler_enabled}\n", #repo variables
          file("${path.cwd}/${var.user_data_file}"), # load our customizations
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-footer.sh") # load the footer
        ]))
        ssh_authorized_keys = file(var.user_public_key_path)
      }

      defined_tags = local.node_tags
      freeform_tags = {
        configuration_repo = var.infra_configuration_repo
        customizations_repo = var.infra_customizations_repo
        shape = var.shape_x86
        arch = "amd64"
        nomad = "true"
      }
    }
  }
}

output "instance_configuration_id_arm" {
  value = oci_core_instance_configuration.oci_instance_configuration_node_arm.id
}

output "instance_configuration_id_x86" {
  value = oci_core_instance_configuration.oci_instance_configuration_node_x86.id
}
