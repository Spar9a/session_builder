# Local values for the Session Builder Terraform project

locals {
  # Common tags to be assigned to all resources
  tags = merge({
    project = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }, var.tags)
  
  # S3 bucket names with environment prefix
  data_lake_bucket_name = "${var.project_name}-${var.data_lake_bucket_suffix}-${var.environment}"
  build_bucket_name     = "${var.project_name}-${var.build_bucket_suffix}-${var.environment}"
  
  # Common resource name prefix
  name_prefix = "${var.project_name}-${var.environment}"
}