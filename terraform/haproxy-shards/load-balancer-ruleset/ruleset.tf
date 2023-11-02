variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "oci_load_balancer_id" {}
variable "oci_load_balancer_bs_name" {}
variable "oci_load_balancer_redirect_rule_set_name" {}

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

resource "oci_load_balancer_rule_set" "redirect_rule_set" {
    items {
        action = "REDIRECT"

        conditions {
            attribute_name = "PATH"
            attribute_value = "/"
            operator = "PREFIX_MATCH"
        }
        description = "redirect http to https"
        redirect_uri {
            host = "{host}"
            path = "{path}"
            port = 443
            protocol = "https"
            query = "{query}"
        }
        response_code = 301
    }
    load_balancer_id = var.oci_load_balancer_id
    name = var.oci_load_balancer_redirect_rule_set_name
}

resource "oci_load_balancer_listener" "redirect_listener" {
  load_balancer_id = var.oci_load_balancer_id
  name = "HAProxyHTTPListener"
  port = 80
  default_backend_set_name = var.oci_load_balancer_bs_name
  rule_set_names = [var.oci_load_balancer_redirect_rule_set_name]
  protocol = "HTTP"
  depends_on = [oci_load_balancer_rule_set.redirect_rule_set]
}