variable "job_name" {
  # If "", the pack name will be used
  description = "The name to use as the job name which overrides using the pack name"
  type        = string
  default     = ""
}

variable "region" {
  description = "The region where jobs will be deployed"
  type        = string
  default     = "global"
}
variable "environment" {
  description = "The environment where jobs will be deployed"
  type        = string
}
variable "oracle_region" {
  description = "The region where jobs will be deployed"
  type        = string
}
variable "oscar_hostname" {
  description = "The hostname of the oscar instance"
  type        = string
  default     = "oscar.example.com"
}
variable "top_level_domain" {
  description = "The top level domain to use for the oscar hostname building"
  type        = string
  default     = "example.com"
}
variable "domain" {
  description = "The domain to use for site ingress monitoring"
  type        = string
  default     = "example.com"
}
variable "pool_type" {
  description = "The type of pool to deploy"
  type        = string
  default     = "general"
}

variable "datacenters" {
  description = "A list of datacenters in the region which are eligible for task placement"
  type        = list(string)
  default     = ["*"]
}

variable "cloudprober_version" {
  description = "The version of cloudprober to use"
  type        = string
  default     = "0.11.0"

}

variable "enable_ops_repo" {
  description = "Whether to enable the ops repo monitoring"
  type        = bool
  default     = false

}

variable "enable_site_ingress" {
  description = "Whether to enable the site ingress monitoring"
  type        = bool
  default     = false
}

variable "enable_haproxy_region" {
  description = "Whether to enable the haproxy region monitoring"
  type        = bool
  default     = false
}

variable "enable_autoscaler" {
  description = "Whether to enable the autoscaler monitoring"
  type        = bool
  default     = false
}

variable "enable_wavefront_proxy" {
  description = "Whether to enable the wavefront proxy monitoring"
  type        = bool
  default     = true
}

variable "enable_coturn" {
  description = "Whether to enable the coturn monitoring"
  type        = bool
  default     = false
}