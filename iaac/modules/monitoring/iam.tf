# IAM Role for CloudWatch
resource "aws_iam_role" "cloudwatch_role" {
  name = "${var.resources_name_prefix}-cloudwatch-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}
