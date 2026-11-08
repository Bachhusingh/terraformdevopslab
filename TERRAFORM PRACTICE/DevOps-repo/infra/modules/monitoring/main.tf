hcl
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/releaseops/${var.env}/app"
  retention_in_days = 14
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.env}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  dimensions          = { InstanceId = var.instance_id }
  alarm_actions       = [var.sns_topic_arn]   # ≈ Azure Monitor Action Group
}