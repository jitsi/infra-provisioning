variable "resource_name_root" {}
variable "vcn_name" {}
variable "oracle_region" {}
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

data "oci_core_vcns" "vcns" {
  compartment_ocid = var.compartment_ocid
  display_name = var.vcn_name
}

resource "oci_core_network_security_group" "emqx_lb_security_group" {
  compartment_ocid = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-LB-SecurityGroup"
}

# Egress - allow all outbound
resource "oci_core_network_security_group_security_rule" "emqx_lb_nsg_rule_egress" {
  network_security_group_id = oci_core_network_security_group.emqx_lb_security_group.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

# Ingress - MQTT TCP (port 1883)
resource "oci_core_network_security_group_security_rule" "emqx_lb_nsg_rule_mqtt" {
  network_security_group_id = oci_core_network_security_group.emqx_lb_security_group.id
  direction = "INGRESS"
  protocol = "6"  # TCP
  source = "0.0.0.0/0"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 1883
      min = 1883
    }
  }
}

# Ingress - MQTTS/TLS (port 8883)
resource "oci_core_network_security_group_security_rule" "emqx_lb_nsg_rule_mqtts" {
  network_security_group_id = oci_core_network_security_group.emqx_lb_security_group.id
  direction = "INGRESS"
  protocol = "6"  # TCP
  source = "0.0.0.0/0"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 8883
      min = 8883
    }
  }
}

# Ingress - WebSocket (port 8083)
resource "oci_core_network_security_group_security_rule" "emqx_lb_nsg_rule_ws" {
  network_security_group_id = oci_core_network_security_group.emqx_lb_security_group.id
  direction = "INGRESS"
  protocol = "6"  # TCP
  source = "0.0.0.0/0"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 8083
      min = 8083
    }
  }
}

# Ingress - WebSocket Secure (port 8084)
resource "oci_core_network_security_group_security_rule" "emqx_lb_nsg_rule_wss" {
  network_security_group_id = oci_core_network_security_group.emqx_lb_security_group.id
  direction = "INGRESS"
  protocol = "6"  # TCP
  source = "0.0.0.0/0"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 8084
      min = 8084
    }
  }
}

output "security_group_id" {
  value = oci_core_network_security_group.emqx_lb_security_group.id
}
