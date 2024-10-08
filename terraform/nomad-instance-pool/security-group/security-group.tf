variable "resource_name_root" {}
variable "vcn_name" {}
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "ephemeral_ingress_cidr" {
  default = "10.0.0.0/8"
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

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_nomad_tcp" {
  network_security_group_id = oci_core_network_security_group.security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "10.0.0.0/8"
  stateless = false

  tcp_options {
    destination_port_range {
      min = 4646
      max = 4648
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_nomad_ingress" {
  network_security_group_id = oci_core_network_security_group.security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "10.0.0.0/8"
  stateless = false

  tcp_options {
    destination_port_range {
      min = 9996
      max = 9999
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_nomad_ephemeral_tcp" {
  network_security_group_id = oci_core_network_security_group.security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = var.ephemeral_ingress_cidr
  stateless = false

  tcp_options {
    destination_port_range {
      min = 20000
      max = 32000
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_nomad_ephemeral_udp" {
  network_security_group_id = oci_core_network_security_group.security_group.id
  direction = "INGRESS"
  protocol = "17"
  source = var.ephemeral_ingress_cidr
  stateless = false

  udp_options {
    destination_port_range {
      min = 20000
      max = 32000
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_telegraf_prometheus_tcp" {
  network_security_group_id = oci_core_network_security_group.security_group.id
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
