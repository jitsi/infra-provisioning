variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "oracle_region" {}
variable "instance_config_name" {}
variable "shape" {}
variable "memory_in_gbs" {}
variable "ocpus" {}
variable "public_subnet_ocid" {}
variable "private_subnet_ocid" {}
variable "secondary_vnic_name" {}
variable "image_ocid" {}
variable "instance_pool_size" {}
variable "instance_pool_name" {}
variable "availability_domains" {
  type = list(string)
}
variable "tag_namespace" {}
variable "environment" {}
variable "environment_type" {}
variable "git_branch" {}
variable "domain" {}
variable "shard_role" {}
variable "name" {}
variable "user_public_key_path" {}
variable "user_private_key_path" {}
variable "auto_scaling_config_name" {}
variable "scale_out_rule_name" {}
variable "scale_in_rule_name" {}
variable "policy_name" {}
variable "vcn_name" {}
variable "resource_name_root" {}
variable "user" {}
variable "coturns_postinstall_status_file" {}
variable "user_data_file" {
  default = "terraform/create-coturn-stack/user-data/postinstall-runner-oracle.sh"
}
variable "user_data_lib_path" {
  default = "terraform/lib"
}
variable "infra_configuration_repo" {}
variable "infra_customizations_repo" {}

locals {
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.environment_type" = var.environment_type
    "${var.tag_namespace}.git_branch" = var.git_branch
    "${var.tag_namespace}.domain" = var.domain
    "${var.tag_namespace}.Name" = var.name
    "${var.tag_namespace}.shard-role" = var.shard_role
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

// ============COTURN NETWORK SECURITY GROUP ============

data "oci_core_vcns" "vcns" {
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}

resource "oci_core_network_security_group" "coturn_network_security_group" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-CoturnSecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "coturn_network_security_group_security_rule_1" {
  network_security_group_id = oci_core_network_security_group.coturn_network_security_group.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

resource "oci_core_network_security_group_security_rule" "public_network_security_group_security_rule_2" {
  network_security_group_id = oci_core_network_security_group.coturn_network_security_group.id
  //tcp
  protocol = "6"
  direction = "INGRESS"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "coturn_network_security_group_security_rule_3" {
  network_security_group_id = oci_core_network_security_group.coturn_network_security_group.id
  //tcp
  protocol = "6"
  direction = "INGRESS"
  source = "0.0.0.0/0"
  stateless = false

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "coturn_network_security_group_security_rule_4" {
  network_security_group_id = oci_core_network_security_group.coturn_network_security_group.id
  //udp
  protocol = "17"
  direction = "INGRESS"
  source = "0.0.0.0/0"
  stateless = false

  udp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_nomad_tcp" {
  network_security_group_id = oci_core_network_security_group.coturn_network_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "10.0.0.0/8"
  stateless = false

  tcp_options {
    destination_port_range {
      min = 4646
      max = 4647
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_consul_serf_tcp" {
  network_security_group_id = oci_core_network_security_group.coturn_network_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 8301
      min = 8301
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_consul_serf_udp" {
  network_security_group_id = oci_core_network_security_group.coturn_network_security_group.id
  direction = "INGRESS"
  protocol = "17"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  udp_options {
    destination_port_range {
      min = 8301
      max = 8301
    }
  }
}


// ============ COTURN INSTANCE POOL ============

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
        subnet_id = var.public_subnet_ocid
        nsg_ids = [
          oci_core_network_security_group.coturn_network_security_group.id]
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
    secondary_vnics {
      display_name = var.secondary_vnic_name

      create_vnic_details {
        assign_public_ip = false
        display_name = var.secondary_vnic_name
        subnet_id = var.private_subnet_ocid
        nsg_ids = [
          oci_core_network_security_group.coturn_network_security_group.id]

        defined_tags = local.common_tags
      }
    }
  }
}

resource "oci_core_instance_pool" "oci_instance_pool_1_ad" {
  size = var.instance_pool_size
  compartment_id = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.oci_instance_configuration.id
  display_name = var.instance_pool_name
  count = length(var.availability_domains) == 1 ? 1:0

  lifecycle {
    prevent_destroy = true
  }

  placement_configurations {
    primary_subnet_id = var.public_subnet_ocid
    secondary_vnic_subnets {
      display_name = var.secondary_vnic_name
      subnet_id = var.private_subnet_ocid
    }
    availability_domain = var.availability_domains[0]
  }

  defined_tags = local.common_tags
}

resource "oci_core_instance_pool" "oci_instance_pool_2_ad" {
  size = var.instance_pool_size
  compartment_id = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.oci_instance_configuration.id
  display_name = var.instance_pool_name
  count = length(var.availability_domains) == 2 ? 1:0

  lifecycle {
    prevent_destroy = true
  }

  placement_configurations {
    primary_subnet_id = var.public_subnet_ocid
    secondary_vnic_subnets {
      display_name = var.secondary_vnic_name
      subnet_id = var.private_subnet_ocid
    }
    availability_domain = var.availability_domains[0]
  }

  placement_configurations {
    primary_subnet_id = var.public_subnet_ocid
    secondary_vnic_subnets {
      display_name = var.secondary_vnic_name
      subnet_id = var.private_subnet_ocid
    }
    availability_domain = var.availability_domains[1 % length(var.availability_domains)]
  }

  defined_tags = local.common_tags
}

resource "oci_core_instance_pool" "oci_instance_pool_3_ad" {
  size = var.instance_pool_size
  compartment_id = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.oci_instance_configuration.id
  display_name = var.instance_pool_name
  count = length(var.availability_domains) == 3 ? 1:0

  lifecycle {
    prevent_destroy = true
  }

  placement_configurations {
    primary_subnet_id = var.public_subnet_ocid
    secondary_vnic_subnets {
      display_name = var.secondary_vnic_name
      subnet_id = var.private_subnet_ocid
    }
    availability_domain = var.availability_domains[0]
  }
  placement_configurations {
    primary_subnet_id = var.public_subnet_ocid
    secondary_vnic_subnets {
      display_name = var.secondary_vnic_name
      subnet_id = var.private_subnet_ocid
    }
    availability_domain = var.availability_domains[1 % length(var.availability_domains)]
  }
  placement_configurations {
    primary_subnet_id = var.public_subnet_ocid
    secondary_vnic_subnets {
      display_name = var.secondary_vnic_name
      subnet_id = var.private_subnet_ocid
    }
    availability_domain = var.availability_domains[2 % length(var.availability_domains)]
  }

  defined_tags = local.common_tags
}

resource "oci_autoscaling_auto_scaling_configuration" "oci_auto_scaling_configuration" {
  compartment_id = var.compartment_ocid
  is_enabled = "true"
  display_name = var.auto_scaling_config_name

  defined_tags = local.common_tags

  policies {
    capacity {
      initial = var.instance_pool_size
      max = var.instance_pool_size
      min = var.instance_pool_size - 1
    }

    display_name = var.policy_name
    policy_type = "threshold"

    rules {
      action {
        type = "CHANGE_COUNT_BY"
        value = "1"
      }

      display_name = var.scale_out_rule_name

      metric {
        metric_type = "CPU_UTILIZATION"

        threshold {
          operator = "GT"
          value = "1"
        }
      }
    }

    rules {
      action {
        type = "CHANGE_COUNT_BY"
        value = "-1"
      }

      display_name = var.scale_in_rule_name

      metric {
        metric_type = "CPU_UTILIZATION"

        threshold {
          operator = "LT"
          value = "0"
        }
      }
    }
  }

  auto_scaling_resources {
    id = length(var.availability_domains) == 3 ? oci_core_instance_pool.oci_instance_pool_3_ad[0].id : (length(var.availability_domains) == 2 ? oci_core_instance_pool.oci_instance_pool_2_ad[0].id : oci_core_instance_pool.oci_instance_pool_1_ad[0].id)
    type = "instancePool"
  }
}

data "oci_core_instance_pool_instances" "oci_instance_pool_instances" {
  count = 1
  compartment_id = var.compartment_ocid
  instance_pool_id = length(var.availability_domains) == 3 ? oci_core_instance_pool.oci_instance_pool_3_ad[0].id : (length(var.availability_domains) == 2 ? oci_core_instance_pool.oci_instance_pool_2_ad[0].id : oci_core_instance_pool.oci_instance_pool_1_ad[0].id)
  depends_on = [
    oci_core_instance_pool.oci_instance_pool_3_ad,
    oci_core_instance_pool.oci_instance_pool_2_ad,
    oci_core_instance_pool.oci_instance_pool_1_ad]
}

data "oci_core_instance" "oci_instance_datasources" {
  count = var.instance_pool_size
  instance_id = lookup(data.oci_core_instance_pool_instances.oci_instance_pool_instances[0].instances[count.index], "id")
}

resource "null_resource" "verify_cloud_init" {
  count = var.instance_pool_size
  depends_on = [
    data.oci_core_instance.oci_instance_datasources]

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
      type = "ssh"
      host = element(data.oci_core_instance.oci_instance_datasources.*.private_ip, count.index)
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

resource "null_resource" "cloud_init_output" {
  count = var.instance_pool_size
  depends_on = [
    null_resource.verify_cloud_init]

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no ${var.user}@${element(data.oci_core_instance.oci_instance_datasources.*.private_ip, count.index)} 'echo hostname: $HOSTNAME, privateIp: ${element(data.oci_core_instance.oci_instance_datasources.*.private_ip, count.index)} - $(cloud-init status)' >> ${var.coturns_postinstall_status_file}"
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}

output "private_ips" {
  value = [
    data.oci_core_instance.oci_instance_datasources.*.private_ip]
}