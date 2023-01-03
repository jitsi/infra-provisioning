
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "load_balancer_shape" {}
variable "vcn_name" {}
variable "subnet_ocid" {}
variable "resource_name_root" {}

variable "dns_zone_name" {}
variable "dns_name" {}
variable "dns_compartment_ocid" {}

variable "whitelist" {
  type    = list(string)
}

variable "tag_namespace" {}
variable "environment" {}
variable "role" {}
variable "grid_name" {}

locals {
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.role" = var.role
    "${var.tag_namespace}.shard-role" = var.role
    "${var.tag_namespace}.grid" = var.grid_name
    "${var.tag_namespace}.Name" = var.resource_name_root
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

resource "oci_core_network_security_group" "security_group_lb" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-LBSecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_egress_lb" {
  network_security_group_id = oci_core_network_security_group.security_group_lb.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_lb_grid" {
  count = length(var.whitelist)
  network_security_group_id = oci_core_network_security_group.security_group_lb.id
  direction = "INGRESS"
  protocol = "6"
  source = var.whitelist[count.index]
  stateless = false

  tcp_options {
    destination_port_range {
      max = 4444
      min = 4444
    }
  }
}

resource "oci_load_balancer" "oci_load_balancer" {
  compartment_id = var.compartment_ocid
  display_name = "${var.resource_name_root}-LoadBalancer"
  shape = var.load_balancer_shape
  subnet_ids = [var.subnet_ocid]

  defined_tags = local.common_tags
  is_private = false
  network_security_group_ids = [oci_core_network_security_group.security_group_lb.id]
}

resource "oci_load_balancer_backend_set" "oci_load_balancer_bs" {
  load_balancer_id = oci_load_balancer.oci_load_balancer.id
  name = "GridLBBS"
  policy = "ROUND_ROBIN"
  health_checker {
    protocol = "HTTP"
    port = 4444
    retries = 3
    url_path = "/"
  }
}

resource "oci_load_balancer_listener" "main_listener" {
  load_balancer_id = oci_load_balancer.oci_load_balancer.id
  name = "GridListener"
  port = 4444
  default_backend_set_name = oci_load_balancer_backend_set.oci_load_balancer_bs.name
  protocol = "HTTP"
}


resource "oci_dns_rrset" "grid_dns_record" {
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

locals {
  lb_ip = oci_load_balancer.oci_load_balancer.ip_address_details[0].ip_address
}

output "lb_ip" {
  value = local.lb_ip
}
