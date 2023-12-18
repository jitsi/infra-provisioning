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
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}

resource "oci_core_network_security_group" "security_group_hub" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-HubSecurityGroup"
}

resource "oci_core_network_security_group" "security_group_node" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-NodeSecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_egress_hub" {
  network_security_group_id = oci_core_network_security_group.security_group_hub.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_egress_node" {
  network_security_group_id = oci_core_network_security_group.security_group_node.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_hub_ssh" {
  network_security_group_id = oci_core_network_security_group.security_group_hub.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 22
      min = 22
    }
  }
}


resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_node_ssh" {
  network_security_group_id = oci_core_network_security_group.security_group_node.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 22
      min = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_hub_grid" {
  network_security_group_id = oci_core_network_security_group.security_group_hub.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 4444
      min = 4444
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_hub_nodes" {
  network_security_group_id = oci_core_network_security_group.security_group_hub.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 3000
      min = 3000
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_nodes_main" {
  network_security_group_id = oci_core_network_security_group.security_group_node.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 5000
      min = 5000
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_hub_to_node" {
  network_security_group_id = oci_core_network_security_group.security_group_node.id
  direction = "INGRESS"
  protocol = "6"
  source = oci_core_network_security_group.security_group_hub.id
  source_type = "NETWORK_SECURITY_GROUP"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 5555
      min = 5555
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_hub_to_node_xtras" {
  network_security_group_id = oci_core_network_security_group.security_group_node.id
  direction = "INGRESS"
  protocol = "6"
  source = oci_core_network_security_group.security_group_hub.id
  source_type = "NETWORK_SECURITY_GROUP"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 3000
      min = 3000
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_nomad_ephemeral_tcp" {
  network_security_group_id = oci_core_network_security_group.security_group_node.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      min = 20000
      max = 32000
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_nomad_ephemeral_udp" {
  network_security_group_id = oci_core_network_security_group.security_group_node.id
  direction = "INGRESS"
  protocol = "17"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  udp_options {
    destination_port_range {
      min = 20000
      max = 32000
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_telegraf_prometheus_tcp" {
  network_security_group_id = oci_core_network_security_group.security_group_node.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 9126
      min = 9126
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_consul_serf_tcp" {
  network_security_group_id = oci_core_network_security_group.security_group_node.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 8301
      min = 8301
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_consul_serf_udp" {
  network_security_group_id = oci_core_network_security_group.security_group_node.id
  direction = "INGRESS"
  protocol = "17"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  udp_options {
    destination_port_range {
      min = 8301
      max = 8301
    }
  }
}
