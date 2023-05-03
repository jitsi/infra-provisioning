variable "environment" {}
variable "name" {}
variable "oracle_region" {}
variable "shape" {}
variable "availability_domains" {
  type = list(string)
}
variable "role" {}
variable "git_branch" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "vcn_name" {}
variable "resource_name_root" {}
variable "load_balancer_shape" {
  default = "flexible"
}
variable load_balancer_shape_details_maximum_bandwidth_in_mbps {
  default = "100"
}
variable load_balancer_shape_details_minimum_bandwidth_in_mbps {
  default = "10"
}
variable "subnet_ocid" {}
variable "image_ocid" {}
variable "instance_pool_size" {}
variable "instance_pool_name" {}
variable "instance_config_name" {}
variable "dns_name" {}
variable "dns_zone_name" {}
variable "dns_compartment_ocid" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "user" {}
variable "user_private_key_path" {}
variable "user_public_key_path" {}
variable "postinstall_status_file" {}
variable "memory_in_gbs" {}
variable "ocpus" {}
variable "ingress_cidr" {}
variable "certificate_certificate_name" {}
variable "certificate_ca_certificate" {}
variable "certificate_private_key" {}
variable "certificate_public_certificate" {}
variable "user_data_file" {
  default = "terraform/consul-server/user-data/postinstall-runner-oracle.sh"
}
variable "user_data_lib_path" {
  default = "terraform/lib"
}
variable "infra_configuration_repo" {}
variable "infra_customizations_repo" {}

