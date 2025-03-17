# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions_logs" {
  name              = "/aws/states/${var.resources_name_prefix}-workflow"
  retention_in_days = 30
}

# CloudWatch Log Group for Spark Logs
resource "aws_cloudwatch_log_group" "spark_logs" {
  name              = "/session-builder/${var.resources_name_prefix}/spark"
  retention_in_days = 30
  
  tags = var.tags
}

# CloudWatch Alarm for Step Functions Execution Failures
resource "aws_cloudwatch_metric_alarm" "step_functions_failed" {
  alarm_name          = "${var.resources_name_prefix}-step-functions-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors Step Functions execution failures"
  alarm_actions       = [aws_sns_topic.error_topic.arn]
  ok_actions          = [aws_sns_topic.completion_topic.arn]
  
  dimensions = {
    StateMachineArn = var.session_builder_workflow_arn
  }
}

# CloudWatch Alarm for Step Functions Execution Timeouts
resource "aws_cloudwatch_metric_alarm" "step_functions_timed_out" {
  alarm_name          = "${var.resources_name_prefix}-step-functions-timed-out"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsTimedOut"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors Step Functions execution timeouts"
  alarm_actions       = [aws_sns_topic.error_topic.arn]
  ok_actions          = [aws_sns_topic.completion_topic.arn]
  
  dimensions = {
    StateMachineArn = var.session_builder_workflow_arn
  }

}

# CloudWatch Dashboard for Session Builder
resource "aws_cloudwatch_dashboard" "session_builder_dashboard" {
  dashboard_name = "${var.resources_name_prefix}-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", var.session_builder_workflow_arn],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", var.session_builder_workflow_arn],
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", var.session_builder_workflow_arn],
            ["AWS/States", "ExecutionsTimedOut", "StateMachineArn", var.session_builder_workflow_arn]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Step Functions Executions"
          period  = 300
        }
      }
    ]
  })
}


# SNS Topics for notifications

# SNS Topic for completion notifications
resource "aws_sns_topic" "completion_topic" {
  name = "${var.resources_name_prefix}-completion-notifications"

  tags = merge(
    var.tags,
    {
      Name        = "${var.resources_name_prefix}-completion-notifications"
      Environment = var.environment
      Project     = var.project_name
    }
  )
}

# SNS Topic for error notifications
resource "aws_sns_topic" "error_topic" {
  name = "${var.resources_name_prefix}-error-notifications"

  tags = merge(
    var.tags,
    {
      Name        = "${var.resources_name_prefix}-error-notifications"
      Environment = var.environment
      Project     = var.project_name
    }
  )
}