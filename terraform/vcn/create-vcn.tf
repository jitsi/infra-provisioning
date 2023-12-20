variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "oracle_region" {}
variable "environment" {}
variable "vcn_cidr" {}
variable "public_subnet_cidr" {}
variable "jvb_subnet_cidr" {}
variable "ops_peer_cidrs" {
  type = list(string)
}
variable "vcn_name" {}
variable "vcn_dns_label" {}
variable "resource_name_root" {}

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

// ============ VCN ============

resource "oci_core_vcn" "vcn" {
  cidr_block     = var.vcn_cidr
  compartment_id = var.compartment_ocid
  display_name   = var.vcn_name
  dns_label      = var.vcn_dns_label
}


resource "oci_core_internet_gateway" "internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "Internet Gateway ${oci_core_vcn.vcn.display_name}"
  vcn_id         = oci_core_vcn.vcn.id
}

data "oci_core_services" "object_storage_services" {
  filter {
    name   = "name"
    values = ["OCI .* Object Storage"]
    regex  = true
  }
}

data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "service_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id = oci_core_vcn.vcn.id
  display_name   = "Service Gateway ${oci_core_vcn.vcn.display_name}"

  services {
    service_id = lookup(data.oci_core_services.all_services.services[0], "id")
  }
}

resource "oci_core_route_table" "route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "Route Table ${oci_core_vcn.vcn.display_name}"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.internet_gateway.id
  }

  route_rules {
    destination       = lookup(data.oci_core_services.object_storage_services.services[0], "cidr_block")
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.service_gateway.id
  }
}

// ============ SECURITY LISTS ============

resource "oci_core_security_list" "private_security_list" {
    compartment_id = var.compartment_ocid
    vcn_id         = oci_core_vcn.vcn.id
    display_name   = "${var.resource_name_root}-PrivateSecurityList"

    // allow outbound traffic on all ports
    egress_security_rules {
        destination = "0.0.0.0/0"
        protocol    = "all"
        description = "allow outbound traffic on all ports"
    }

    egress_security_rules {
        destination = lookup(data.oci_core_services.all_services.services[0], "cidr_block")
        destination_type = "SERVICE_CIDR_BLOCK"
        protocol    = "all"
    }

    // allow inbound ssh traffic from the internal network
    ingress_security_rules {
        protocol  = "6"         // tcp
        source    = var.vcn_cidr
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
        stateless = false
        description = "allow inbound ssh traffic from ops networks"
        tcp_options {
            min = 22
            max = 22
        }
      }
    }

    ingress_security_rules {
        protocol    = 1     // icmp
        source      = "0.0.0.0/0"
        stateless   = false

        icmp_options {
            type = 3
            code = 4
        }
    }

    ingress_security_rules {
        protocol    = 1       //icmp
        source      = var.vcn_cidr
        stateless   = false

        icmp_options {
            type = 3
        }
    }

    // allow consul TCP gossip traffic internally
    ingress_security_rules {
        protocol  = "6"         // tcp
        source    = "10.0.0.0/8"
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
        source    = var.vcn_cidr
        stateless = false
        description = "allow telegraf scrapes"

        tcp_options {
            min = 9126
            max = 9126
        }
    }

}


// ============ NETWORKS SECURITY GROUPS ============

resource "oci_core_network_security_group" "public_network_security_group" {
    compartment_id = var.compartment_ocid
    vcn_id         = oci_core_vcn.vcn.id
    display_name   = "${var.resource_name_root}-PublicSecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "public_network_security_group_security_rule_1" {
    network_security_group_id = oci_core_network_security_group.public_network_security_group.id
    direction                 = "EGRESS"
    destination               = "0.0.0.0/0"
    protocol                  = "all"
}

