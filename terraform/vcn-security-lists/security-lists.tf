variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "oracle_region" {}
variable "environment" {}
variable "resource_name_root" {}
variable "ops_peer_cidrs" {
  type = list(string)
}
variable "vcn_name" {}

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
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}

data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

// ============ SECURITY LISTS ============

resource "oci_core_security_list" "private_security_list" {
    compartment_id = var.compartment_ocid
    vcn_id         = data.oci_core_vcns.vcns.virtual_networks[0].id
    display_name   = "${var.resource_name_root}-PrivateSecurityList"

    // allow outbound traffic on all ports
    egress_security_rules {
        destination = "0.0.0.0/0"
        destination_type = "CIDR_BLOCK"
        stateless = false
        protocol    = "all"
        description = "allow outbound traffic on all ports"
    }

    egress_security_rules {
        destination = lookup(data.oci_core_services.all_services.services[0], "cidr_block")
        destination_type = "SERVICE_CIDR_BLOCK"
        protocol    = "all"
        stateless = false
        description = "allow outbound traffic to Oracle Services Network"
    }

    // allow inbound ssh traffic from the internal network
    ingress_security_rules {
        protocol  = "6"         // tcp
        source    = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
        source_type = "CIDR_BLOCK"
        stateless = false
        description = "allow inbound ssh traffic from the internal network"

        tcp_options {
            // These values correspond to the destination port range.
            min = 22
            max = 22
        }
    }

    // allow inbound ssh traffic from ops networks
    dynamic "ingress_security_rules" {
      for_each = toset(var.ops_peer_cidrs)
      content {
        protocol  = "6"         // tcp
        source    = ingress_security_rules.value
        source_type = "CIDR_BLOCK"
        stateless = false
        description = "allow inbound ssh traffic from ops networks"
        tcp_options {
            min = 22
            max = 22
        }
      }
    }

    ingress_security_rules {
        description = "external inbound icmp traffic"
        protocol    = 1     // icmp
        source      = "0.0.0.0/0"
        source_type = "CIDR_BLOCK"
        stateless   = false

        icmp_options {
            type = 3
            code = 4
        }
    }

    ingress_security_rules {
        description = "internal inbound icmp traffic"
        protocol    = 1       //icmp
        source      = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
        source_type = "CIDR_BLOCK"
        stateless   = false

        icmp_options {
            type = 3
        }
    }

    // allow consul TCP gossip traffic internally
    ingress_security_rules {
        protocol  = "6"         // tcp
        source    = "10.0.0.0/8"
        source_type = "CIDR_BLOCK"
        stateless = false
        description = "allow consul TCP gossip traffic internally"

        tcp_options {
            min = 8301
            max = 8301
        }
    }

    // allow consul UDP gossip traffic internally
    ingress_security_rules {
        protocol  = "17"         // udp
        source    = "10.0.0.0/8"
        source_type = "CIDR_BLOCK"
        stateless = false
        description = "allow consul UDP gossip traffic internally"

        udp_options {
            min = 8301
            max = 8301
        }
    }

    // allow consul http traffic internally
    ingress_security_rules {
        protocol  = "6"         // tcp
        source    = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
        source_type = "CIDR_BLOCK"
        stateless = false
        description = "allow telegraf scrapes"

        tcp_options {
            min = 9126
            max = 9126
        }
    }

}
