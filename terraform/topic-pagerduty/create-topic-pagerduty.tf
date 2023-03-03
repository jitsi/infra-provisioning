variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "environment" {}
variable "environment_type" {
    default = "dev"
}
variable "tag_namespace" {
    default = "jitsi"
}
variable "notification_topic_description" {
    default = "Health notifications"
}
variable "pagerduty_endpoint" {}
variable "email" {}

locals {
  topic_name = "${var.environment}-PagerDutyTopic"
  common_tags = {
        "${var.tag_namespace}.Name" = "${var.environment}-PagerDutyTopic"
        "${var.tag_namespace}.environment" = var.environment
        "${var.tag_namespace}.environment_type" = var.environment_type
    }
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


resource "oci_ons_notification_topic" "pagerduty_notification_topic" {
    #Required
    compartment_id = var.compartment_ocid
    name = local.topic_name

    #Optional
    defined_tags = local.common_tags
    description = var.notification_topic_description
}

resource "oci_ons_subscription" "pagerduty_subscription" {
    #Required
    compartment_id = var.compartment_ocid
    endpoint = var.pagerduty_endpoint
    protocol = "PAGERDUTY"
    topic_id = oci_ons_notification_topic.pagerduty_notification_topic.id

    #Optional
    defined_tags = local.common_tags
}

resource "oci_ons_subscription" "email_subscription" {
    #Required
    compartment_id = var.compartment_ocid
    endpoint = var.email
    protocol = "EMAIL"
    topic_id = oci_ons_notification_topic.pagerduty_notification_topic.id

    #Optional
    defined_tags = local.common_tags
}

