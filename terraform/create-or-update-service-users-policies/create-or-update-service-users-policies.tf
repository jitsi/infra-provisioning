variable "tenancy_ocid" {}
variable "compartment_name" {}
variable "compartment_id" {}
variable "video_editor_group_name" {}
variable "video_editor_policy_name" {}
variable "cs_history_group_name" {}
variable "cs_history_policy_name" {}
variable "regions" {
  type = list(string)
}
variable "cs_history_regions" {
  type = list(string)
}

provider "oci" {
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

//============ Policies ============

locals {
  # flatten ensures that this local value is a flat list of objects,
  # rather than a list of lists of objects
  video_editor_statements = concat(flatten([
  for region in var.regions:
  [
    #To execute object lifecycle policies, you must authorize the service to archive and delete objects on your behalf.
    "Allow service objectstorage-${region} to manage object-family in compartment ${var.compartment_name}",

    #Video-editor should be allowed to upload files and to create pre-authenticated request (PAR)"
    "Allow group ${var.video_editor_group_name} to manage object-family in compartment ${var.compartment_name} where target.bucket.name='vpaas-segments-${var.compartment_name}-${region}'",
   ]
  ]))

  cs_history_statements = concat(flatten([
  for region in var.cs_history_regions:
  [
    #To execute object lifecycle policies, you must authorize the service to archive and delete objects on your behalf.
    "Allow service objectstorage-${region} to manage object-family in compartment ${var.compartment_name}",

    #Content-sharing-history should be allowed to upload files and to create pre-authenticated request (PAR)"
    "Allow group ${var.cs_history_group_name} to manage object-family in compartment ${var.compartment_name} where target.bucket.name='vpaas-screenshots-${var.compartment_name}-${region}'",
  ]
  ]))
}

resource "oci_identity_policy" "video_editor_policy" {
  name = var.video_editor_policy_name
  description = "Allow video editor k8s service to access oci resources"
  compartment_id = var.compartment_id

  statements = local.video_editor_statements
}

resource "oci_identity_policy" "cs_history_policy" {
  name = var.cs_history_policy_name
  description = "Allow content-sharing-history k8s service to access oci resources"
  compartment_id = var.compartment_id

  statements = local.cs_history_statements
}

//============ Outputs ============

output "video_editor_policy_name" {
  value = oci_identity_policy.video_editor_policy.name
}

output "video_editor_policy_id" {
  value = oci_identity_policy.video_editor_policy.id
}

output "cs_history_policy_name" {
  value = oci_identity_policy.cs_history_policy.name
}

output "cs_history_policy_id" {
  value = oci_identity_policy.cs_history_policy.id
}