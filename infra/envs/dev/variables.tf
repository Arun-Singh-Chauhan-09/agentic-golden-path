variable "region" {
  type    = string
  default = "eu-central-1" # Frankfurt
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "image_tag" {
  type        = string
  description = "Image tag to deploy; CI passes the git SHA via TF_VAR_image_tag."
  default     = "latest"
}
