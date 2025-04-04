variable "environment" {}
variable "oracle_region" {}
variable "shape" {}
variable "availability_domains" {
  type = list(string)
}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "vcn_name" {}
variable "subnet_ocid" {}
variable "image_ocid" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "user" {}
variable "user_private_key_path" {}
variable "user_public_key_path" {}
variable "ingress_nsg_cidr" {
    default = "0.0.0.0/0"
}
variable "instance_display_name" {}
variable "instance_shape_config_memory_in_gbs" {}
variable "instance_shape_config_ocpus" {}
variable "postinstall_status_file" {}
variable "disk_in_gbs" {}
variable "user_data_lib_path" {
  default = "terraform/lib"
}
variable "user_data_file" {
  default = "terraform/iperf-server/user-data/postinstall-runner-oracle.sh"
}
variable "infra_configuration_repo" {}
variable "infra_customizations_repo" {}

locals {
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.environment_type" = var.environment_type
    "${var.tag_namespace}.role" = "iperf"
    "${var.tag_namespace}.shard-role" = "iperf"
    "${var.tag_namespace}.Name" = "${var.environment}-${var.oracle_region}-iperf"
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

resource "oci_core_network_security_group" "instance_security_group" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.environment}-${var.oracle_region}-iperf-SecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "instance_nsg_rule_egress" {
  network_security_group_id = oci_core_network_security_group.instance_security_group.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

# TCP Ingress for nginx server
resource "oci_core_network_security_group_security_rule" "instance_nsg_rule_ingress_tcp" {
  network_security_group_id = oci_core_network_security_group.instance_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = var.ingress_nsg_cidr
  stateless = false

  tcp_options {
    destination_port_range {
      max = 5201
      min = 5201
    }
  }
}

# TCP Ingress for iperf server
resource "oci_core_network_security_group_security_rule" "instance_nsg_rule_ingress_udp" {
  network_security_group_id = oci_core_network_security_group.instance_security_group.id
  direction = "INGRESS"
  protocol = "17"
  source = var.ingress_nsg_cidr
  stateless = false

  udp_options {
    destination_port_range {
      max = 5201
      min = 5201
    }
  }
}

resource "oci_core_instance" "instance" {
    #Required
    availability_domain = var.availability_domains[0]
    compartment_id = var.compartment_ocid
    shape = var.shape

    create_vnic_details {
        subnet_id = var.subnet_ocid
        nsg_ids = [oci_core_network_security_group.instance_security_group.id]
        assign_public_ip = true
    }

    source_details {
        source_type = "image"
        source_id = var.image_ocid
        # Apply this to set the size of the boot volume that's created for this instance.
        # Otherwise, the default boot volume size of the image is used.
        # This should only be specified when source_type is set to "image".
        boot_volume_size_in_gbs = var.disk_in_gbs
    }

    metadata = {
        user_data = base64encode(join("",[
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-header.sh"), # load the header
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-lib.sh"), # load the lib
          file("${path.cwd}/${var.user_data_file}"), # load our customizations
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-footer.sh") # load the footer
        ]))
        ssh_authorized_keys = file(var.user_public_key_path)
    }

    defined_tags = local.common_tags

    freeform_tags = {
      configuration_repo = var.infra_configuration_repo
      customizations_repo = var.infra_customizations_repo
      shape = var.shape
    }

    display_name = var.instance_display_name

    shape_config {
        #Optional
        memory_in_gbs = var.instance_shape_config_memory_in_gbs
        ocpus = var.instance_shape_config_ocpus
    }

    preserve_boot_volume = false
}


locals {
  private_ip = oci_core_instance.instance.private_ip
  public_ip = oci_core_instance.instance.public_ip
}

resource "null_resource" "verify_cloud_init" {
  count = 1
  depends_on = [oci_core_instance.instance]
  
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
      type = "ssh"
      host = local.private_ip
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

resource "null_resource" "cloud_init_output" {
  count = 1
  depends_on = [null_resource.verify_cloud_init]

  provisioner "local-exec" {
    command = "ssh -i \"${var.user_private_key_path}\" -o StrictHostKeyChecking=no ${var.user}@${local.private_ip} 'echo hostname: $HOSTNAME, privateIp: ${local.private_ip} - $(cloud-init status)' >> ${var.postinstall_status_file}"
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}

output "private_ip" {
  value = local.private_ip
}

output "public_ip" {
  value = local.public_ip
}

