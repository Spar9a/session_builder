# Local variable for Spark Docker Image
locals {
  spark_image = "bitnami/spark:latest"
}

# CloudWatch Log Group for Spark Logs
resource "aws_cloudwatch_log_group" "spark_logs" {
  name              = "/session-builder/${var.environment}/spark"
  retention_in_days = 30
  
  tags = var.tags
}

# SSM Parameter for Spark Configuration
resource "aws_ssm_parameter" "spark_config" {
  name  = "/session-builder/${var.environment}/config/spark"
  type  = "String"
  value = jsonencode({
    "spark.executor.memory"      = "4g"
    "spark.executor.cores"       = "2"
    "spark.driver.memory"        = "4g"
    "spark.driver.cores"         = "2"
    "spark.default.parallelism"  = "20"
    "spark.sql.extensions"       = "io.delta.sql.DeltaSparkSessionExtension"
    "spark.sql.catalog.spark_catalog" = "org.apache.spark.sql.delta.catalog.DeltaCatalog"
  })
  
  tags = var.tags
}

# Security Group for Spark Cluster
resource "aws_security_group" "spark_sg" {
  name        = "${var.resources_name_prefix}-spark-sg"
  description = "Security group for Spark cluster"
  vpc_id      = var.vpc_id
  
  # Spark internal communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
    description = "Allow all internal cluster communication"
  }
  
  # Spark UI
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Spark master UI"
  }
  
  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(var.tags, {
    Name = "${var.resources_name_prefix}-spark-sg"
  })
}

# IAM Policy for S3 Access
resource "aws_iam_role_policy" "spark_s3_access" {
  name = "${var.resources_name_prefix}-spark-s3-access"
  role = aws_iam_role.spark_instance_role.id
  
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
          "arn:aws:s3:::${var.data_lake_bucket_name}/*",
          "arn:aws:s3:::${var.build_storage_bucket_name}",
          "arn:aws:s3:::${var.build_storage_bucket_name}/*"
        ]
      }
    ]
  })
}

# IAM Policy for CloudWatch Logs
resource "aws_iam_role_policy" "spark_cloudwatch_access" {
  name = "${var.resources_name_prefix}-spark-cloudwatch-access"
  role = aws_iam_role.spark_instance_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.spark_logs.arn}:*"
        ]
      }
    ]
  })
}

# IAM Policy for SSM Access
resource "aws_iam_role_policy" "spark_ssm_access" {
  name = "${var.resources_name_prefix}-spark-ssm-access"
  role = aws_iam_role.spark_instance_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:parameter/session-builder/${var.environment}/*"
        ]
      }
    ]
  })
}

# EC2 Instance for Spark Master
resource "aws_instance" "spark_master" {
  ami                    = var.spark_ami_id
  instance_type          = var.master_instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [aws_security_group.spark_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.spark_instance_profile.name
  
  user_data = templatefile("${path.module}/files/spark/master_user_data.sh", {
    aws_region         = var.aws_region
    cloudwatch_group   = aws_cloudwatch_log_group.spark_logs.name
    data_lake_bucket_name   = var.data_lake_bucket_name
    raw_data_folder    = var.raw_data_folder_name
    ssm_config_path = aws_ssm_parameter.spark_config.name
    code_bucket   = var.build_storage_bucket_name
    processed_data_folder = var.processed_data_folder_name
    deltalake_folder = var.deltalake_folder_name
  })

  user_data_replace_on_change = true

  
  tags = merge(var.tags, {
    Name = "${var.resources_name_prefix}-spark-master"
    Role = "spark-master"
  })
  
  volume_tags = merge(var.tags, {
    Name = "${var.resources_name_prefix}-spark-master-volume"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# EC2 Instances for Spark Workers
resource "aws_instance" "spark_workers" {
  count                  = var.worker_count
  ami                    = var.spark_ami_id
  instance_type          = var.worker_instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [aws_security_group.spark_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.spark_instance_profile.name
  
  user_data = templatefile("${path.module}/files/spark/worker_user_data.sh", {
    aws_region         = var.aws_region
    cloudwatch_group   = aws_cloudwatch_log_group.spark_logs.name
    data_lake_bucket_name   = var.data_lake_bucket_name
    raw_data_folder    = var.raw_data_folder_name
    code_bucket   = var.build_storage_bucket_name
    ssm_config_path = aws_ssm_parameter.spark_config.name
    processed_data_folder = var.processed_data_folder_name
    deltalake_folder = var.deltalake_folder_name
  })

  user_data_replace_on_change = true
  
  tags = merge(var.tags, {
    Name = "${var.resources_name_prefix}-spark-worker-${count.index}"
    Role = "spark-worker"
  })
  
  volume_tags = merge(var.tags, {
    Name = "${var.resources_name_prefix}-spark-worker-${count.index}-volume"
  })
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [aws_instance.spark_master]
}