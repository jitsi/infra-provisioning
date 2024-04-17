variable "environment" {}
variable "name" {}
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "resource_name_root" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "load_balancer_id" {}
variable "waf_policy_id" {}

locals {
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.environment_type" = var.environment_type
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

resource "oci_waf_web_app_firewall" "oci_ingress_waf_firewall" {
    #Required
    backend_type = "LOAD_BALANCER"
    compartment_id = var.compartment_ocid
    load_balancer_id = var.load_balancer_id
    web_app_firewall_policy_id = var.waf_policy_id

    #Optional
    #defined_tags = {"foo-namespace.bar-key"= "value"}
    display_name = var.name
    #freeform_tags = {"bar-key"= "value"}
    #system_tags = var.web_app_firewall_system_tags
}

locals {
  firewall_id = oci_waf_web_app_firewall.oci_ingress_waf_firewall.id
  firewall_name = oci_waf_web_app_firewall.oci_ingress_waf_firewall.display_name
}

output "firewall_id" {
  value = local.firewall_id
}

output "firewall_name" {
  value = local.firewall_name
}