locals {
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.environment_type" = var.environment_type
    "${var.tag_namespace}.git_branch" = var.git_branch
    "${var.tag_namespace}.role" = var.role
    "${var.tag_namespace}.Name" = var.name
  }
  common_metadata = {
      user_data = base64encode(join("",[
        file("${path.cwd}/${var.user_data_lib_path}/postinstall-header.sh"), # load the header
        file("${path.cwd}/${var.user_data_lib_path}/postinstall-lib.sh"), # load the lib
        "\nexport INFRA_CONFIGURATION_REPO=${var.infra_configuration_repo}\nexport INFRA_CUSTOMIZATIONS_REPO=${var.infra_customizations_repo}\n", #repo variables
        file("${path.cwd}/${var.user_data_file}"), # load our customizations
        file("${path.cwd}/${var.user_data_lib_path}/postinstall-footer.sh") # load the footer
      ]))
      ssh_authorized_keys = file(var.user_public_key_path)
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

data "oci_core_vcns" "vcns" {
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}

resource "oci_core_network_security_group" "consul_security_group" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-SecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "consul_nsg_rule_egress" {
  network_security_group_id = oci_core_network_security_group.consul_security_group.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

resource "oci_core_network_security_group_security_rule" "consul_nsg_rule_ingress_consul_web" {
  network_security_group_id = oci_core_network_security_group.consul_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = var.ingress_cidr
  stateless = false

  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "consul_nsg_rule_ingress_ssh" {
  network_security_group_id = oci_core_network_security_group.consul_security_group.id
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

resource "oci_core_network_security_group_security_rule" "consul_nsg_rule_ingress_consul_http" {
  network_security_group_id = oci_core_network_security_group.consul_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = var.ingress_cidr
  stateless = false

  tcp_options {
    destination_port_range {
      max = 8502
      min = 8500
    }
  }
}

resource "oci_core_network_security_group_security_rule" "consul_nsg_rule_ingress_consul_server" {
  network_security_group_id = oci_core_network_security_group.consul_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = var.ingress_cidr
  stateless = false

  tcp_options {
    destination_port_range {
      max = 8300
      min = 8300
    }
  }
}

resource "oci_core_network_security_group_security_rule" "consul_nsg_rule_ingress_consul_dns_tcp" {
  network_security_group_id = oci_core_network_security_group.consul_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = var.ingress_cidr
  stateless = false

  tcp_options {
    destination_port_range {
      max = 8600
      min = 8600
    }
  }
}

resource "oci_core_network_security_group_security_rule" "consul_nsg_rule_ingress_consul_serf_lan_wan" {
  network_security_group_id = oci_core_network_security_group.consul_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = var.ingress_cidr
  stateless = false

  tcp_options {
    destination_port_range {
      min = 8300
      max = 8302
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_nomad_tcp" {
  network_security_group_id = oci_core_network_security_group.consul_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "10.0.0.0/8"
  stateless = false

  tcp_options {
    destination_port_range {
      min = 4646
      max = 4648
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nsg_rule_ingress_nomad_udp" {
  network_security_group_id = oci_core_network_security_group.consul_security_group.id
  direction = "INGRESS"
  protocol = "17"
  source = "10.0.0.0/8"
  stateless = false

  udp_options {
    destination_port_range {
      min = 4648
      max = 4648
    }
  }
}


resource "oci_core_network_security_group_security_rule" "consul_nsg_rule_ingress_consul_dns_udp" {
  network_security_group_id = oci_core_network_security_group.consul_security_group.id
  direction = "INGRESS"
  protocol = "17"
  source = var.ingress_cidr
  stateless = false

  udp_options {
    destination_port_range {
      max = 8600
      min = 8600
    }
  }
}

resource "oci_core_network_security_group_security_rule" "consul_nsg_rule_ingress_consul_serf_lan_wan_udp" {
  network_security_group_id = oci_core_network_security_group.consul_security_group.id
  direction = "INGRESS"
  protocol = "17"
  source = var.ingress_cidr
  stateless = false

  udp_options {
    destination_port_range {
      min = 8300
      max = 8302
    }
  }
}
resource "oci_core_instance_configuration" "oci_instance_configuration_a" {
  compartment_id = var.compartment_ocid
  display_name = var.instance_config_name

  lifecycle {
      create_before_destroy = true
  }

  defined_tags = local.common_tags

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id = var.compartment_ocid
      shape = var.shape


      shape_config {
        memory_in_gbs = var.memory_in_gbs
        ocpus = var.ocpus
      }

      create_vnic_details {
        subnet_id = var.subnet_ocid
        nsg_ids = [oci_core_network_security_group.consul_security_group.id]
      }

      source_details {
        source_type = "image"
        image_id = var.image_ocid
      }

      metadata = local.common_metadata
      freeform_tags = {
        configuration_repo = var.infra_configuration_repo
        customizations_repo = var.infra_customizations_repo
        shape = var.shape
      }
    }
  }
}

resource "oci_core_instance_configuration" "oci_instance_configuration_b" {
  compartment_id = var.compartment_ocid
  display_name = var.instance_config_name

  lifecycle {
      create_before_destroy = true
  }

  defined_tags = local.common_tags

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id = var.compartment_ocid
      shape = var.shape


      shape_config {
        memory_in_gbs = var.memory_in_gbs
        ocpus = var.ocpus
      }

      create_vnic_details {
        subnet_id = var.subnet_ocid
        nsg_ids = [oci_core_network_security_group.consul_security_group.id]
      }

      source_details {
        source_type = "image"
        image_id = var.image_ocid
      }

      metadata = local.common_metadata
    }
  }
}

resource "oci_core_instance_configuration" "oci_instance_configuration_c" {
  compartment_id = var.compartment_ocid
  display_name = var.instance_config_name

  lifecycle {
      create_before_destroy = true
  }

  defined_tags = local.common_tags

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id = var.compartment_ocid
      shape = var.shape


      shape_config {
        memory_in_gbs = var.memory_in_gbs
        ocpus = var.ocpus
      }

      create_vnic_details {
        subnet_id = var.subnet_ocid
        nsg_ids = [oci_core_network_security_group.consul_security_group.id]
      }

      source_details {
        source_type = "image"
        image_id = var.image_ocid
      }

      metadata = local.common_metadata
    }
  }
}

resource "oci_load_balancer" "oci_load_balancer" {
  compartment_id = var.compartment_ocid
  display_name = "${var.resource_name_root}-LoadBalancer"
  shape = var.load_balancer_shape
  subnet_ids = [var.subnet_ocid]

    shape_details {
        maximum_bandwidth_in_mbps = var.load_balancer_shape_details_maximum_bandwidth_in_mbps
        minimum_bandwidth_in_mbps = var.load_balancer_shape_details_minimum_bandwidth_in_mbps
    }

  defined_tags = local.common_tags
  is_private = true
  network_security_group_ids = [oci_core_network_security_group.consul_security_group.id]
}

resource "oci_load_balancer_backend_set" "oci_load_balancer_bs" {
  load_balancer_id = oci_load_balancer.oci_load_balancer.id
  name = "ConsulLBBS"
  policy = "ROUND_ROBIN"
  health_checker {
    protocol = "HTTP"
    port = 8500
    retries = 3
    url_path = "/"
  }
}

resource "oci_load_balancer_certificate" "main_certificate" {
    #Required
    certificate_name = var.certificate_certificate_name
    load_balancer_id = oci_load_balancer.oci_load_balancer.id

    ca_certificate = var.certificate_ca_certificate
    private_key = var.certificate_private_key
    public_certificate = var.certificate_public_certificate

    lifecycle {
        create_before_destroy = true
    }
}

resource "oci_load_balancer_listener" "main_listener" {
  load_balancer_id = oci_load_balancer.oci_load_balancer.id
  name = "WFProxyListener"
  port = 443
  default_backend_set_name = oci_load_balancer_backend_set.oci_load_balancer_bs.name
  protocol = "HTTP"
  ssl_configuration {
      #Optional
      certificate_name = oci_load_balancer_certificate.main_certificate.certificate_name
      verify_peer_certificate = false
  }
}

resource "oci_core_instance_pool" "oci_instance_pool_a" {
  compartment_id = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.oci_instance_configuration_a.id
  display_name = join("-", [var.instance_pool_name, "a"])
  size = var.instance_pool_size

  lifecycle {
    create_before_destroy = true
  }

  placement_configurations {
    primary_subnet_id = var.subnet_ocid
    availability_domain = var.availability_domains[0]
  }

  load_balancers {
    load_balancer_id = oci_load_balancer.oci_load_balancer.id
    backend_set_name = oci_load_balancer_backend_set.oci_load_balancer_bs.name
    port = 8500
    vnic_selection = "PrimaryVnic"
  }

  defined_tags = local.common_tags
}

resource "oci_core_instance_pool" "oci_instance_pool_b" {
  compartment_id = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.oci_instance_configuration_b.id
  display_name = join("-", [var.instance_pool_name, "b"])
  size = var.instance_pool_size

  lifecycle {
    create_before_destroy = true
  }

  placement_configurations {
    primary_subnet_id = var.subnet_ocid
    availability_domain = var.availability_domains[1 % length(var.availability_domains)]
  }

  load_balancers {
    load_balancer_id = oci_load_balancer.oci_load_balancer.id
    backend_set_name = oci_load_balancer_backend_set.oci_load_balancer_bs.name
    port = 8500
    vnic_selection = "PrimaryVnic"
  }

  defined_tags = local.common_tags
}

resource "oci_core_instance_pool" "oci_instance_pool_c" {
  compartment_id = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.oci_instance_configuration_c.id
  display_name = join("-", [var.instance_pool_name, "c"])
  size = var.instance_pool_size

  lifecycle {
    create_before_destroy = true
  }

  placement_configurations {
    primary_subnet_id = var.subnet_ocid
    availability_domain = var.availability_domains[2 % length(var.availability_domains)]
  }

  load_balancers {
    load_balancer_id = oci_load_balancer.oci_load_balancer.id
    backend_set_name = oci_load_balancer_backend_set.oci_load_balancer_bs.name
    port = 8500
    vnic_selection = "PrimaryVnic"
  }

  defined_tags = local.common_tags
}

data "oci_core_instance_pool_instances" "oci_instance_pool_instances_a" {
  compartment_id = var.compartment_ocid
  instance_pool_id = oci_core_instance_pool.oci_instance_pool_a.id
  depends_on = [oci_core_instance_pool.oci_instance_pool_a]
}
data "oci_core_instance_pool_instances" "oci_instance_pool_instances_b" {
  compartment_id = var.compartment_ocid
  instance_pool_id = oci_core_instance_pool.oci_instance_pool_b.id
  depends_on = [oci_core_instance_pool.oci_instance_pool_b]
}
data "oci_core_instance_pool_instances" "oci_instance_pool_instances_c" {
  compartment_id = var.compartment_ocid
  instance_pool_id = oci_core_instance_pool.oci_instance_pool_c.id
  depends_on = [oci_core_instance_pool.oci_instance_pool_c]
}

data "oci_core_instance" "oci_instance_datasources_a" {
  count = var.instance_pool_size
  instance_id = lookup(data.oci_core_instance_pool_instances.oci_instance_pool_instances_a.instances[count.index], "id")
}
data "oci_core_instance" "oci_instance_datasources_b" {
  count = var.instance_pool_size
  instance_id = lookup(data.oci_core_instance_pool_instances.oci_instance_pool_instances_b.instances[count.index], "id")
}
data "oci_core_instance" "oci_instance_datasources_c" {
  count = var.instance_pool_size
  instance_id = lookup(data.oci_core_instance_pool_instances.oci_instance_pool_instances_c.instances[count.index], "id")
}

locals {
  private_ips_a = data.oci_core_instance.oci_instance_datasources_a.*.private_ip
  private_ips_b = data.oci_core_instance.oci_instance_datasources_b.*.private_ip
  private_ips_c = data.oci_core_instance.oci_instance_datasources_c.*.private_ip
  lb_ip = oci_load_balancer.oci_load_balancer.ip_address_details[0].ip_address
}

resource "oci_dns_rrset" "consul_dns_record" {
  zone_name_or_id = var.dns_zone_name
  domain = var.dns_name
  rtype = "A"
  compartment_id = var.dns_compartment_ocid
  items {
    domain = var.dns_name
    rtype = "A"
    ttl = "60"
    rdata = oci_load_balancer.oci_load_balancer.ip_address_details[0].ip_address
   }
}

resource "oci_dns_rrset" "consul_dns_rrset_a" {
  compartment_id = var.dns_compartment_ocid
  zone_name_or_id = var.dns_zone_name
  domain = join(".",[join("-", [var.resource_name_root, "a"]),var.dns_zone_name])
  rtype = "A"
  items {
    domain = join(".",[join("-", [var.resource_name_root, "a"]),var.dns_zone_name])
    rtype = "A"
    ttl = "60"
    rdata = local.private_ips_a[0]
   }
}
resource "oci_dns_rrset" "consul_dns_rrset_b" {
  compartment_id = var.dns_compartment_ocid
  zone_name_or_id = var.dns_zone_name
  domain = join(".",[join("-", [var.resource_name_root, "b"]),var.dns_zone_name])
  rtype = "A"
  items {
    domain = join(".",[join("-", [var.resource_name_root, "b"]),var.dns_zone_name])
    rtype = "A"
    ttl = "60"
    rdata = local.private_ips_b[0]
   }
}
resource "oci_dns_rrset" "consul_dns_rrset_c" {
  compartment_id = var.dns_compartment_ocid
  zone_name_or_id = var.dns_zone_name
  domain = join(".",[join("-", [var.resource_name_root, "c"]),var.dns_zone_name])
  rtype = "A"
  items {
    domain = join(".",[join("-", [var.resource_name_root, "c"]),var.dns_zone_name])
    rtype = "A"
    ttl = "60"
    rdata = local.private_ips_c[0]
   }
}

resource "null_resource" "verify_cloud_init_a" {
  count = var.instance_pool_size
  depends_on = [data.oci_core_instance.oci_instance_datasources_a]

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
      type = "ssh"
      host = element(local.private_ips_a, count.index)
      user = var.user
      private_key = file(var.user_private_key_path)

      script_path = "/home/${var.user}/script_%RAND%.sh"

      timeout = "10m"
    }
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}
resource "null_resource" "cloud_init_output_a" {
  count = var.instance_pool_size
  depends_on = [null_resource.verify_cloud_init_a]

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no ${var.user}@${element(local.private_ips_a, count.index)} 'echo hostname: $HOSTNAME, privateIp: ${element(local.private_ips_a, count.index)} - $(cloud-init status)' >> ${var.postinstall_status_file}"
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}

resource "null_resource" "verify_cloud_init_b" {
  count = var.instance_pool_size
  depends_on = [data.oci_core_instance.oci_instance_datasources_b]

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
      type = "ssh"
      host = element(local.private_ips_b, count.index)
      user = var.user
      private_key = file(var.user_private_key_path)

      script_path = "/home/${var.user}/script_%RAND%.sh"

      timeout = "10m"
    }
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}
resource "null_resource" "cloud_init_output_b" {
  count = var.instance_pool_size
  depends_on = [null_resource.verify_cloud_init_b]

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no ${var.user}@${element(local.private_ips_b, count.index)} 'echo hostname: $HOSTNAME, privateIp: ${element(local.private_ips_b, count.index)} - $(cloud-init status)' >> ${var.postinstall_status_file}"
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}

resource "null_resource" "verify_cloud_init_c" {
  count = var.instance_pool_size
  depends_on = [data.oci_core_instance.oci_instance_datasources_c]

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
      type = "ssh"
      host = element(local.private_ips_c, count.index)
      user = var.user
      private_key = file(var.user_private_key_path)

      script_path = "/home/${var.user}/script_%RAND%.sh"

      timeout = "10m"
    }
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}
resource "null_resource" "cloud_init_output_c" {
  count = var.instance_pool_size
  depends_on = [null_resource.verify_cloud_init_c]

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no -J ${var.user}@${element(local.private_ips_c, count.index)} 'echo hostname: $HOSTNAME, privateIp: ${element(local.private_ips_c, count.index)} - $(cloud-init status)' >> ${var.postinstall_status_file}"
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}

output "private_ips_a" {
  value = local.private_ips_a
}
output "private_ips_b" {
  value = local.private_ips_b
}
output "private_ips_c" {
  value = local.private_ips_c
}
output "lb_ip" {
  value = local.lb_ip
}
output "lb_dns_name" {
  value = var.dns_name
}