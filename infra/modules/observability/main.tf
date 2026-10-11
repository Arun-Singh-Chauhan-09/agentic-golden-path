terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# The platform's one defined SLO, expressed as CloudWatch alarms.
#
# SLO:  99.5% of requests succeed (non-5xx) AND p95 latency < 1s,
#       measured over a rolling window.
# SLI:  derived from ALB HTTPCode_Target_5XX_Count / RequestCount,
#       and TargetResponseTime p95.
#
# Burning through the error budget pages the on-call; the README explains
# the budget math. One well-reasoned SLO beats ten vanity dashboards.

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
  tags = var.tags
}

# --- Availability: 5xx rate over threshold ------------------------------
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "${var.name}-5xx-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = var.error_rate_threshold # e.g. 0.005 = 0.5%
  treat_missing_data  = "notBreaching"
  alarm_description   = "5xx error ratio above SLO error budget"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "error_ratio"
    expression  = "errors / requests"
    label       = "5xx error ratio"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  tags = var.tags
}

# --- Latency: p95 target response time ----------------------------------
resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${var.name}-latency-p95"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = var.latency_p95_seconds
  treat_missing_data  = "notBreaching"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  period              = 60
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  alarm_description   = "p95 latency above SLO"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}
