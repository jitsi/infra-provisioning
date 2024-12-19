variable "name" {}
variable "resource_name_root" {}
variable "vcn_name" {}
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "availability_domains" {
  type = list(string)
}
variable "instance_pool_size_x86" {}
variable "instance_pool_size_arm" {}

variable "user" {}
variable "user_private_key_path" {}
variable "postinstall_status_file" {}

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
          "\nexport INFRA_CONFIGURATION_REPO=${var.infra_configuration_repo}\nexport INFRA_CUSTOMIZATIONS_REPO=${var.infra_customizations_repo}\n", #repo variables
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
          "\nexport INFRA_CONFIGURATION_REPO=${var.infra_configuration_repo}\nexport INFRA_CUSTOMIZATIONS_REPO=${var.infra_customizations_repo}\n", #repo variables
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

resource "oci_core_instance_pool" "oci_instance_pool_node_arm" {
  compartment_id = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.oci_instance_configuration_node_arm.id
  display_name = "${var.grid_name} Grid Arm Nodes"
  size = var.instance_pool_size_arm

  dynamic "placement_configurations" {
    for_each = toset(var.availability_domains)
    content {
      primary_subnet_id = var.subnet_ocid
      availability_domain = placement_configurations.value
    }
  }

  defined_tags = local.node_tags
  freeform_tags = {
    arch = "aarch64"
  }

}

resource "oci_core_instance_pool" "oci_instance_pool_node_x86" {
  compartment_id = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.oci_instance_configuration_node_x86.id
  display_name = "${var.grid_name} Grid x86 Nodes"
  size = var.instance_pool_size_x86

  dynamic "placement_configurations" {
    for_each = toset(var.availability_domains)
    content {
      primary_subnet_id = var.subnet_ocid
      availability_domain = placement_configurations.value
    }
  }

  defined_tags = local.node_tags
  freeform_tags = {
    arch = "amd64"
  }

}

data "oci_core_instance_pool_instances" "oci_instance_pool_instances_node_arm" {
  compartment_id = var.compartment_ocid
  instance_pool_id = oci_core_instance_pool.oci_instance_pool_node_arm.id
  depends_on = [oci_core_instance_pool.oci_instance_pool_node_arm]
}

data "oci_core_instance_pool_instances" "oci_instance_pool_instances_node_x86" {
  compartment_id = var.compartment_ocid
  instance_pool_id = oci_core_instance_pool.oci_instance_pool_node_x86.id
  depends_on = [oci_core_instance_pool.oci_instance_pool_node_x86]
}


data "oci_core_instance" "oci_instance_datasources_node_arm" {
  depends_on = [oci_core_instance_pool.oci_instance_pool_node_arm]
  count = var.instance_pool_size_arm
  instance_id = lookup(data.oci_core_instance_pool_instances.oci_instance_pool_instances_node_arm.instances[count.index], "id")
}

data "oci_core_instance" "oci_instance_datasources_node_x86" {
  depends_on = [oci_core_instance_pool.oci_instance_pool_node_x86]
  count = var.instance_pool_size_x86
  instance_id = lookup(data.oci_core_instance_pool_instances.oci_instance_pool_instances_node_x86.instances[count.index], "id")
}

locals {
  node_x86_private_ips = data.oci_core_instance.oci_instance_datasources_node_x86.*.private_ip
  node_arm_private_ips = data.oci_core_instance.oci_instance_datasources_node_arm.*.private_ip
}


resource "null_resource" "verify_cloud_init_node_arm" {
  count = var.instance_pool_size_arm
  depends_on = [data.oci_core_instance.oci_instance_datasources_node_arm]

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
      type = "ssh"
      host = element(local.node_arm_private_ips, count.index)
      user = var.user
      private_key = file(var.user_private_key_path)

      script_path = "/home/${var.user}/script_%RAND%.sh"

      timeout = "10m"
    }
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}

resource "null_resource" "verify_cloud_init_node_x86" {
  count = var.instance_pool_size_x86
  depends_on = [data.oci_core_instance.oci_instance_datasources_node_x86]

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
      type = "ssh"
      host = element(local.node_x86_private_ips, count.index)
      user = var.user
      private_key = file(var.user_private_key_path)

      script_path = "/home/${var.user}/script_%RAND%.sh"

      timeout = "10m"
    }
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}

output "node_private_ips_arm" {
  value = local.node_arm_private_ips
}

output "node_private_ips_x86" {
  value = local.node_x86_private_ips
}
