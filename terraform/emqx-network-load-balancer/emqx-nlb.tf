variable "environment" {}
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "resource_name_root" {}
variable "public_subnet_ocid" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "dns_name" {}
variable "dns_zone_name" {}
variable "dns_compartment_ocid" {}
variable "lb_security_group_id" {}
variable "load_balancer_shape" {
  default = "flexible"
}
variable "load_balancer_shape_details_maximum_bandwidth_in_mbps" {
  default = "100"
}
variable "load_balancer_shape_details_minimum_bandwidth_in_mbps" {
  default = "10"
}

locals {
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.environment_type" = var.environment_type
    "${var.tag_namespace}.role" = "emqx-lb"
    "${var.tag_namespace}.Name" = "${var.resource_name_root}-nlb"
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

# OCI Load Balancer configured for TCP (Network Load Balancer)
resource "oci_load_balancer" "emqx_load_balancer" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.resource_name_root}-LoadBalancer"
  shape          = var.load_balancer_shape

  shape_details {
    maximum_bandwidth_in_mbps = var.load_balancer_shape_details_maximum_bandwidth_in_mbps
    minimum_bandwidth_in_mbps = var.load_balancer_shape_details_minimum_bandwidth_in_mbps
  }

  subnet_ids = [var.public_subnet_ocid]

  is_private                 = false
  network_security_group_ids = [var.lb_security_group_id]

  defined_tags = local.common_tags
}

# Backend Set for MQTT (port 1883) - TCP protocol
# Health check on HAProxy health endpoint
resource "oci_load_balancer_backend_set" "mqtt_backend_set" {
  load_balancer_id = oci_load_balancer.emqx_load_balancer.id
  name             = "emqx-mqtt-backend"
  policy           = "LEAST_CONNECTIONS"

  health_checker {
    protocol       = "HTTP"
    port           = 8080
    url_path       = "/haproxy_health"
    interval_ms    = 10000
    timeout_in_millis = 3000
    retries        = 3
  }
}

# Backend Set for MQTTS (port 8883) - TCP protocol
resource "oci_load_balancer_backend_set" "mqtts_backend_set" {
  load_balancer_id = oci_load_balancer.emqx_load_balancer.id
  name             = "emqx-mqtts-backend"
  policy           = "LEAST_CONNECTIONS"

  health_checker {
    protocol       = "HTTP"
    port           = 8080
    url_path       = "/haproxy_health"
    interval_ms    = 10000
    timeout_in_millis = 3000
    retries        = 3
  }
}

# Backend Set for WebSocket (port 8083) - TCP protocol
resource "oci_load_balancer_backend_set" "ws_backend_set" {
  load_balancer_id = oci_load_balancer.emqx_load_balancer.id
  name             = "emqx-ws-backend"
  policy           = "LEAST_CONNECTIONS"

  health_checker {
    protocol       = "HTTP"
    port           = 8080
    url_path       = "/haproxy_health"
    interval_ms    = 10000
    timeout_in_millis = 3000
    retries        = 3
  }
}

# Backend Set for WebSocket Secure (port 8084) - TCP protocol
resource "oci_load_balancer_backend_set" "wss_backend_set" {
  load_balancer_id = oci_load_balancer.emqx_load_balancer.id
  name             = "emqx-wss-backend"
  policy           = "LEAST_CONNECTIONS"

  health_checker {
    protocol       = "HTTP"
    port           = 8080
    url_path       = "/haproxy_health"
    interval_ms    = 10000
    timeout_in_millis = 3000
    retries        = 3
  }
}

# Note: Backends will be automatically added by the EMQX instance pools
# via the load_balancers block in each instance pool definition

# Listener for MQTT (port 1883) - TCP protocol
resource "oci_load_balancer_listener" "mqtt_listener" {
  load_balancer_id         = oci_load_balancer.emqx_load_balancer.id
  name                     = "emqx-mqtt-listener"
  default_backend_set_name = oci_load_balancer_backend_set.mqtt_backend_set.name
  port                     = 1883
  protocol                 = "TCP"
}

# Listener for MQTTS (port 8883) - TCP protocol
resource "oci_load_balancer_listener" "mqtts_listener" {
  load_balancer_id         = oci_load_balancer.emqx_load_balancer.id
  name                     = "emqx-mqtts-listener"
  default_backend_set_name = oci_load_balancer_backend_set.mqtts_backend_set.name
  port                     = 8883
  protocol                 = "TCP"
}

# Listener for WebSocket (port 8083) - TCP protocol
resource "oci_load_balancer_listener" "ws_listener" {
  load_balancer_id         = oci_load_balancer.emqx_load_balancer.id
  name                     = "emqx-ws-listener"
  default_backend_set_name = oci_load_balancer_backend_set.ws_backend_set.name
  port                     = 8083
  protocol                 = "TCP"
}

# Listener for WebSocket Secure (port 8084) - TCP protocol
resource "oci_load_balancer_listener" "wss_listener" {
  load_balancer_id         = oci_load_balancer.emqx_load_balancer.id
  name                     = "emqx-wss-listener"
  default_backend_set_name = oci_load_balancer_backend_set.wss_backend_set.name
  port                     = 8084
  protocol                 = "TCP"
}

# DNS A record for load balancer
resource "oci_dns_rrset" "emqx_lb_dns_record" {
  zone_name_or_id = var.dns_zone_name
  domain          = var.dns_name
  rtype           = "A"
  compartment_id  = var.dns_compartment_ocid

  items {
    domain = var.dns_name
    rtype  = "A"
    ttl    = "60"
    rdata  = oci_load_balancer.emqx_load_balancer.ip_address_details[0].ip_address
  }
}

output "lb_ip" {
  value = oci_load_balancer.emqx_load_balancer.ip_address_details[0].ip_address
}

output "dns_name" {
  value = var.dns_name
}

output "lb_id" {
  value = oci_load_balancer.emqx_load_balancer.id
}

# Output backend set names for instance pool attachment
output "mqtt_backend_set_name" {
  value = oci_load_balancer_backend_set.mqtt_backend_set.name
}

output "mqtts_backend_set_name" {
  value = oci_load_balancer_backend_set.mqtts_backend_set.name
}

output "ws_backend_set_name" {
  value = oci_load_balancer_backend_set.ws_backend_set.name
}

output "wss_backend_set_name" {
  value = oci_load_balancer_backend_set.wss_backend_set.name
}
