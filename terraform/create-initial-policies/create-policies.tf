variable "tenancy_ocid" {}
variable "compartment_name" {}
variable "dynamic_group_name" {}
variable "policy_name" {}
variable "compartment_id" {}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
}

resource "oci_identity_policy" "policy" {
  name = var.policy_name
  description = "Allow users from ${var.dynamic_group_name} to use OCI resources within the compartment ${var.compartment_name}"
  compartment_id = var.compartment_id

  statements = [
    "Allow dynamic-group ${var.dynamic_group_name} to read virtual-network-family in compartment ${var.compartment_name}",
    "Allow dynamic-group ${var.dynamic_group_name} to manage instance-family in compartment ${var.compartment_name}",
    "Allow dynamic-group ${var.dynamic_group_name} to read objects in compartment ${var.compartment_name} where target.bucket.name='jvb-bucket-${var.compartment_name}'",
    "Allow dynamic-group ${var.dynamic_group_name} to manage objects in compartment ${var.compartment_name} where target.bucket.name='jvb-dump-logs-${var.compartment_name}'",
    "Allow dynamic-group ${var.dynamic_group_name} to manage objects in compartment ${var.compartment_name} where target.bucket.name='dump-logs-${var.compartment_name}'",
    "Allow dynamic-group ${var.dynamic_group_name} to manage objects in compartment ${var.compartment_name} where target.bucket.name='tf-state-${var.compartment_name}'",
    "Allow dynamic-group ${var.dynamic_group_name} to manage objects in compartment ${var.compartment_name} where target.bucket.name='jvb-images-${var.compartment_name}'",
    "Allow dynamic-group ${var.dynamic_group_name} to manage objects in compartment ${var.compartment_name} where target.bucket.name='iperf-logs-${var.compartment_name}'",
    "Allow dynamic-group ${var.dynamic_group_name} to manage objects in compartment ${var.compartment_name} where target.bucket.name='stats-${var.compartment_name}'",
    "Allow dynamic-group ${var.dynamic_group_name} to use tag-namespace in compartment ${var.compartment_name}",
    "Allow dynamic-group ${var.dynamic_group_name} to manage private-ips in compartment ${var.compartment_name}",
    "Allow dynamic-group ${var.dynamic_group_name} to manage public-ips in compartment ${var.compartment_name}",
    "Allow dynamic-group ${var.dynamic_group_name} to read compartments in compartment ${var.compartment_name}",
    "Allow service compute_management to use tag-namespace in compartment ${var.compartment_name}",
    "Allow dynamic-group ${var.dynamic_group_name} to manage volume-family in compartment ${var.compartment_name}"
  ]
}

output "policy" {
  value = oci_identity_policy.policy.name
}