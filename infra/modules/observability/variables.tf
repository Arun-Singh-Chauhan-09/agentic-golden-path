variable "name" {
  type = string
}

variable "alb_arn_suffix" {
  type        = string
  description = "ALB arn_suffix from the ecs-service module."
}

variable "error_rate_threshold" {
  type        = number
  description = "Max tolerated 5xx ratio (0.005 = 0.5%, i.e. 99.5% availability SLO)."
  default     = 0.005
}

variable "latency_p95_seconds" {
  type        = number
  description = "p95 latency SLO in seconds."
  default     = 1.0
}

variable "tags" {
  type    = map(string)
  default = {}
}
