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

// Sip Jibri subnet ip range will be from x.y.4.0 to x.y.4.63
resource "oci_core_subnet" "sip_jibri_subnet" {
  cidr_block          = format("%s.%s.4.0/26", split(".", data.oci_core_vcns.vcns.virtual_networks[0].cidr_block)[0], split(".", data.oci_core_vcns.vcns.virtual_networks[0].cidr_block)[1])
  display_name        = "${var.resource_name_root}-SipJibriSubnet"
  dns_label           = "sipjibrisubnet"
  compartment_id      = var.compartment_ocid
  vcn_id              = data.oci_core_vcns.vcns.virtual_networks[0].id
  security_list_ids   = [
    data.oci_core_security_lists.private_security_lists.security_lists[0].id]
  route_table_id      = data.oci_core_route_tables.private_route_tables.route_tables[0].id
  prohibit_public_ip_on_vnic = true
}

// ============ SIP JIBRI NETWORK SECURITY GROUP ============

resource "oci_core_network_security_group" "jibri_network_security_group" {
  lifecycle {
    prevent_destroy = true
  }

  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-SipJibriCustomSecurityGroup"
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

