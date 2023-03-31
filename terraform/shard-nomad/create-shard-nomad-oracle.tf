variable "environment" {}
variable "domain" {}
variable "shard" {}
variable "nomad_lb_ip" {}
variable "cloud_name" {}
variable "release_number" {}
variable "name" {}
variable "oracle_region" {}
variable "role" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "resource_name_root" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "http_monitor_interval_in_seconds" {
  default = "30"
}
variable "http_monitor_timeout_in_seconds" {
  default = "10"
}
variable "http_monitor_is_enabled" {
  default = "true'"
}
variable "http_monitor_vantage_point_names" {
  default = [ "aws-pdx","aws-iad", "aws-gru","aws-fra","aws-tyo" ]
}

# leave alarm off until shard has JVBs or else alarms will ring on new shard creation
variable "alarm_is_enabled" {
  default = "false"
}
variable "alarm_body" {
  default = "FAILURE: Shard health check failed from all external perspectives and is in a failed state.\nCheck the on call cheat sheet for more details:\n https://docs.google.com/document/d/1hFMNI6tbahZhXDWqimJQ9cJO4Ofa3P02lKCAOUegdNM/edit"
}
variable "alarm_any_body" {
  default = "WARNING: Shard health check failed from at least one external perspective twice in a row.\nCheck the on call cheat sheet for more details:\n https://docs.google.com/document/d/1hFMNI6tbahZhXDWqimJQ9cJO4Ofa3P02lKCAOUegdNM/edit"
}

variable "alarm_repeat_notification_duration" {
  default = ""
}

variable "alarm_severity" {
  default = "CRITICAL"
}
variable "alarm_any_severity" {
  default = "WARNING"
}

variable "alarm_pagerduty_is_enabled" {
  default = "false"
}
variable "alarm_pagerduty_topic_name" {}
variable "alarm_email_topic_name" {}

locals {
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.domain" = var.domain
    "${var.tag_namespace}.shard" = var.shard
    "${var.tag_namespace}.cloud_name" = var.cloud_name
    "${var.tag_namespace}.environment_type" = var.environment_type
    "${var.tag_namespace}.release_number" = var.release_number
    "${var.tag_namespace}.role" = var.role
    "${var.tag_namespace}.shard-role" = var.role
    "${var.tag_namespace}.Name" = var.name
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

data "oci_ons_notification_topics" "email_notification_topics" {
    #Required
    compartment_id = var.compartment_ocid

    #Optional
 #   id = var.notification_topic_id
    name = var.alarm_email_topic_name
}

data "oci_ons_notification_topics" "pagerduty_notification_topics" {
    #Required
    compartment_id = var.compartment_ocid

    #Optional
 #   id = var.notification_topic_id
    name = var.alarm_pagerduty_topic_name
}

locals {
  overall_alarm_targets = var.alarm_pagerduty_is_enabled == "true" ? [data.oci_ons_notification_topics.pagerduty_notification_topics.notification_topics[0].topic_id] : [data.oci_ons_notification_topics.email_notification_topics.notification_topics[0].topic_id]
  email_only_alarm_targets = [data.oci_ons_notification_topics.email_notification_topics.notification_topics[0].topic_id]
}

resource "oci_health_checks_http_monitor" "shard_http_health" {
    #Required
    compartment_id = var.compartment_ocid
    display_name = "${var.resource_name_root}-HealthCheck"
    interval_in_seconds = var.http_monitor_interval_in_seconds
    protocol = "HTTPS"
    targets = [var.nomad_lb_ip]

    #Optional
    defined_tags = local.common_tags
    is_enabled = "true"
#    headers = {"Host": var.domain}
    method = "GET"
    path = "/${var.shard}/about/health"
    port = 443
    timeout_in_seconds = var.http_monitor_timeout_in_seconds
    vantage_point_names = var.http_monitor_vantage_point_names
}

resource "oci_monitoring_alarm" "shard_health_alarm_overall" {
    #Required
    compartment_id = var.compartment_ocid
    destinations = local.overall_alarm_targets
    display_name = "${var.resource_name_root}-HealthAlarm"
    is_enabled = var.alarm_is_enabled
    metric_compartment_id = var.compartment_ocid
    namespace = "oci_healthchecks"
    query = "HTTP.isHealthy[1m]{resourceId = \"${oci_health_checks_http_monitor.shard_http_health.id}\"}.grouping().max() < 1"
    severity = var.alarm_severity
    depends_on = [
      oci_health_checks_http_monitor.shard_http_health
    ]
    #Optional
    body = var.alarm_body
    defined_tags = local.common_tags
    message_format = "ONS_OPTIMIZED"
    pending_duration = "PT1M"
# can be set to repeat emails while a shard is down
    repeat_notification_duration = var.alarm_repeat_notification_duration
#    metric_compartment_id_in_subtree = var.alarm_metric_compartment_id_in_subtree
#    resolution = var.alarm_resolution
#    resource_group = var.alarm_resource_group
}

resource "oci_monitoring_alarm" "shard_health_alarm_any" {
    #Required
    compartment_id = var.compartment_ocid
    destinations = local.email_only_alarm_targets
    display_name = "${var.resource_name_root}-HealthAnyAlarm"
    is_enabled = var.alarm_is_enabled
    metric_compartment_id = var.compartment_ocid
    namespace = "oci_healthchecks"
    query = "HTTP.isHealthy[1m]{resourceId = \"${oci_health_checks_http_monitor.shard_http_health.id}\", errorMessage !~ \"*context deadline exceeded*\"}.min() < 1"
    severity = var.alarm_any_severity
    depends_on = [
      oci_health_checks_http_monitor.shard_http_health
    ]
    #Optional
    body = var.alarm_any_body
    defined_tags = local.common_tags
    message_format = "ONS_OPTIMIZED"
    pending_duration = "PT2M"
#    metric_compartment_id_in_subtree = var.alarm_metric_compartment_id_in_subtree
# can be set to repeat emails while a shard is down
#    repeat_notification_duration = var.alarm_repeat_notification_duration
#    resolution = var.alarm_resolution
#    resource_group = var.alarm_resource_group
}
