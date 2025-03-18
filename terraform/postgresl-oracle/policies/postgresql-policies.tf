variable "environment" {
  description = "Environment"
  type = string
}

variable "compartment_ocid" {
  description = "Compartment ID where to create resources for Requestor Tenancy"
  type        = string
}


variable "tenancy_ocid" {
  description = "Tenancy ID where to create resources for Requestor Tenancy"
  type        = string
}

variable "oracle_region" {
  description = "Oracle Cloud Infrastructure region"
  type        = string
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

resource "oci_identity_policy" "psql_secrets_policy" {
  compartment_id = var.compartment_ocid
  description    = "Policy to allow DB management service to read secret-family for mentioned compartment"
  name           = "${var.environment}-psql-secrets-policy"
  statements     = ["Allow service dpd to read secret-family in compartment id ${var.compartment_ocid}"]
}
