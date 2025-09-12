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

resource "oci_core_network_security_group" "security_group" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-SecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_egress" {
  network_security_group_id = oci_core_network_security_group.security_group.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_ssh" {
  network_security_group_id = oci_core_network_security_group.security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 22
      min = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_http" {
  network_security_group_id = oci_core_network_security_group.security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 83
      min = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_https" {
  network_security_group_id = oci_core_network_security_group.security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_health" {
  network_security_group_id = oci_core_network_security_group.security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      min = 8080
      max = 8081
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_knight" {
  network_security_group_id = oci_core_network_security_group.security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "10.0.0.0/8"
  stateless = false

  tcp_options {
    destination_port_range {
      min = 8180
      max = 8180
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_consul_serf_tcp" {
  network_security_group_id = oci_core_network_security_group.security_group.id
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
  network_security_group_id = oci_core_network_security_group.security_group.id
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

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_peering" {
  network_security_group_id = oci_core_network_security_group.security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "10.0.0.0/8"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 1024
      min = 1024
    }
  }
}