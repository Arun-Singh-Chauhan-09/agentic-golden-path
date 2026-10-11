# Local Kubernetes cluster for the free, laptop-only track.
#
# Terraform owns the cluster; ArgoCD owns what runs inside it. Same split as
# the AWS track (Terraform owns ECS, the pipeline owns the image), so the
# mental model carries over.
#
#   terraform -chdir=infra/local-kind init
#   terraform -chdir=infra/local-kind apply

terraform {
  required_version = ">= 1.6"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.9"
    }
  }
}

provider "kind" {}

resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # NodePorts published straight to the host: no port-forward needed for
      # the two things you open most (the app and Grafana).
      extra_port_mappings {
        container_port = 30090 # app Service nodePort
        host_port      = var.app_host_port
      }
      extra_port_mappings {
        container_port = 30030 # Grafana Service nodePort
        host_port      = var.grafana_host_port
      }
    }

    node {
      role = "worker"
    }
  }
}
