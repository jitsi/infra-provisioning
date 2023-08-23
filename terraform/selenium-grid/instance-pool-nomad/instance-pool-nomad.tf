variable "name" {}
variable "resource_name_root" {}
variable "vcn_name" {}
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "availability_domains" {
  type = list(string)
}
variable "instance_pool_size" {}

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
variable "load_balancer_id" {}
variable "load_balancer_bs_name" {}

variable "subnet_ocid" {}

variable "shape" {}
variable "image_ocid" {}
variable "user_public_key_path" {}
variable "node_security_group_id" {}
variable "memory_in_gbs" {}
variable "ocpus" {}

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

resource "oci_core_instance_configuration" "oci_instance_configuration_node" {
  lifecycle {
      create_before_destroy = true
  }

  compartment_id = var.compartment_ocid
  display_name = "${var.resource_name_root}-NodeInstanceConfiguration"

  defined_tags = local.node_tags

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
        nsg_ids = [var.node_security_group_id]
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

      defined_tags = local.node_tags
      freeform_tags = {
        configuration_repo = var.infra_configuration_repo
        customizations_repo = var.infra_customizations_repo
        shape = var.shape
        nomad = "true"
      }
    }
  }
}

resource "oci_core_instance_pool" "oci_instance_pool_node" {
  compartment_id = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.oci_instance_configuration_node.id
  display_name = "${var.grid_name} Grid Nodes"
  size = var.instance_pool_size

  dynamic "placement_configurations" {
    for_each = toset(var.availability_domains)
    content {
      primary_subnet_id = var.subnet_ocid
      availability_domain = placement_configurations.value
    }
  }

  defined_tags = local.node_tags

}

data "oci_core_instance_pool_instances" "oci_instance_pool_instances_node" {
  compartment_id = var.compartment_ocid
  instance_pool_id = oci_core_instance_pool.oci_instance_pool_node.id
  depends_on = [oci_core_instance_pool.oci_instance_pool_node]
}

data "oci_core_instance" "oci_instance_datasources_node" {
  depends_on = [oci_core_instance_pool.oci_instance_pool_node]
  count = var.instance_pool_size
  instance_id = lookup(data.oci_core_instance_pool_instances.oci_instance_pool_instances_node.instances[count.index], "id")
}

locals {
  node_private_ips = data.oci_core_instance.oci_instance_datasources_node.*.private_ip
}

resource "null_resource" "verify_cloud_init_node" {
  count = var.instance_pool_size
  depends_on = [data.oci_core_instance.oci_instance_datasources_node]

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
      type = "ssh"
      host = element(local.node_private_ips, count.index)
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

output "node_private_ips" {
  value = local.node_private_ips
}
