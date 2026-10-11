variable "name" {
  type        = string
  description = "Name prefix for tagging resources."
}

variable "cidr_block" {
  type        = string
  description = "VPC CIDR block."
  default     = "10.0.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Number of AZs to spread subnets across."
  default     = 2
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
