variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "image_tag" {
  type        = string
  description = "Pinned image tag (git SHA). No default: prod must deploy a known build."
}

variable "bedrock_model_arns" {
  type        = list(string)
  description = "Bedrock model ARNs the task role may invoke in prod."
  default     = []
}
