variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "oracle_region" {}
variable "tag_namespace" {}

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

resource "oci_identity_tag_namespace" "eghtjitsi" {
    #Required
    compartment_id = var.compartment_ocid
    description = "eghtjitsi tags"
    name = var.tag_namespace
}

resource "oci_identity_tag" "environment" {
  #Required
  description      = "environment"
  name             = "environment"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "environment_type" {
  #Required
  description      = "environment_type"
  name             = "environment_type"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "git_branch" {
  #Required
  description      = "git_branch"
  name             = "git_branch"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "domain" {
  #Required
  description      = "domain"
  name             = "domain"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "shard" {
  #Required
  description      = "shard"
  name             = "shard"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "shard-role" {
  #Required
  description      = "shard-role"
  name             = "shard-role"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "grid" {
  #Required
  description      = "grid"
  name             = "grid"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "grid-role" {
  #Required
  description      = "grid-role"
  name             = "grid-role"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "Name" {
  #Required
  description      = "Name"
  name             = "Name"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "xmpp_host_public_ip_address" {
  #Required
  description      = "xmpp_host_public_ip_address"
  name             = "xmpp_host_public_ip_address"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "release_number" {
  #Required
  description      = "release_number"
  name             = "release_number"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "build_id" {
  #Required
  description      = "build_id"
  name             = "build_id"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "MetaVersion" {
  #Required
  description      = "MetaVersion"
  name             = "MetaVersion"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "TS" {
  #Required
  description      = "TS"
  name             = "TS"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "Type" {
  #Required
  description      = "Type"
  name             = "Type"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "Version" {
  #Required
  description      = "Version"
  name             = "Version"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "role" {
  #Required
  description      = "replaces shard-role"
  name             = "role"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "use_eip" {
  #Required
  description      = "Use Elastic IPs"
  name             = "use_eip"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "aws_cloud_name" {
  #Required
  description      = "AWS cloud name"
  name             = "aws_cloud_name"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "jibri_release_number" {
  #Required
  description      = "Jibri release number"
  name             = "jibri_release_number"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}
resource "oci_identity_tag" "jvb_release_number" {
  #Required
  description      = "JVB release number"
  name             = "jvb_release_number"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}
resource "oci_identity_tag" "jigasi_release_number" {
  #Required
  description      = "Jigasi release number"
  name             = "jigasi_release_number"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "aws_auto_scale_group" {
  #Required
  description      = "AWS autoscale group name"
  name             = "aws_auto_scale_group"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "autoscaler_sidecar_jvb_flag" {
  #Required
  description      = "Autoscaler sidecar jvb"
  name             = "autoscaler_sidecar_jvb_flag"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "jvb_pool_mode" {
  #Required
  description      = "JVB Pool mode"
  name             = "jvb_pool_mode"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}

resource "oci_identity_tag" "unique_id" {
  #Required
  description      = "Standalone Unique ID"
  name             = "unique_id"
  tag_namespace_id = oci_identity_tag_namespace.eghtjitsi.id
}
