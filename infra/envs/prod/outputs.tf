output "service_url" {
  value = "http://${module.service.alb_dns_name}"
}

output "ecr_repository_url" {
  value = module.service.ecr_repository_url
}

output "cluster_name" {
  value = module.service.cluster_name
}

output "service_name" {
  value = module.service.service_name
}

output "alerts_sns_topic_arn" {
  value = module.observability.sns_topic_arn
}
