variable "job_name" {
  description = "The name to use as the job name which overrides using the pack name"
  type        = string
  default     = ""
}

variable "region" {
  description = "The region where the job should be placed"
  type        = string
  default     = ""
}

variable "datacenters" {
  description = "A list of datacenters in the region which are eligible for task placement"
  type        = list(string)
  default     = ["dc1"]
}

variable "pool_type" {
  description = "The type of pool to deploy to"
  type        = string
  default     = "general"
}

variable "image" {
  description = "The opus-transcriber-proxy docker image (run in monitor mode via a command override)"
  type        = string
}

variable "metrics_port" {
  description = "Container port the synthetic metrics server listens on (mapped to a dynamic host port and scraped by Prometheus via Consul)"
  type        = number
  default     = 8080
}

variable "interval_seconds" {
  description = "How often the synthetic replays the sample against the endpoint"
  type        = string
  default     = "300"
}

variable "retry_delay_seconds" {
  description = "Seconds to wait before the single retry after a failed first attempt (the run reports failure only if both attempts fail)"
  type        = string
  default     = "20"
}

variable "ws_url_template" {
  description = "The wss:// /transcribe endpoint. The literal token __SESSION_ID__ is replaced at runtime with a fresh synthetic-<random> sessionId so successive runs never clash."
  type        = string
}

variable "sample_dump" {
  description = "Path (inside the image) to the JSONL Opus dump to replay"
  type        = string
  default     = "resources/sample.jsonl"
}

variable "connect_timeout" {
  description = "Seconds to wait for the websocket to connect before failing"
  type        = string
  default     = "15"
}

variable "assert_min_finals" {
  description = "Minimum number of final transcripts required for the run to pass"
  type        = string
  default     = "1"
}

variable "environment" {
  description = "Environment name; selects the Vault path secret/default/opus-transcriber-proxy/monitor-<environment> holding the CF Access service token"
  type        = string
}
