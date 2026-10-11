output "sns_topic_arn" {
  description = "Subscribe a Slack/email endpoint here to receive SLO alerts."
  value       = aws_sns_topic.alerts.arn
}
