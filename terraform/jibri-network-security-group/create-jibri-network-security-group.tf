variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "oracle_region" {}
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

// ============ JIBRI NETWORK SECURITY GROUP ============

data "oci_core_vcns" "vcns" {
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}

resource "oci_core_network_security_group" "jibri_network_security_group" {
  lifecycle {
    prevent_destroy = true
  }

  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-JibriCustomSecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "jibri_network_security_group_security_rule_1" {
  lifecycle {
    prevent_destroy = true
  }

  network_security_group_id = oci_core_network_security_group.jibri_network_security_group.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

resource "oci_core_network_security_group_security_rule" "jibri_network_security_group_security_rule_2" {
  lifecycle {
    prevent_destroy = true
  }

  network_security_group_id = oci_core_network_security_group.jibri_network_security_group.id
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

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_nomad_tcp" {
  network_security_group_id = oci_core_network_security_group.jibri_network_security_group.id
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
  network_security_group_id = oci_core_network_security_group.jibri_network_security_group.id
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
  network_security_group_id = oci_core_network_security_group.jibri_network_security_group.id
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

resource "oci_core_network_security_group_security_rule" "nsg_rule_telegraf_prometheus_tcp" {
  network_security_group_id = oci_core_network_security_group.jibri_network_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 9126
      min = 9126
    }
  }
}