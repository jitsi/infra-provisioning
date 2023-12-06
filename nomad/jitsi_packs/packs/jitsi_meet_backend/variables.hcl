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

variable "prosody_modules_commit_id" {
  description = "The commit id of the prosody modules to use"
  type        = string
  default = "6696075e26e2"
}
