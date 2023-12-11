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

// ============ VCN ============

data "oci_core_vcns" "vcns" {
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}

data "oci_core_services" "object_storage_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

data "oci_core_service_gateways" "service_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
}

resource "oci_core_nat_gateway" "nat_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name   = "NAT Gateway ${data.oci_core_vcns.vcns.virtual_networks[0].display_name}"
}

resource "oci_core_route_table" "private_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name   = "Private Route Table ${data.oci_core_vcns.vcns.virtual_networks[0].display_name}"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat_gateway.id
  }

  route_rules {
    destination       = lookup(data.oci_core_services.object_storage_services.services[0], "cidr_block")
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = data.oci_core_service_gateways.service_gateway.service_gateways[0].id
  }
}

data "oci_core_route_tables" "route_table" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "Route Table ${data.oci_core_vcns.vcns.virtual_networks[0].display_name}"
}


// ============ SECURITY LISTS ============

data "oci_core_security_lists" "private_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-PrivateSecurityList"
}

data "oci_core_security_lists" "ops_security_lists" {
  compartment_id = var.compartment_ocid
  vcn_id         = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-OpsSecurityList"
}

// ============ SUBNETS ============

resource "oci_core_subnet" "nat_subnet" {
  cidr_block          = format("%s.%s.128.0/18", split(".", data.oci_core_vcns.vcns.virtual_networks[0].cidr_block)[0], split(".", data.oci_core_vcns.vcns.virtual_networks[0].cidr_block)[1])
  display_name        = "${var.resource_name_root}-NATSubnet"
  dns_label           = "natsubnet"
  compartment_id      = var.compartment_ocid
  vcn_id              = data.oci_core_vcns.vcns.virtual_networks[0].id
  security_list_ids   = [
                            data.oci_core_security_lists.private_security_lists.security_lists[0].id,
                            data.oci_core_security_lists.ops_security_lists.security_lists[0].id
                        ]
  route_table_id      = oci_core_route_table.private_route_table.id
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "coturn_subnet" {
  cidr_block = format("%s.%s.2.0/24", split(".", data.oci_core_vcns.vcns.virtual_networks[0].cidr_block)[0], split(".", data.oci_core_vcns.vcns.virtual_networks[0].cidr_block)[1])
  display_name = "${var.resource_name_root}-PublicSubnet2"
  dns_label = "publicsubnet2"
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  security_list_ids = [
    data.oci_core_security_lists.private_security_list.security_lists[0].id]
  route_table_id = data.oci_core_route_tables.route_table.route_tables[0].id
}

// ============ OUTPUTS ============

output "private_route_table_name" {
  value = oci_core_route_table.private_route_table.display_name
}

output "nat_gateway_name" {
  value = oci_core_nat_gateway.nat_gateway.display_name
}

output "nat_subnet_name" {
  value = oci_core_subnet.nat_subnet.display_name
}

output "coturn_subnet_name" {
  value = oci_core_subnet.coturn_subnet.display_name
}