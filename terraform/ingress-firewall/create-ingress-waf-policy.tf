variable "environment" {}
variable "name" {}
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "resource_name_root" {}
variable "environment_type" {}
variable "tag_namespace" {}

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

resource "oci_waf_web_app_firewall_policy" "oci_ingress_waf_firewall_policy" {
  compartment_id = var.compartment_ocid
  display_name = "${var.oracle_region}-PublicWAFPolicy"

  actions {
    name = "ForbiddenAction"
    type = "PRECONFIGURED"
    code = "403"
  }

  request_protection {
    rules {
      action_name = "ForbiddenAction"
      name = "preconfigured HTTP protections"
      #protection_capabilities {
      #  key = "920390"  ## Limit arguments total length (max_total_argument_length)
      #  version = "1"
      #}
      #protection_capabilities {
      #  key = "920380"  ## Number of Arguments Limits (max_number_of_arguments)
      #  version = "1"
      #}
      #protection_capabilities {
      #  key = "920370"  ## Limit argument value length (max_single_argument_length)
      #  version = "1"
      #}
      protection_capabilities {
        key = "921110"  ## HTTP request smuggling
        version = "3"
      }
      type = "PROTECTION"  # ACCESS_CONTROL', 'PROTECTION', or 'REQUEST_RATE_LIMITING'

      #protection_capability_settings {
      #  max_number_of_arguments = var.web_app_firewall_policy_request_protection_rules_protection_capability_settings_max_number_of_arguments
      #  max_single_argument_length = var.web_app_firewall_policy_request_protection_rules_protection_capability_settings_max_single_argument_length
      #  max_total_argument_length = var.web_app_firewall_policy_request_protection_rules_protection_capability_settings_max_total_argument_length
      #}
    }
  }
}

locals {
  policy_id = oci_waf_web_app_firewall_policy.oci_ingress_waf_firewall_policy.id
  policy_name = oci_waf_web_app_firewall_policy.oci_ingress_waf_firewall_policy.display_name
}

output "policy_id" {
  value = local.policy_id
}

output "policy_name" {
  value = local.policy_name
}
