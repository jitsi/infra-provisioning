variable "bucket_name" {
    type = string
    default = "download-repo"
}
variable "bucket_namespace" {}
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "environment" {}
variable "tag_namespace" {
    type = string
    default = "jitsi"
}
# oracle/oci provider
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

# create an oci bucket with name download-repo-${var.environment}

resource "oci_objectstorage_bucket" "repo_bucket" {
    #Required
    compartment_id = var.compartment_ocid
    name = var.bucket_name
    namespace = var.bucket_namespace

    #Optional
    defined_tags = {
        "${var.tag_namespace}.environment"= "${var.environment}"
        "${var.tag_namespace}.role"= "repo"
    }
}
