variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "oracle_region" {}
variable "environment" {}
variable "vcn_name" {}
variable "resource_name_root" {}

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

// ============ NETWORKS SECURITY GROUPS ============

resource "oci_core_network_security_group" "jvb_network_security_group" {
    compartment_id = var.compartment_ocid
    vcn_id         = data.oci_core_vcns.vcns.virtual_networks[0].id
    display_name   = "${var.resource_name_root}-JVBSecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "jvb_network_security_group_security_rule_egress" {
    network_security_group_id = oci_core_network_security_group.jvb_network_security_group.id
    direction                 = "EGRESS"
    destination               = "0.0.0.0/0"
    protocol                  = "all"
}

resource "oci_core_network_security_group_security_rule" "jvb_network_security_group_security_rule_https" {
    network_security_group_id = oci_core_network_security_group.jvb_network_security_group.id
    protocol                  = "6"   //tcp
    direction                 = "INGRESS"
    source                    = "0.0.0.0/0"
    stateless                 = false

    tcp_options {
        destination_port_range {
          min = 443
          max = 443
        }
    }
}

resource "oci_core_network_security_group_security_rule" "jvb_network_security_group_security_rule_media" {
    network_security_group_id = oci_core_network_security_group.jvb_network_security_group.id
    protocol                  = "17"   //udp
    direction                 = "INGRESS"
    source                    = "0.0.0.0/0"
    stateless                 = false

    udp_options {
        destination_port_range {
          min = 10000
          max = 10000
        }
    }
}
