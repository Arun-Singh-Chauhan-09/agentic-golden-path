output "postgres_endpoint" {
  value = aws_db_instance.this.address
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "db_password_secret_arn" {
  description = "Secrets Manager ARN the app reads the DB password from."
  value       = aws_secretsmanager_secret.db.arn
}
