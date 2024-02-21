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

variable "enable_shard" {
  description = "Whether to enable the cross-region shard monitoring."
  type        = bool
  default     = false
}

variable "enable_skynet" {
  description = "Whether to enable the skynet monitoring"
  type        = bool
  default     = false
}

variable "skynet_hostname" {
  description = "The hostname of the skynet service"
  type        = string
}

variable "rtcstats_hostname" {
  description = "The hostname of the rtcstats service"
  type        = string
}

variable "enable_whisper" {
  description = "Whether to enable the whisper monitoring"
  type        = bool
  default     = false
}

variable "whisper_hostname" {
  description = "The hostname of the whisper service"
  type        = string
}

variable "enable_custom_https" {
  description = "Whether to enable the custom https monitoring"
  type        = bool
  default     = false
}

variable "custom_https_targets" {
  description = "target endpoints"
  type        = string
  default     = ""
}

variable "enable_loki" {
  description = "Whether to enable the loki monitoring"
  type        = bool
  default     = false
}