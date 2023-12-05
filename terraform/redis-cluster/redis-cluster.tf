
variable "resource_name_root" {}
variable "environment" {}
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "role" {
    default = "redis-cluster"
}
variable "tag_namespace" {
    default = "jitsi"
}

variable "redis_cluster_node_count" {
    default = 3
}

variable "redis_cluster_node_memory_in_gbs" {
    default = 16
}

variable redis_cluster_software_version {
    default = "V7_0_5"
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

locals {
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.role" = var.role
    "${var.tag_namespace}.Name" = "${var.resource_name_root}-RedisCluster"
  }
}

data "oci_core_vcns" "vcns" {
  compartment_id = var.compartment_ocid
  display_name = "${var.oracle_region}-${var.environment}-vcn"
}

data "oci_core_subnets" "nat_subnets" {
    #Required
    compartment_id = var.compartment_ocid

    #Optional
    display_name = "${var.oracle_region}-${var.environment}-NATSubnet"
    vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
}

resource "oci_redis_redis_cluster" "redis_cluster" {
    #Required
    compartment_id = var.compartment_ocid
    display_name = "${var.resource_name_root}-RedisCluster"
    node_count = var.redis_cluster_node_count
    node_memory_in_gbs = var.redis_cluster_node_memory_in_gbs
    software_version = var.redis_cluster_software_version
    subnet_id = data.oci_core_subnets.nat_subnets.subnets[0].id

    #Optional
    defined_tags = local.common_tags
}
