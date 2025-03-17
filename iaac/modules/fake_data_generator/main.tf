locals {
  functions_dir = "${path.module}/files/functions"
}

# module "data_faker_layer" {
#   source = "terraform-aws-modules/lambda/aws"
#   create_layer = true
#   docker_image = "${var.resources_name_prefix}-data-faker-layer"
#   compatible_runtimes = ["python3.11"]
#   source_path = "${local.functions_dir}/data_faker"
#   build_in_docker = true
#   # docker_pip_cache = true
#   docker_file = "${local.functions_dir}/data_faker/Dockerfile"
#   architectures = ["arm64"]
# }


module "data_faker_function" {
  source  = "terraform-aws-modules/lambda/aws"

  create_function = true
  publish = true

  function_name = "${var.resources_name_prefix}-data-faker"
  docker_image = "${var.resources_name_prefix}-data-faker-image"
  handler          = "main.lambda_handler"

  lambda_role = aws_iam_role.data_faker_lambda_role.arn
  source_path = "${local.functions_dir}/data_faker"
  build_in_docker = true
  # docker_pip_cache = true
  docker_file = "${local.functions_dir}/data_faker/Dockerfile"

  environment_variables = {
      NUM_USERS=var.num_users
      ROWS_PER_FILE=var.rows_per_file
      NUM_FILES_PER_DAY=var.num_files_per_day
      NUM_API_DAYS=var.num_api_days
      MAX_DAYS_BACKWARD=var.max_days_backward
      S3_BUCKET_NAME=var.data_lake_bucket_name
      S3_INPUT_FOLDER=var.raw_data_folder
  }

  architectures = ["arm64"]
  compatible_runtimes = ["python3.11"]
  runtime     = "python3.11"
  timeout = 360
  memory_size = 1024

  tags = var.tags
  
}
