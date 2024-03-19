variable "job_name" {
  # If "", the pack name will be used
  description = "The name to use as the job name which overrides using the pack name"
  type        = string
  default     = "jitsi-autoscaler"
}

variable "region" {
  description = "The region where jobs will be deployed"
  type        = string
  default     = "global"
}

variable "datacenters" {
  description = "A list of datacenters in the region which are eligible for task placement"
  type        = list(string)
  default     = ["*"]
}

variable "count" {
  description = "The number of app instances to deploy"
  type        = number
  default     = 2
}

variable "hostname" {
  description = "The hostname to use for the app"
  type        = string
  default     = "autoscaler.example.com"
}

variable "version" {
  description = "The version of the app to deploy"
  type        = string
  default     = "latest"
}

variable "pool_type" {
  description = "The type of pool to use for the job"
  type        = string
  default     = "general"
}

variable "register_service" {
  description = "If you want to register a consul service for the job"
  type        = bool
  default     = true
}

variable "redis_from_consul" {
  description = "If you want to use the Redis service registered in Consul"
  type        = bool
  default     = true
}

variable "redis_service_name" {
  description = "Controls redis service name to discover in Consul"
  type        = string
  default     = "master.resec-redis"
}

variable "redis_host" {
  description = "If you want to use a Redis host that is not registered in Consul"
  type        = string
  default     = "localhost"
}

variable "redis_port" {
  description = "If you want to use a Redis host that is not registered in Consul"
  type        = string
  default     = "6379"
}

variable "redis_tls" {
  description = "If you want to use TLS to connect to Redis"
  type        = bool
  default     = false
}

variable "asap_base_url" {
  description = "The base URL for the ASAP API"
  type        = string
  default     = "https://example.com/asap_keys/server"
}

variable "enable_oci" {
  description = "If you want to enable OCI in the autoscaler"
  type        = bool
  default     = true
}

variable "enable_nomad" {
  description = "If you want to enable nomad in the autoscaler"
  type        = bool
  default     = true
}

variable "asap_accepted_hook_iss" {
  description = "The accepted hook issuer"
  type        = string
  default     = "jitsi-autoscaler-sidecar,homer"
}

variable "asap_jwt_aud" {
  description = "The JWT audience accepted by the autoscaler"
  default = "jitsi-autoscaler"
}

variable "oci_compartment_id" {
  description = "The default OCI compartment for launches"
  type        = string
}

variable "resources" {
  description = "The resources to use for the job"
  type        = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 1000
    memory = 1024
  }
}