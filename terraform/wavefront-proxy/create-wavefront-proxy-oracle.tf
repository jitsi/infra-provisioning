variable "environment" {}
variable "name" {}
variable "oracle_region" {}
variable "availability_domains" {
  type = list(string)
}
variable "role" {}
variable "git_branch" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "resource_name_root" {}
variable "load_balancer_shape" {}
variable "subnet_ocid" {}
variable "instance_pool_size" {}
variable "instance_pool_name" {}
variable "dns_name" {}
variable "dns_zone_name" {}
variable "dns_compartment_ocid" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "user" {}
variable "user_private_key_path" {}
variable "bastion_host" {}
variable "wavefront_proxy_postinstall_status_file" {}
variable "security_group_id" {}
variable "user_public_key_path" {}
variable "instance_config_name" {}
variable "image_ocid" {}
variable "memory_in_gbs" {}
variable "ocpus" {}
variable "shape" {}
variable "infra_configuration_repo" {}
variable "infra_customizations_repo" {}
variable "user_data_lib_path" {
  default = "terraform/lib"
}
variable "user_data_file" {
  default = "terraform/wavefront-proxy/user-data/postinstall-runner-oracle.sh"
}
variable load_balancer_shape_details_maximum_bandwidth_in_mbps {
  default = "100"
}
variable load_balancer_shape_details_minimum_bandwidth_in_mbps {
  default = "10"
}

locals {
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

resource "oci_load_balancer" "oci_load_balancer" {
  compartment_id = var.compartment_ocid
  display_name = "${var.resource_name_root}-LoadBalancer"
  shape = var.load_balancer_shape
  shape_details {
      maximum_bandwidth_in_mbps = var.load_balancer_shape_details_maximum_bandwidth_in_mbps
      minimum_bandwidth_in_mbps = var.load_balancer_shape_details_minimum_bandwidth_in_mbps
  }

  subnet_ids = [var.subnet_ocid]

  defined_tags = local.common_tags
  is_private = true
  network_security_group_ids = [var.security_group_id]
}

resource "oci_load_balancer_backend_set" "oci_load_balancer_bs" {
  load_balancer_id = oci_load_balancer.oci_load_balancer.id
  name = "WFProxyLBBS"
  policy = "ROUND_ROBIN"
  health_checker {
    protocol = "TCP"
    port = 2878
    retries = 3
  }
}

resource "oci_load_balancer_backend_set" "oci_load_balancer_bs_json" {
  load_balancer_id = oci_load_balancer.oci_load_balancer.id
  name = "WFProxyLBBSJson"
  policy = "ROUND_ROBIN"
  health_checker {
    protocol = "TCP"
    port = 2878
    retries = 3
  }
}

resource "oci_load_balancer_listener" "main_listener" {
  load_balancer_id = oci_load_balancer.oci_load_balancer.id
  name = "WFProxyListener"
  port = 2878
  default_backend_set_name = oci_load_balancer_backend_set.oci_load_balancer_bs.name
  protocol = "TCP"
}

resource "oci_load_balancer_listener" "json_listener" {
  load_balancer_id = oci_load_balancer.oci_load_balancer.id
  name = "WFProxyJSONListener"
  port = 3878
  default_backend_set_name = oci_load_balancer_backend_set.oci_load_balancer_bs_json.name
  protocol = "HTTP"
}
resource "oci_core_instance_configuration" "oci_instance_configuration" {
  lifecycle {
      create_before_destroy = true
  }

  compartment_id = var.compartment_ocid
  display_name = var.instance_config_name

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
        nsg_ids = [var.security_group_id]
      }

      source_details {
        source_type = "image"
        image_id = var.image_ocid
      }

      metadata = {
        user_data = base64encode(join("",[
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-header.sh"), # load the header
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-lib.sh"), # load the lib
          "\nINFRA_CONFIGURATION_REPO=${var.infra_configuration_repo}\nINFRA_CUSTOMIZATIONS_REPO=${var.infra_customizations_repo}\n", #repo variables
          file("${path.cwd}/${var.user_data_file}"), # load our customizations
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-footer.sh") # load the footer
        ]))
        ssh_authorized_keys = file(var.user_public_key_path)
      }

      freeform_tags = {
        configuration_repo = var.infra_configuration_repo
        customizations_repo = var.infra_customizations_repo
      }

      defined_tags = local.common_tags

    }
  }
}


resource "oci_core_instance_pool" "oci_instance_pool" {
  compartment_id = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.oci_instance_configuration.id
  display_name = var.instance_pool_name
  size = var.instance_pool_size

  dynamic "placement_configurations" {
    for_each = toset(var.availability_domains)
    content {
      primary_subnet_id = var.subnet_ocid
      availability_domain = placement_configurations.value
    }
  }

  load_balancers {
    load_balancer_id = oci_load_balancer.oci_load_balancer.id
    backend_set_name = oci_load_balancer_backend_set.oci_load_balancer_bs.name
    port = 2878
    vnic_selection = "PrimaryVnic"
  }

  load_balancers {
    load_balancer_id = oci_load_balancer.oci_load_balancer.id
    backend_set_name = oci_load_balancer_backend_set.oci_load_balancer_bs_json.name
    port = 2878
    vnic_selection = "PrimaryVnic"
  }

  defined_tags = local.common_tags
}

data "oci_core_instance_pool_instances" "oci_instance_pool_instances" {
  compartment_id = var.compartment_ocid
  instance_pool_id = oci_core_instance_pool.oci_instance_pool.id
  depends_on = [oci_core_instance_pool.oci_instance_pool]
}

data "oci_core_instance" "oci_instance_datasources" {
  count = var.instance_pool_size
  instance_id = lookup(data.oci_core_instance_pool_instances.oci_instance_pool_instances.instances[count.index], "id")
}

locals {
  private_ips = data.oci_core_instance.oci_instance_datasources.*.private_ip
  lb_ip = oci_load_balancer.oci_load_balancer.ip_address_details[0].ip_address
}

resource "oci_dns_rrset" "wfproxy_dns_record" {
  zone_name_or_id = var.dns_zone_name
  domain = var.dns_name
  rtype = "A"
  compartment_id = var.dns_compartment_ocid
  items {
    domain = var.dns_name
    rtype = "A"
    ttl = "60"
    rdata = oci_load_balancer.oci_load_balancer.ip_address_details[0].ip_address
   }
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

      bastion_host = var.bastion_host
      bastion_user = var.user
      bastion_private_key = file(var.user_private_key_path)
      script_path = "/home/${var.user}/script_%RAND%.sh"

      timeout = "10m"
    }
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}

resource "null_resource" "cloud_init_output" {
  count = var.instance_pool_size
  depends_on = [null_resource.verify_cloud_init]

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no -J ${var.user}@${var.bastion_host} ${var.user}@${element(local.private_ips, count.index)} 'echo hostname: $HOSTNAME, privateIp: ${element(local.private_ips, count.index)} - $(cloud-init status)' >> ${var.wavefront_proxy_postinstall_status_file}"
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}

output "private_ips" {
  value = local.private_ips
}

output "lb_ip" {
  value = local.lb_ip
}
