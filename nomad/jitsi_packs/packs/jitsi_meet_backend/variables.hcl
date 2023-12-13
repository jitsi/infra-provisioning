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
  description = "The datacenter to place the task"
  type        = string
}

variable "fabio_domain_enabled" {
  description = "Whether to enable the full domain as a urlprefix for fabio"
  type        = bool
  default     = false
}

variable "visitors_count" {
  type = number
  default = 0
}