variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "dns_zone_name" {}
variable "tag_namespace" {
    default = "jitsi"
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

resource "oci_dns_zone" "geo_zone" {
    #Required
    compartment_id = var.tenancy_ocid
    name = var.dns_zone_name
    zone_type = "PRIMARY"
}