resource "oci_core_network_security_group_security_rule" "public_network_security_group_security_rule_2" {
    network_security_group_id = oci_core_network_security_group.public_network_security_group.id
    protocol                  = "6"   //tcp
    direction                 = "INGRESS"
    source                    = "0.0.0.0/0"
    stateless                 = false

    tcp_options {
        destination_port_range {
          min = 22
          max = 22
        }
    }
}

resource "oci_core_network_security_group" "jvb_network_security_group" {
    compartment_id = var.compartment_ocid
    vcn_id         = oci_core_vcn.vcn.id
    display_name   = "${var.resource_name_root}-JVBSecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "jvb_network_security_group_security_rule_1" {
    network_security_group_id = oci_core_network_security_group.jvb_network_security_group.id
    direction                 = "EGRESS"
    destination               = "0.0.0.0/0"
    protocol                  = "all"
}

resource "oci_core_network_security_group_security_rule" "jvb_network_security_group_security_rule_2" {
    network_security_group_id = oci_core_network_security_group.jvb_network_security_group.id
    protocol                  = "6"   //tcp
    direction                 = "INGRESS"
    source                    = var.vcn_cidr
    stateless                 = false

    tcp_options {
        destination_port_range {
          min = 22
          max = 22
        }
    }
}

resource "oci_core_network_security_group_security_rule" "jvb_network_security_group_security_rule_3" {
    network_security_group_id = oci_core_network_security_group.jvb_network_security_group.id
    protocol                  = "6"   //tcp
    direction                 = "INGRESS"
    source                    = "0.0.0.0/0"
    stateless                 = false

    tcp_options {
        destination_port_range {
          min = 443
          max = 443
        }
    }
}

resource "oci_core_network_security_group_security_rule" "jvb_network_security_group_security_rule_4" {
    network_security_group_id = oci_core_network_security_group.jvb_network_security_group.id
    protocol                  = "17"   //udp
    direction                 = "INGRESS"
    source                    = "0.0.0.0/0"
    stateless                 = false

    udp_options {
        destination_port_range {
          min = 10000
          max = 10000
        }
    }
}



// ============ SUBNETS ============

resource "oci_core_subnet" "public_subnet" {
  depends_on          = [oci_core_network_security_group.public_network_security_group, oci_core_security_list.private_security_list]
  cidr_block          = var.public_subnet_cidr
  display_name        = "${var.resource_name_root}-PublicSubnet1"
  dns_label           = "pubsubnet1"
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_vcn.vcn.id
  security_list_ids   = ["${oci_core_security_list.private_security_list.id}"]
  route_table_id      = oci_core_route_table.route_table.id
}

resource "oci_core_subnet" "jvb_subnet" {
  depends_on          = [oci_core_network_security_group.jvb_network_security_group, oci_core_security_list.private_security_list]
  cidr_block          = var.jvb_subnet_cidr
  display_name        = "${var.resource_name_root}-JVBSubnet64"
  dns_label           = "jvbsubnet64"
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_vcn.vcn.id
  security_list_ids   = ["${oci_core_security_list.private_security_list.id}"]
  route_table_id      = oci_core_route_table.route_table.id
}

// ============ OUTPUTS ============

output "vcn_name" {
  value = oci_core_vcn.vcn.display_name
}

output "route_table_name" {
  value = oci_core_route_table.route_table.display_name
}

output "internet_gateway_name" {
  value = oci_core_internet_gateway.internet_gateway.display_name
}

output "public_security_list_name" {
  value = oci_core_security_list.public_security_list.display_name
}

output "private_security_list_name" {
  value = oci_core_security_list.private_security_list.display_name
}

output "public_network_security_group_name" {
  value = oci_core_network_security_group.public_network_security_group.display_name
}

output "jvb_network_security_group_name" {
  value = oci_core_network_security_group.jvb_network_security_group.display_name
}

output "public_subnet_name" {
  value = oci_core_subnet.public_subnet.display_name
}

output "jvb_subnet_name" {
  value = oci_core_subnet.jvb_subnet.display_name
}