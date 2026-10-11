variable "name" {
  type        = string
  description = "Service + resource name prefix."
}

variable "region" {
  type        = string
  description = "AWS region (used for the awslogs driver)."
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Subnets for the public ALB."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Subnets for the Fargate tasks."
}

variable "image_tag" {
  type        = string
  description = "Container image tag to deploy (usually the git SHA)."
  default     = "latest"
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "mock_llm" {
  type        = bool
  description = "Run the app in mock mode (no real Bedrock calls)."
  default     = true
}

variable "bedrock_model_arns" {
  type        = list(string)
  description = "ARNs the task role may invoke. Empty = no Bedrock policy attached."
  default     = []
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "force_delete_ecr" {
  type        = bool
  description = "Allow terraform destroy to remove a non-empty ECR repo (dev only)."
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
