variable "oracle_region" {}
variable "environment" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}

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
  display_name = "${var.environment}-${var.oracle_region}-PublicWAFPolicy"

  actions {
    name = "DefaultAllow"
    type = "ALLOW"
  }
  actions {
    name = "ForbiddenAction"
    type = "RETURN_HTTP_RESPONSE"
    code = "403"
  }

  request_access_control {
    default_action_name = "DefaultAllow"
    rules {
      action_name = "ForbiddenAction"
      name = "HTTP request smuggling"
      type = "ACCESS_CONTROL"
      condition = "i_contains(keys(http.request.headers), 'Content-Length') && i_contains(http.request.headers.\"transfer-encoding\", 'chunked')"
      condition_language = "JMESPATH"
    }
  }

  request_protection {
    rules {
      action_name = "ForbiddenAction"
      name = "builtin HTTP protections"
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
      protection_capabilities {
        key = "921150, 921160"  ## argument newline detection
        version = "2"
      }
      protection_capabilities {
        key = "921151"  ## GET newline detection
        version = "1"
      }
      type = "PROTECTION"  # ACCESS_CONTROL', 'PROTECTION', or 'REQUEST_RATE_LIMITING'
      is_body_inspection_enabled = "true"

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
