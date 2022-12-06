variable "tenancy_ocid" {}
variable "compartment_name" {}
variable "compartment_id" {}
variable "jibri_policy_name" {}
variable "recovery_agent_policy_name" {}
variable "jibri_dynamic_group_name" {}
variable "recovery_agent_dynamic_group_name" {}

variable "regions" {
  type = list(string)
}
variable "vcn_ids" {
  type = list(string)
}

provider "oci" {
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
  # flatten ensures that this local value is a flat list of objects,
  # rather than a list of lists of objects
  jibri_statements = concat(flatten([
  for region, vcn_id in zipmap(var.regions, var.vcn_ids):
  [
    #To execute object lifecycle policies, you must authorize the service to archive and delete objects on your behalf.
    "Allow service objectstorage-${region} to manage object-family in compartment ${var.compartment_name}",

    #If you are creating a pre-authenticated request (PAR) for read access to objects in a bucket,
    #you need OBJECT_READ, in addition to PAR_MANAGE (included in permission to manage buckets) to grant user read access to objects.
    #Writing policies for object-family is equivalent to writing a separate one for managing objects and another one for managing buckets.
    "Allow dynamic-group ${var.jibri_dynamic_group_name} to manage object-family in compartment ${var.compartment_name} where all {target.bucket.name='failed-recordings-${var.compartment_name}-${region}',request.vcn.id='${vcn_id}'}",
    "Allow dynamic-group ${var.jibri_dynamic_group_name} to manage object-family in compartment ${var.compartment_name} where all {target.bucket.name='dropbox-failed-recordings-${var.compartment_name}-${region}',request.vcn.id='${vcn_id}'}",
    "Allow dynamic-group ${var.jibri_dynamic_group_name} to manage object-family in compartment ${var.compartment_name} where all {target.bucket.name='vpaas-recordings-${var.compartment_name}-${region}',request.vcn.id='${vcn_id}'}",
    # Needed for allowing read access for objects identified via a pre-auth requests.
    # Permissions of the pre-authenticated request creator are checked each time you use a pre-authenticated request.
    # We can no longer restrict via VCN, as otherwise, the requests going through the internet gateway will be denied.
    # Jibri agent generates PARs for vpaas recordings.
    "Allow dynamic-group ${var.jibri_dynamic_group_name} to read objects in compartment ${var.compartment_name} where target.bucket.name='vpaas-recordings-${var.compartment_name}-${region}'",
  ]
  ]
  ),
  [
    "Allow dynamic-group ${var.jibri_dynamic_group_name} to read volume-family in compartment ${var.compartment_name}"
  ]
  )

  recovery_agent_statements = flatten([
  for region, vcn_id in zipmap(var.regions, var.vcn_ids):
  [
    "Allow dynamic-group ${var.recovery_agent_dynamic_group_name} to manage object-family in compartment ${var.compartment_name} where all {target.bucket.name='failed-recordings-${var.compartment_name}-${region}',request.vcn.id='${vcn_id}'}",
    "Allow dynamic-group ${var.recovery_agent_dynamic_group_name} to manage object-family in compartment ${var.compartment_name} where all {target.bucket.name='dropbox-failed-recordings-${var.compartment_name}-${region}',request.vcn.id='${vcn_id}'}",
    "Allow dynamic-group ${var.recovery_agent_dynamic_group_name} to manage object-family in compartment ${var.compartment_name} where all {target.bucket.name='vpaas-failed-recordings-${var.compartment_name}-${region}',request.vcn.id='${vcn_id}'}",
    # Recovery agent generates PARs for both failed dropbox and vpaas recordings
    "Allow dynamic-group ${var.recovery_agent_dynamic_group_name} to read objects in compartment ${var.compartment_name} where any {target.bucket.name='vpaas-failed-recordings-${var.compartment_name}-${region}',target.bucket.name='dropbox-failed-recordings-${var.compartment_name}-${region}'}"
  ]
  ])
}

//============ Policies ============

resource "oci_identity_policy" "jibri_policy" {
  name = var.jibri_policy_name
  description = "Allow Jibris to use additional OCI resources within the compartment ${var.compartment_name}, with restricted access to objects per service's region"
  compartment_id = var.compartment_id

  statements = local.jibri_statements
}

resource "oci_identity_policy" "recovery_agent_policy" {
  name = var.recovery_agent_policy_name
  description = "Allow Recovery agent to use additional OCI resources within the compartment ${var.compartment_name}, with restricted access to objects per service's region"
  compartment_id = var.compartment_id

  statements = local.recovery_agent_statements
}

output "jibri_policy" {
  value = oci_identity_policy.jibri_policy.name
}

output "recovery_agent_policy" {
  value = oci_identity_policy.recovery_agent_policy.name
}