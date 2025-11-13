variable "volume_count" {
    type = number
    default = 3
    description = "count of volumes"
}

variable "volume_size_in_gbs" {
    type = number
    default = 150
}

variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "oracle_region" {}
variable "environment" {}
variable "tag_namespace" {
    type = string
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

data "oci_identity_availability_domains" "availability_domains" {
	#Required
	compartment_id = var.tenancy_ocid
}

resource "oci_core_volume" "emqx-volume" {
    count             = var.volume_count

    #Required
    compartment_id = var.compartment_ocid

    #Optional
    availability_domain = data.oci_identity_availability_domains.availability_domains.availability_domains[count.index%length(data.oci_identity_availability_domains.availability_domains.availability_domains)].name

    defined_tags = {"${var.tag_namespace}.environment" = var.environment}
    display_name = "emqx-volume-${count.index}"
    freeform_tags = {
        "volume-index" = "${count.index}"
        "volume-type" = "emqx"
        "volume-role" = "emqx"
    }

    size_in_gbs = var.volume_size_in_gbs
}
