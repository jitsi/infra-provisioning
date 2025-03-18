variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "environment" {}
variable "tag_namespace" {
    default = "jitsi"
}
variable "vault_type" {
    default = "DEFAULT"
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
        "${var.tag_namespace}.shard-role" = "nomad-general-vault"
    }
}

# create a vault in the compartment
resource "oci_kms_vault" "general_vault" {
    #Required
    compartment_id = var.compartment_ocid
    display_name = "${var.environment} Nomad General Vault"
    vault_type = var.vault_type

    #Optional
    defined_tags = local.common_tags
}
