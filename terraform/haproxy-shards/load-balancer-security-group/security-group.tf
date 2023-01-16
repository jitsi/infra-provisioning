variable "resource_name_root" {}
variable "vcn_name" {}
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}

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

resource "oci_core_network_security_group" "lb_security_group" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-SecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "lb_nsg_rule_egress" {
  network_security_group_id = oci_core_network_security_group.lb_security_group.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

//TODO only vox ips
resource "oci_core_network_security_group_security_rule" "lb_nsg_rule_ingress_http" {
  network_security_group_id = oci_core_network_security_group.lb_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "0.0.0.0/0"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 80
      min = 80
    }
  }
}

//TODO only vox ips
resource "oci_core_network_security_group_security_rule" "lb_nsg_rule_ingress_https" {
  network_security_group_id = oci_core_network_security_group.lb_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "0.0.0.0/0"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}