variable "environment" {}
variable "name" {}
variable "oracle_region" {}
variable "availability_domains" {
  type = list(string)
}
variable "role" {}
variable "pool_type" {}
variable "git_branch" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "instance_config_name" {}
variable "image_ocid" {}
variable "user_public_key_path" {}
variable "shape" {}
variable "memory_in_gbs" {}
variable "ocpus" {}
variable "pool_subnet_ocid" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "user" {}

variable "user_data_lib_path" {
  default = "terraform/lib"
}
variable "user_data_file" {
  default = "terraform/nomad-whisper/user-data/postinstall-runner-nomad-whisper-oracle.sh"
}
variable "infra_configuration_repo" {}
variable "infra_customizations_repo" {}
variable "disk_in_gbs" {}

locals {
  common_freeform_tags = {
    "pool_type" = var.pool_type
    shape = var.shape
  }
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.environment_type" = var.environment_type
    "${var.tag_namespace}.git_branch" = var.git_branch
    "${var.tag_namespace}.shard-role" = var.role
    "${var.tag_namespace}.role" = var.role
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

data "oci_core_network_security_groups" "nomad_network_security_groups" {
  compartment_id = var.compartment_ocid
  filter {
    name = "display_name"
    values = ["${var.environment}-${var.oracle_region}-nomad-pool-shared-SecurityGroup"]
  }
}

resource "oci_core_instance_configuration" "oci_instance_configuration" {
  lifecycle {
      create_before_destroy = true
  }

  compartment_id = var.compartment_ocid
  display_name = var.instance_config_name

  freeform_tags = local.common_freeform_tags
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
        subnet_id = var.pool_subnet_ocid
        nsg_ids = data.oci_core_network_security_groups.nomad_network_security_groups.network_security_groups[*].id
      }

      source_details {
        source_type = "image"
        image_id = var.image_ocid
        boot_volume_size_in_gbs = var.disk_in_gbs
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

      freeform_tags = local.common_freeform_tags
      defined_tags = local.common_tags
    }
  }
}

