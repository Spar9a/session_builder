# Development environment variables
environment = "dev"
aws_region = "us-east-1"

# Compute settings for dev environment
master_instance_type = "m5.xlarge"
worker_instance_type = "m5.large"
spark_ami_id = "ami-0885b1f6bd170450c"
worker_count = 1

# Schedule for dev environment (daily at 3 AM UTC)
schedule_expression = "cron(0 3 * * ? *)"

processed_paths_table_name = "processed-paths"

# Additional tags for dev environment
tags = {
  Owner       = "Data Office"
  CostCenter  = "DE123"
  Project     = "SessionBuilder"
}

## Data Faker config
DATA_FAKER_NUM_USERS=10000
DATA_FAKER_ROWS_PER_FILE=1000000
DATA_FAKER_NUM_FILES_PER_DAY=6
DATA_FAKER_NUM_API_DAYS=30
DATA_FAKER_MAX_DAYS_BACKWARD=15