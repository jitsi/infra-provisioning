variable "environment" {}
variable "name" {}
variable "oracle_region" {}
variable "availability_domains" {
  type = list(string)
}
variable "role" {
  default = "emqx"
}
variable "pool_type" {
  default = "emqx"
}
variable "git_branch" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "resource_name_root" {}
variable "instance_config_name" {}
variable "image_ocid" {}
variable "user_public_key_path" {}
variable "security_group_id" {}
variable "shape" {}
variable "memory_in_gbs" {}
variable "ocpus" {}
variable "pool_subnet_ocid" {}
variable "public_subnet_ocid" {}
variable "instance_pool_size" {}
variable "instance_pool_name" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "user" {}
variable "user_private_key_path" {}
variable "vcn_name" {}

variable "postinstall_status_file" {}
variable "user_data_lib_path" {
  default = "terraform/lib"
}
variable "user_data_file" {
  default = "terraform/emqx-instance-pool/user-data/postinstall-runner-oracle.sh"
}
variable "infra_configuration_repo" {}
variable "infra_customizations_repo" {}
variable "disk_in_gbs" {}
variable "volumes_enabled" {
  default = true
}
variable "load_balancer_id" {
  type = string
  default = ""
  description = "Optional: OCI Load Balancer ID to attach instance pools to"
}
variable "lb_backend_set_name" {
  type = string
  default = ""
  description = "Optional: Backend set name to attach instances to (e.g., mqtt backend set)"
}
variable "lb_backend_port" {
  type = number
  default = 8080
  description = "Port that load balancer will use for health checks (HAProxy admin port)"
}

locals {
  common_freeform_tags = {
    "pool_type" = var.pool_type
    shape = var.shape
  }
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.environment_type" = var.environment_type
    "${var.tag_namespace}.git_branch" = var.git_branch
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

# Create N instance configurations, one per pool member, each with its own group-index
resource "oci_core_instance_configuration" "oci_instance_configuration" {
  count = var.instance_pool_size

  lifecycle {
      create_before_destroy = true
  }

  compartment_id = var.compartment_ocid
  display_name = "${var.instance_config_name}-${count.index}"

  freeform_tags = merge(local.common_freeform_tags, {
    "group-index" = "${count.index}"
  })
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
        subnet_id = var.pool_subnet_ocid
        nsg_ids = [var.security_group_id]
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
          "\nexport INFRA_CONFIGURATION_REPO=${var.infra_configuration_repo}\nexport INFRA_CUSTOMIZATIONS_REPO=${var.infra_customizations_repo}\nexport VOLUMES_ENABLED=${var.volumes_enabled}\n", #repo variables
          file("${path.cwd}/${var.user_data_file}"), # load our customizations
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-footer.sh") # load the footer
        ]))
        ssh_authorized_keys = file(var.user_public_key_path)
      }

      freeform_tags = merge(local.common_freeform_tags, {
        "group-index" = "${count.index}"
      })
      defined_tags = local.common_tags
    }
  }
}

data "oci_core_vcns" "vcns" {
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}

# Create N instance pools of size 1, each using its corresponding instance configuration
resource "oci_core_instance_pool" "oci_instance_pool" {
  count = var.instance_pool_size

  compartment_id = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.oci_instance_configuration[count.index].id
  display_name = "${var.instance_pool_name}-${count.index}"
  size = 1

  dynamic "placement_configurations" {
    for_each = toset([element(var.availability_domains, count.index % length(var.availability_domains))])
    content {
      primary_subnet_id = var.pool_subnet_ocid
      availability_domain = placement_configurations.value
    }
  }

  # Optionally attach to load balancer backend set
  dynamic "load_balancers" {
    for_each = var.load_balancer_id != "" ? [1] : []
    content {
      load_balancer_id = var.load_balancer_id
      backend_set_name = var.lb_backend_set_name
      port             = var.lb_backend_port
      vnic_selection   = "PrimaryVnic"
    }
  }

  freeform_tags = merge(local.common_freeform_tags, {
    "group-index" = "${count.index}"
  })
  defined_tags = local.common_tags
}

data "oci_core_instance_pool_instances" "oci_instance_pool_instances" {
  count = var.instance_pool_size

  compartment_id = var.compartment_ocid
  instance_pool_id = oci_core_instance_pool.oci_instance_pool[count.index].id
  depends_on = [oci_core_instance_pool.oci_instance_pool]
}

data "oci_core_instance" "oci_instance_datasources" {
  count = var.instance_pool_size
  instance_id = lookup(data.oci_core_instance_pool_instances.oci_instance_pool_instances[count.index].instances[0], "id")
}

locals {
  private_ips = data.oci_core_instance.oci_instance_datasources.*.private_ip
}

resource "null_resource" "verify_cloud_init" {
  count = var.instance_pool_size
  depends_on = [data.oci_core_instance.oci_instance_datasources]

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
      type = "ssh"
      host = element(local.private_ips, count.index)
      user = var.user
      private_key = file(var.user_private_key_path)

      script_path = "/home/${var.user}/script_%RAND%.sh"

      timeout = "10m"
    }
  }
}

resource "null_resource" "cloud_init_output" {
  count = var.instance_pool_size
  depends_on = [null_resource.verify_cloud_init]

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no ${var.user}@${element(local.private_ips, count.index)} 'echo hostname: $HOSTNAME, privateIp: ${element(local.private_ips, count.index)} - $(cloud-init status)' >> ${var.postinstall_status_file}"
  }
}


output "private_ips" {
  value = local.private_ips
}

output "instance_pool_ids" {
  value = oci_core_instance_pool.oci_instance_pool.*.id
}
