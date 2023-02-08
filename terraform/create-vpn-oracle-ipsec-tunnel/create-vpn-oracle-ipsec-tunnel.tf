variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "oracle_region" {}
variable "vcn_name" {}
variable "resource_name_root" {}
variable "bgp_asn" {}
variable "tunnel_1_ip_address" {}
variable "tunnel_1_shared_secret" {}
variable "tunnel_1_ipsec_customer_interface_ip" {}
variable "tunnel_1_ipsec_oracle_interface_ip" {}
variable "tunnel_2_ipsec_customer_interface_ip" {}
variable "tunnel_2_ipsec_oracle_interface_ip" {}
variable "tunnel_2_ip_address" {}
variable "tunnel_2_shared_secret" {}

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

data "oci_core_drgs" "drgs" {
  compartment_id = var.compartment_ocid
  filter {
    name = "display_name"
    values = [
      "DRG .*"]
    regex = true
  }
}

// ============ CUSTOMER-PREMISES EQUIPMENT ============

resource "oci_core_cpe" "cpe_1" {
  compartment_id = var.compartment_ocid
  ip_address = var.tunnel_1_ip_address

  display_name = "aws-tunnel-1"
}

resource "oci_core_cpe" "cpe_2" {
  compartment_id = var.compartment_ocid
  ip_address = var.tunnel_2_ip_address

  display_name = "aws-tunnel-2"
}

// ============ IP SEC CONNECTION ============

resource "oci_core_ipsec" "ipsec_connection_1" {
  depends_on = [
    oci_core_cpe.cpe_1
  ]

  compartment_id = var.compartment_ocid
  cpe_id = oci_core_cpe.cpe_1.id
  drg_id = data.oci_core_drgs.drgs.drgs[0].id

  #Required; Start with dummy routes and re-configure the tunnel to use BGP dynamic routing using "oci_core_ipsec_connection_tunnel_management"
  static_routes = [
    "10.0.1.0/24"]
  display_name = "oci-to-aws-1"
}

resource "oci_core_ipsec" "ipsec_connection_2" {
  depends_on = [
    oci_core_cpe.cpe_2]

  compartment_id = var.compartment_ocid
  cpe_id = oci_core_cpe.cpe_2.id
  drg_id = data.oci_core_drgs.drgs.drgs[0].id

  #Required
  static_routes = [
    "10.0.1.0/24"]
  display_name = "oci-to-aws-2"
}

data "oci_core_ipsec_connection_tunnels" "ipsec_connection_1_tunnels" {
  ipsec_id = oci_core_ipsec.ipsec_connection_1.id
}

data "oci_core_ipsec_connection_tunnels" "ipsec_connection_2_tunnels" {
  ipsec_id = oci_core_ipsec.ipsec_connection_2.id
}

resource "oci_core_ipsec_connection_tunnel_management" "ipsec_connection_1_tunnel_1" {
  ipsec_id = oci_core_ipsec.ipsec_connection_1.id
  tunnel_id = data.oci_core_ipsec_connection_tunnels.ipsec_connection_1_tunnels.ip_sec_connection_tunnels[0].id
  routing = "BGP"
  display_name = "tunnel-1"

  bgp_session_info {
    customer_bgp_asn = var.bgp_asn
    customer_interface_ip = var.tunnel_1_ipsec_customer_interface_ip
    oracle_interface_ip = var.tunnel_1_ipsec_oracle_interface_ip
  }
  shared_secret = var.tunnel_1_shared_secret
}

resource "oci_core_ipsec_connection_tunnel_management" "ipsec_connection_1_tunnel_dummy" {
  depends_on = [
    oci_core_ipsec_connection_tunnel_management.ipsec_connection_1_tunnel_1]

  ipsec_id = oci_core_ipsec.ipsec_connection_1.id
  tunnel_id = data.oci_core_ipsec_connection_tunnels.ipsec_connection_1_tunnels.ip_sec_connection_tunnels[1].id
  routing = "STATIC"
  display_name = "dummy"
}

resource "oci_core_ipsec_connection_tunnel_management" "ipsec_connection_2_tunnel_1" {
  ipsec_id = oci_core_ipsec.ipsec_connection_2.id
  tunnel_id = data.oci_core_ipsec_connection_tunnels.ipsec_connection_2_tunnels.ip_sec_connection_tunnels[0].id
  routing = "BGP"
  display_name = "tunnel-1"

  bgp_session_info {
    customer_bgp_asn = var.bgp_asn
    customer_interface_ip = var.tunnel_2_ipsec_customer_interface_ip
    oracle_interface_ip = var.tunnel_2_ipsec_oracle_interface_ip
  }
  shared_secret = var.tunnel_2_shared_secret
}

resource "oci_core_ipsec_connection_tunnel_management" "ipsec_connection_2_tunnel_dummy" {
  depends_on = [
    oci_core_ipsec_connection_tunnel_management.ipsec_connection_2_tunnel_1]

  ipsec_id = oci_core_ipsec.ipsec_connection_2.id
  tunnel_id = data.oci_core_ipsec_connection_tunnels.ipsec_connection_2_tunnels.ip_sec_connection_tunnels[1].id
  routing = "STATIC"
  display_name = "dummy"
}
