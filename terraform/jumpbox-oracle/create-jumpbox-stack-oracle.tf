variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "subnet_ocid" {}
variable "security_group_ocid" {}
variable "user" {}
variable "user_private_key_path" {}
variable "user_public_key_path" {}
variable "image_ocid" {}
variable "oracle_region" {}
variable "environment" {}
variable "environment_type" {}
variable "display_name" {}
variable "shape" {}
variable "availability_domain" {}
variable "git_branch" {}
variable "name" {}
variable "domain" {}
variable "tag_namespace" {}
variable "ocpus" {}
variable "memory_in_gbs" {}
variable "dns_compartment_ocid" {}
variable "dns_name" {}
variable "dns_zone_name" {}
variable "infra_configuration_repo" {}
variable "infra_customizations_repo" {}
variable "user_data_lib_path" {
  default = "terraform/lib"
}
variable "user_data_file" {
    default = "terraform/jumpbox-oracle/configure-jumpbox-local-oracle.sh"
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

resource "oci_core_instance" "oci-instance" {
    availability_domain = var.availability_domain
    compartment_id = var.compartment_ocid
    shape = var.shape
    shape_config {
        memory_in_gbs = var.memory_in_gbs
        ocpus = var.ocpus
    }

    display_name = var.display_name

    create_vnic_details {
        assign_public_ip = false
        subnet_id = var.subnet_ocid
        nsg_ids = [
            var.security_group_ocid]
    }

    source_details {
        source_type = "image"
        source_id = var.image_ocid
    }

    defined_tags = {
        "${var.tag_namespace}.environment" = var.environment
        "${var.tag_namespace}.environment_type" = var.environment_type
        "${var.tag_namespace}.git_branch" = var.git_branch
        "${var.tag_namespace}.domain" = var.domain
        "${var.tag_namespace}.shard-role" = "ssh"
        "${var.tag_namespace}.Name" = var.name
     }
    freeform_tags = {
        configuration_repo = var.infra_configuration_repo
        customizations_repo = var.infra_customizations_repo
        shape = var.shape
    }

    metadata = {
        ssh_authorized_keys = file(var.user_public_key_path)
    }

    provisioner "file" {
        connection {
            type        = "ssh"
            host        = oci_core_instance.oci-instance.public_ip
            user        = var.user
            private_key = file(var.user_private_key_path)
        }

        content = join("",[
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-header.sh"), # load the header
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-lib.sh"), # load the lib
          "\nINFRA_CONFIGURATION_REPO=${var.infra_configuration_repo}\nINFRA_CUSTOMIZATIONS_REPO=${var.infra_customizations_repo}\n", #repo variables
          file("${path.cwd}/${var.user_data_file}"), # load our customizations
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-footer.sh") # load the footer
        ])      
        destination = "/tmp/configure-jumpbox-local-oracle.sh"
    }


    provisioner "remote-exec" {
        connection {
            type        = "ssh"
            host        = oci_core_instance.oci-instance.public_ip
            user        = var.user
            private_key = file(var.user_private_key_path)
            script_path = "/home/${var.user}/script_%RAND%.sh"
        }

        inline = [
            "sudo cp /tmp/configure-jumpbox-local-oracle.sh /usr/local/bin/configure-jumpbox-local-oracle.sh",
            "sudo chmod +x /usr/local/bin/configure-jumpbox-local-oracle.sh",
            "sudo /usr/local/bin/configure-jumpbox-local-oracle.sh"
        ]
    }

}

resource "oci_dns_rrset" "jumpbox_dns" {
    compartment_id = var.dns_compartment_ocid
    zone_name_or_id = var.dns_zone_name
    domain = var.dns_name
    rtype = "A"
    items {
        domain = var.dns_name
        rtype = "A"
        ttl = "60"
        rdata = oci_core_instance.oci-instance.public_ip
    }
}
