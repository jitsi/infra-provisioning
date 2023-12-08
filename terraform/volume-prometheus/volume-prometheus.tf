variable "volume_size_in_gbs" {
    type = number
    default = 500
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

resource "oci_core_volume" "prometheus-volume" {
    #Required
    compartment_id = var.compartment_ocid

    #Optional
    # autotune_policies {
    #     #Required
    #     autotune_type = var.volume_autotune_policies_autotune_type

    #     #Optional
    #     max_vpus_per_gb = var.volume_autotune_policies_max_vpus_per_gb
    # }
    # use first AD
    availability_domain = data.oci_identity_availability_domains.availability_domains.availability_domains[0].name

    # backup_policy_id = data.oci_core_volume_backup_policies.test_volume_backup_policies.volume_backup_policies.0.id
    # block_volume_replicas {
    #     #Required
    #     availability_domain = var.volume_block_volume_replicas_availability_domain

    #     #Optional
    #     display_name = var.volume_block_volume_replicas_display_name
    # }
    defined_tags = {"${var.tag_namespace}.environment" = var.environment}
    display_name = "prometheus-volume"
    freeform_tags = {
        "volume-type" = "prometheus"
        "volume-role" = "consul"
    }

    # is_auto_tune_enabled = var.volume_is_auto_tune_enabled
    # kms_key_id = oci_kms_key.test_key.id
    size_in_gbs = var.volume_size_in_gbs
    # size_in_mbs = var.volume_size_in_mbs
    # source_details {
    #     #Required
    #     id = var.volume_source_details_id
    #     type = var.volume_source_details_type
    # }
    # vpus_per_gb = var.volume_vpus_per_gb
    # block_volume_replicas_deletion = true

}
