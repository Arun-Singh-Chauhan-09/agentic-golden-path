variable "cluster_name" {
  type        = string
  description = "kind cluster name. kubectl context becomes kind-<name>."
  default     = "agentic-gp"
}

variable "node_image" {
  type        = string
  description = "kindest/node image; pin it so every rebuild gets the same Kubernetes version."
  default     = "kindest/node:v1.31.0"
}

variable "app_host_port" {
  type        = number
  description = "Host port for the app (maps to NodePort 30090)."
  default     = 8090
}

variable "grafana_host_port" {
  type        = number
  description = "Host port for Grafana (maps to NodePort 30030)."
  default     = 3030
}
