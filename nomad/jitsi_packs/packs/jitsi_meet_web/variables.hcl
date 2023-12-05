variable "job_name" {
  # If "", the pack name will be used
  description = "The name to use as the job name which overrides using the pack name"
  type        = string
  default     = ""
}

variable "dc" {
  description = "The datacenters to use"
  type        = list(string)
}