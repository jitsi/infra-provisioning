variable "tenancy_ocid" {}
variable "compartment_name" {}
variable "dynamic_group_name" {}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
}

// ============ Compartment ============

resource "oci_identity_compartment" "oci_compartment" {
  compartment_id = var.tenancy_ocid
  description = "Dedicated compartment for ${var.compartment_name} environment"
  name = var.compartment_name
}

// ============ Dynamic Group ============

resource "oci_identity_dynamic_group" "dynamic_group" {
  compartment_id = var.tenancy_ocid
  description = "Enabling instances from ${var.compartment_name} Compartment to make API calls against OCI"
  matching_rule = "all {instance.compartment.id = '${oci_identity_compartment.oci_compartment.id}'}"
  name = var.dynamic_group_name
  depends_on = [
    oci_identity_compartment.oci_compartment]
}

resource "oci_identity_dynamic_group" "jibri_dynamic_group" {
  compartment_id = var.tenancy_ocid
  description = "Enabling Jibri instances from ${var.compartment_name} Compartment to make API calls against OCI"
  matching_rule = "all {instance.compartment.id = '${oci_identity_compartment.oci_compartment.id}', tag.jitsi.shard-role.value = 'java-jibri'}"
  name = "${var.compartment_name}-jibri-dynamic-group"
  depends_on = [
    oci_identity_compartment.oci_compartment]
}

resource "oci_identity_dynamic_group" "recovery_agent_dynamic_group" {
  compartment_id = var.tenancy_ocid
  description = "Enabling Recovery instances from ${var.compartment_name} Compartment to make API calls against OCI"
  matching_rule = "all {instance.compartment.id = '${oci_identity_compartment.oci_compartment.id}', tag.jitsi.shard-role.value = 'recovery-agent'}"
  name = "${var.compartment_name}-recovery-agent-dynamic-group"
  depends_on = [
    oci_identity_compartment.oci_compartment]
}

resource "oci_identity_dynamic_group" "nomad_pool_dynamic_group" {
  compartment_id = var.tenancy_ocid
  description = "Enabling Nomad Pool instances from ${var.compartment_name} Compartment to make API calls against OCI"
  matching_rule = "all {instance.compartment.id = '${oci_identity_compartment.oci_compartment.id}', tag.jitsi.role.value = 'nomad-pool'}"
  name = "${var.compartment_name}-nomad-pool-dynamic-group"
  depends_on = [
    oci_identity_compartment.oci_compartment]
}

// ============ OUTPUTS ============

output "compartment_ocid" {
  value = oci_identity_compartment.oci_compartment.id
}

output "dynamic_group" {
  value = oci_identity_dynamic_group.dynamic_group.name
}

output "jibri_dynamic_group" {
  value = oci_identity_dynamic_group.jibri_dynamic_group.name
}

output "recovery_agent_dynamic_group" {
  value = oci_identity_dynamic_group.recovery_agent_dynamic_group.name
}
