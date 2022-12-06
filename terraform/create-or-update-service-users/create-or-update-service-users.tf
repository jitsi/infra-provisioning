variable "tenancy_ocid" {}
variable "oracle_region" {}
variable "service_user_type" {}

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

//============ Users and Groups ============

resource "oci_identity_group" "video-editor-group" {
  compartment_id = var.tenancy_ocid
  description = "Group for video-editor k8s service"
  name = "${var.service_user_type}-video-editor-group"
}

resource "oci_identity_user" "video-editor-user" {
  compartment_id = var.tenancy_ocid
  description = "User for video-editor k8s service"
  name = "${var.service_user_type}-video-editor"
}

resource "oci_identity_user_group_membership" "video-editor-user-group-membership" {
  group_id = oci_identity_group.video-editor-group.id
  user_id = oci_identity_user.video-editor-user.id
}

resource "oci_identity_group" "content-sharing-history-group" {
  compartment_id = var.tenancy_ocid
  description = "Group for content-sharing-history k8s service"
  name = "${var.service_user_type}-content-sharing-history-group"
}

resource "oci_identity_user" "content-sharing-history-user" {
  compartment_id = var.tenancy_ocid
  description = "User for content-sharing-history k8s service"
  name = "${var.service_user_type}-content-sharing-history"
}

resource "oci_identity_user_group_membership" "content-sharing-history-group-membership" {
  group_id = oci_identity_group.content-sharing-history-group.id
  user_id = oci_identity_user.content-sharing-history-user.id
}


//============ Outputs ============

output "video_editor_user_name" {
  value = oci_identity_user.video-editor-user.name
}

output "video_editor_user_id" {
  value = oci_identity_user.video-editor-user.id
}

output "video_editor_group_name" {
  value = oci_identity_group.video-editor-group.name
}

output "video_editor_group_id" {
  value = oci_identity_group.video-editor-group.id
}

output "content-sharing-history_user_name" {
  value = oci_identity_user.content-sharing-history-user.name
}

output "content-sharing-history_user_id" {
  value = oci_identity_user.content-sharing-history-user.id
}

output "content-sharing-history_group_name" {
  value = oci_identity_group.content-sharing-history-group.name
}

output "content-sharing-history_group_id" {
  value = oci_identity_group.content-sharing-history-group.id
}