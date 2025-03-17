# IAM Role for Spark Instances/Tasks
resource "aws_iam_role" "spark_instance_role" {
  name = "${var.resources_name_prefix}-spark-instance-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["ec2.amazonaws.com", "ecs-tasks.amazonaws.com"]
        }
      }
    ]
  })
  
  tags = var.tags
}


# IAM Instance Profile for Spark Instances
resource "aws_iam_instance_profile" "spark_instance_profile" {
  name = "${var.resources_name_prefix}-spark-instance-profile"
  role = aws_iam_role.spark_instance_role.name
  
  tags = var.tags
}

# No ECR policy needed as we're using public Docker images

resource "aws_iam_role_policy_attachment" "spark_execution_logs" {
  role       = aws_iam_role.spark_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "spark_execution_role" {
  name = "${var.resources_name_prefix}-spark-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.resources_name_prefix}-lambda-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
  
  tags = var.tags
}

# IAM role for Step Functions state machine
resource "aws_iam_role" "step_function_role" {
  name = "${var.resources_name_prefix}-step-function-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })
  
  tags = var.tags
}

# IAM policy for Step Functions to invoke Lambda functions
resource "aws_iam_role_policy" "step_function_lambda_invoke" {
  name = "${var.resources_name_prefix}-step-function-lambda-invoke"
  role = aws_iam_role.step_function_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          module.check_new_data.lambda_function_arn,
          module.start_ec2_instances.lambda_function_arn,
          module.check_job_status.lambda_function_arn,
          module.stop_ec2_instances.lambda_function_arn
        ]
      }
    ]
  })
}

# IAM policy for Step Functions to log to CloudWatch
resource "aws_iam_role_policy" "step_function_cloudwatch" {
  name = "${var.resources_name_prefix}-step-function-cloudwatch"
  role = aws_iam_role.step_function_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}