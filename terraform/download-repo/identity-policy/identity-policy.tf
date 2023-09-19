variable "bucket_name" {
    type = string
    default = "download-repo"
}
variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
# oracle/oci provider
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

# set policy that includes statement: Allow group Jenkins to manage objects in compartment torture-test where target.bucket.name='${var.bucket_name}'	
resource "oci_identity_policy" "repo_bucket_policy" {
    #Required
    compartment_id = var.compartment_ocid
    description = "Allows Jenkins to manage download-repo objects in compartment"
    name = "download_repo_bucket_policy"
    statements = [
        "Allow group Jenkins to manage objects in compartment torture-test where target.bucket.name='${var.bucket_name}'"
    ]
}