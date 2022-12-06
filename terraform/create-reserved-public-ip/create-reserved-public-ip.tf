variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "oracle_region" {}
variable "instance_pool_size" {}
variable "tag_namespace" {}
variable "environment" {}
variable "environment_type" {}
variable "git_branch" {}
variable "domain" {}
variable "shard_role" {}
variable "name" {}

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

resource "oci_core_public_ip" "reserverd_public_ip" {
  lifecycle {
    prevent_destroy = true
    #the ignoring applies only to updates to the existing reserved ips
    ignore_changes = all
  }

  defined_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.environment_type" = var.environment_type
    "${var.tag_namespace}.git_branch" = var.git_branch
    "${var.tag_namespace}.domain" = var.domain
    "${var.tag_namespace}.Name" = var.name
    "${var.tag_namespace}.shard-role" = var.shard_role
  }

  count = var.instance_pool_size
  compartment_id = var.compartment_ocid
  display_name = "reserved-ip-coturn-${count.index}"
  lifetime = "RESERVED"
}

