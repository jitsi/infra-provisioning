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

// ============ INPUTS ============

data "oci_core_vcns" "vcns" {
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}

data "oci_core_security_lists" "private_security_lists" {
  compartment_id = var.compartment_ocid
  vcn_id         = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-PrivateSecurityList"
}

data "oci_core_route_tables" "private_route_tables" {
  compartment_id = var.compartment_ocid
  vcn_id         = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "Private Route Table ${var.resource_name_root}-vcn"
}

// ============ SUBNET ============

// Jigasi subnet ip range will be from x.y.62.0 to x.y.62.127, 128 in total
resource "oci_core_subnet" "jigasi_subnet" {
  cidr_block          = format("%s.%s.62.0/25", split(".", data.oci_core_vcns.vcns.virtual_networks[0].cidr_block)[0], split(".", data.oci_core_vcns.vcns.virtual_networks[0].cidr_block)[1])
  display_name        = "${var.resource_name_root}-JigasiSubnet"
  dns_label           = "jigasisubnet"
  compartment_id      = var.compartment_ocid
  vcn_id              = data.oci_core_vcns.vcns.virtual_networks[0].id
  security_list_ids   = [
    data.oci_core_security_lists.private_security_lists.security_lists[0].id]
  route_table_id      = data.oci_core_route_tables.private_route_tables.route_tables[0].id
  prohibit_public_ip_on_vnic = true
}

// ============ JIGASI NETWORK SECURITY GROUP ============

resource "oci_core_network_security_group" "jigasi_network_security_group" {
  lifecycle {
    prevent_destroy = true
  }

  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-JigasiCustomSecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "jigasi_network_security_group_security_rule_1" {
  lifecycle {
    prevent_destroy = true
  }

  network_security_group_id = oci_core_network_security_group.jigasi_network_security_group.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

resource "oci_core_network_security_group_security_rule" "jigasi_network_security_group_security_rule_2" {
  lifecycle {
    prevent_destroy = true
  }

  network_security_group_id = oci_core_network_security_group.jigasi_network_security_group.id
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

resource "oci_core_network_security_group_security_rule" "jigasi_network_security_group_security_rule_3" {
  lifecycle {
    prevent_destroy = true
  }

  network_security_group_id = oci_core_network_security_group.jigasi_network_security_group.id
  //tcp
  protocol = "6"
  direction = "INGRESS"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "jigasi_network_security_group_security_rule_4" {
  lifecycle {
    prevent_destroy = true
  }

  network_security_group_id = oci_core_network_security_group.jigasi_network_security_group.id
  //tcp
  protocol = "6"
  direction = "INGRESS"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      min = 8301
      max = 8301
    }
  }
}

resource "oci_core_network_security_group_security_rule" "jigasi_network_security_group_security_rule_5" {
  lifecycle {
    prevent_destroy = true
  }

  network_security_group_id = oci_core_network_security_group.jigasi_network_security_group.id
  //udp
  protocol = "17"
  direction = "INGRESS"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  udp_options {
    destination_port_range {
      min = 8301
      max = 8301
    }
  }
}

resource "oci_core_network_security_group_security_rule" "jigasi_network_security_group_security_rule_6" {
  lifecycle {
    prevent_destroy = true
  }

  network_security_group_id = oci_core_network_security_group.jigasi_network_security_group.id
  //tcp
  protocol = "6"
  direction = "INGRESS"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      min = 7070
      max = 7070
    }
  }
}
