module "start_ec2_instances" {
  source  = "terraform-aws-modules/lambda/aws"

  function_name = "${var.resources_name_prefix}-start-ec2"
  description   = "Starts EC2 instances for Spark processing"
  handler       = "main.start_ec2"
  runtime       = "python3.11"
  architectures = ["arm64"]
  compatible_runtimes = ["python3.11"]
  timeout       = 60
  memory_size   = 128

  source_path = "${local.lambda_functions_path}/ec2_manager"

  create_role = false
  lambda_role = aws_iam_role.lambda_role.arn

  environment_variables = {
    MASTER_INSTANCE_ID  = aws_instance.spark_master.id
    WORKER_INSTANCE_IDS = jsonencode(aws_instance.spark_workers[*].id)
    CODE_BUCKET         = var.build_storage_bucket_name
    SPARK_JOB_SCRIPT    = "session_builder.py"
    LOG_GROUP         = "/session-builder/${var.environment}/spark"
    DATA_LAKE_BUCKET = var.data_lake_bucket_name
    PROCESSED_FOLDER    = var.deltalake_folder_name
  }

  tags = var.tags
}

module "check_job_status" {
  source  = "terraform-aws-modules/lambda/aws"

  function_name = "${var.resources_name_prefix}-check-status"
  description   = "Checks Spark job status"
  handler       = "main.check_status"
  runtime       = "python3.11"
  architectures = ["arm64"]
  compatible_runtimes = ["python3.11"]
  timeout       = 30
  memory_size   = 128

  source_path = "${local.lambda_functions_path}/ec2_manager"

  create_role = false
  lambda_role = aws_iam_role.lambda_role.arn

  environment_variables = {
    MASTER_INSTANCE_ID  = aws_instance.spark_master.id
    WORKER_INSTANCE_IDS = jsonencode(aws_instance.spark_workers[*].id)
    CODE_BUCKET         = var.build_storage_bucket_name
    SPARK_JOB_SCRIPT    = "session_builder.py"
    LOG_GROUP         = "/session-builder/${var.environment}/spark"
    DATA_LAKE_BUCKET = var.data_lake_bucket_name
    PROCESSED_FOLDER    = var.deltalake_folder_name
  }

  tags = var.tags
}

module "stop_ec2_instances" {
  source  = "terraform-aws-modules/lambda/aws"

  function_name = "${var.resources_name_prefix}-stop-ec2"
  description   = "Stops EC2 instances after processing"
  handler       = "main.stop_ec2"
  runtime       = "python3.11"
  architectures = ["arm64"]
  compatible_runtimes = ["python3.11"]
  timeout       = 60
  memory_size   = 128

  source_path = "${local.lambda_functions_path}/ec2_manager"

  create_role = false
  lambda_role = aws_iam_role.lambda_role.arn

  environment_variables = {
    MASTER_INSTANCE_ID  = aws_instance.spark_master.id
    WORKER_INSTANCE_IDS = jsonencode(aws_instance.spark_workers[*].id)
    CODE_BUCKET         = var.build_storage_bucket_name
    SPARK_JOB_SCRIPT    = "session_builder.py"
    LOG_GROUP         = "/session-builder/${var.environment}/spark"
    DATA_LAKE_BUCKET = var.data_lake_bucket_name
    PROCESSED_FOLDER    = var.deltalake_folder_name
  }

  tags = var.tags
}

module "check_new_data" {
  source  = "terraform-aws-modules/lambda/aws"

  function_name = "${var.resources_name_prefix}-check-new-data"
  description   = "Checks for new data in the data lake bucket"
  handler       = "main.lambda_handler"
  runtime       = "python3.11"
  architectures = ["arm64"]
  compatible_runtimes = ["python3.11"]
  timeout       = 30
  memory_size   = 128

  source_path = "${local.lambda_functions_path}/check_new_data"

  create_role = false
  lambda_role = aws_iam_role.lambda_role.arn

  environment_variables = {
    MASTER_INSTANCE_ID  = aws_instance.spark_master.id
    WORKER_INSTANCE_IDS = jsonencode(aws_instance.spark_workers[*].id)
    CODE_BUCKET         = var.build_storage_bucket_name
    SPARK_JOB_SCRIPT    = "session_builder.py"
    LOG_GROUP         = "/session-builder/${var.environment}/spark"
    DATA_LAKE_BUCKET = var.data_lake_bucket_name
    PROCESSED_FOLDER    = var.deltalake_folder_name
  }

  tags = var.tags
}