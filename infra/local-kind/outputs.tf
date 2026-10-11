output "kube_context" {
  description = "Context name to pass to kubectl --context."
  value       = "kind-${kind_cluster.this.name}"
}

output "endpoint" {
  value = kind_cluster.this.endpoint
}

output "app_url" {
  value = "http://localhost:${var.app_host_port}"
}

output "grafana_url" {
  value = "http://localhost:${var.grafana_host_port}"
}
