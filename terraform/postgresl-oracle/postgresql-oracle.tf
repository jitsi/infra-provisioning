
# compartment OCID - Replace these values

variable "compartment_ocid" {
  description = "Compartment ID where to create resources for Requestor Tenancy"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment"
  type = string
}

variable "vcn_name" {
  description = "VCN Name"
  type = string
}

variable "tenancy_ocid" {
  description = "Tenancy ID where to create resources for Requestor Tenancy"
  type        = string
  default     = ""
}

variable "tag_namespace" {
    description = "Tag Namespace"
    type = string
    default = "jitsi"
}

variable "oracle_region" {}
variable "subnet_ocid" {}

variable "db_system_db_version" {
  description = "Version"
  type = number
  default = 14
}

variable "db_system_display_name" {
  description = "nomad psql db system name"
  type = string
  default = "nomadpsql" # example value
}


variable "db_system_shape" {
    description = "shape"
    type = string
    default = "PostgreSQL.VM.Standard.E5.Flex"  # example value
    #change the shape value as per your requirements
}

variable "db_system_instance_count" {
  description = "instance count"
  type = number
  default = 1  # example value
}

variable "db_system_instance_memory_size_in_gbs" {
  description = "RAM"
  type = number
  default = 32  # example value
}

variable "db_system_instance_ocpu_count" {
  description = "OCPU count"
  type = number
  default = 2  # example value
}

variable "db_system_storage_details_is_regionally_durable" {
  description = "regional"
  type = bool
  default = true
}

variable "db_system_credentials_password_details_password" {
  description = "password"
  type = string
  default = ""
}

variable "db_system_credentials_username" {
  description = "username"
  type = string
  default = "admin" # example value
}

variable "db_system_storage_details_system_type" {
  description = "type"
  type = string
  default = "OCI_OPTIMIZED_STORAGE"
  
}

variable "vault_id" {
  description = "Vault ID"
  type = string
}

variable "key_protection_mode" {
  type        = string
  default     = "HSM"
  description = "Key protection mode SOFTWARE or HSM"
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

locals {
    common_tags = {
        "${var.tag_namespace}.environment" = var.environment
        "${var.tag_namespace}.shard-role" = "nomad-general-vault"
    }
}


data "oci_core_vcns" "vcns" {
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}

data "oci_kms_vault" "vault" {
    vault_id = var.vault_id
}

resource "oci_core_network_security_group" "postgresql_security_group" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.environment}-Postgresql"
}

resource "oci_core_network_security_group_security_rule" "postgresql_nsg_rule_egress" {
  network_security_group_id = oci_core_network_security_group.postgresql_security_group.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

resource "oci_core_network_security_group_security_rule" "postgresql_nsg_rule_ingress_local_vcn" {
  network_security_group_id = oci_core_network_security_group.postgresql_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 5432
      min = 5432
    }
  }
}


resource "oci_identity_policy" "psql_secrets_policy" {
  compartment_id = var.compartment_ocid
  description    = "Policy to allow DB management service to read secret-family for mentioned compartment"
  name           = "${var.environment}-psql-secrets-policy"
  statements     = ["Allow service dpd to read secret-family in compartment id ${var.compartment_ocid}"]
  defined_tags   = local.common_tags
}

resource "oci_kms_key" "psql_key" {
  depends_on = [ data.oci_kms_vault.vault ]

  compartment_id = var.compartment_ocid
  display_name   = "${var.environment}-psql-key"
  key_shape {
    algorithm = "AES"
    length    = 32
  }
  management_endpoint = data.oci_kms_vault.vault.management_endpoint

  defined_tags   = local.common_tags
  protection_mode = var.key_protection_mode
}

resource "random_password" "psql_admin_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "oci_vault_secret" "psql_secret" {
  compartment_id = var.compartment_ocid
  
  secret_content {
    #Required
    content_type = "BASE64"

    #Optional
    content = base64encode(coalesce(var.db_system_credentials_password_details_password, random_password.psql_admin_password.result))
    name    = "psql_secret"
    stage   = "CURRENT"
  }

  secret_name    = "psql_nomad_secret"

  freeform_tags = {
  }
  defined_tags = local.common_tags
  key_id = oci_kms_key.psql_key.id
  metadata = {
  }
  vault_id  = var.vault_id

  lifecycle {
    ignore_changes = [secret_content]
  }
  
}

resource "oci_psql_db_system" "nomad_psql_db_system" {
    #Required
    compartment_id = var.compartment_ocid
    db_version = var.db_system_db_version
    display_name = var.db_system_display_name
    network_details {
        #Required
        subnet_id = var.subnet_ocid
        #Optional
        nsg_ids = [oci_core_network_security_group.postgresql_security_group.id]
    }
    shape = var.db_system_shape
    storage_details {
        #Required
        is_regionally_durable = var.db_system_storage_details_is_regionally_durable
        system_type = var.db_system_storage_details_system_type
        #Optional
        # availability_domain = var.db_system_storage_details_availability_domain
        # iops = var.db_system_storage_details_iops
    }
    credentials {
        #Required
        password_details {
            #Required
            password_type = "VAULT_SECRET"
            #Optional
            secret_id = oci_vault_secret.psql_secret.id

        }
        username = var.db_system_credentials_username
    }
    instance_count = var.db_system_instance_count
    instance_memory_size_in_gbs = var.db_system_instance_memory_size_in_gbs
    instance_ocpu_count = var.db_system_instance_ocpu_count

}
