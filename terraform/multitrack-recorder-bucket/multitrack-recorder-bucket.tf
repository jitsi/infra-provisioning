variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "environment" {}
variable "tag_namespace" {
    default = "jitsi"
}
variable "bucket_namespace" {
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
        "${var.tag_namespace}.shard-role" = "multitrack-recorder"
    }
    bucket_name = "multitrack-recorder-${var.environment}"
    queue_name = "multitrack-recorder-${var.environment}"
}

resource "oci_objectstorage_bucket" "bucket" {
    #Required
    compartment_id = var.compartment_ocid
    name = local.bucket_name
    namespace = var.bucket_namespace

    #Optional
    defined_tags = local.common_tags
}

resource "oci_queue_queue" "queue" {
    #Required
    display_name = local.queue_name
    
    compartment_id = var.compartment_ocid
    #Optional
    defined_tags = local.common_tags
   
}
