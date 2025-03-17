# IAM role for Lambda functions
resource "aws_iam_role" "data_faker_lambda_role" {
  name = "${var.resources_name_prefix}-data-faker-lambda-role"

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

# IAM Policy for S3 Access
resource "aws_iam_role_policy" "data_faker_s3_access" {
  name = "${var.resources_name_prefix}-data-faker-s3-access"
  role = aws_iam_role.data_faker_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.data_lake_bucket_name}",
          "arn:aws:s3:::${var.data_lake_bucket_name}/*"
        ]
      }
    ]
  })
}