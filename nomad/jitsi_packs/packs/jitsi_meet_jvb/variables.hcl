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

variable "datacenter" {
  description = "A datacenter in the region which are eligible for task placement"
  type        = string
}

variable "connect_datacenters" {
  description = "The list of datacenters to search shards in for consul-connect"
  type        = list(string)
  default     = []
}
