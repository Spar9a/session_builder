# Input variables for the Session Builder Terraform project

variable "project_name" {
  description = "Name of the application"
  type        = string
  default     = "session-builder"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "data_lake_bucket_suffix" {
  description = "Suffix for the data lake bucket name"
  type        = string
  default     = "data-lake"
}

# Storage variables
variable "raw_data_data_folder" {
  description = "Raw data folder name"
  type        = string
  default     = "raw"
}

# Storage variables
variable "deltalake_folder_name" {
  description = "Deltalake table folder name"
  type        = string
  default     = "deltalake"
}

# Storage variables
variable "processed_data_folder_name" {
  description = "Processed folder name"
  type        = string
  default     = "processed"
}

variable "build_bucket_suffix" {
  description = "Suffix for the code bucket"
  type        = string
  default     = "builds"
}

# Compute variables
variable "spark_ami_id" {
  description = "AMI ID for Spark instances"
  type        = string
  default     = "ami-0885b1f6bd170450c"
}

variable "master_instance_type" {
  description = "EC2 instance type for Spark master"
  type        = string
  default     = "m5.xlarge"
}

variable "worker_instance_type" {
  description = "EC2 instance type for Spark workers"
  type        = string
  default     = "m5.large"
}

variable "worker_count" {
  description = "Number of Spark worker instances"
  type        = number
  default     = 2
}

# Networking variables
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# Orchestration variables
variable "schedule_expression" {
  description = "Schedule expression for EventBridge rule"
  type        = string
  default     = "cron(0 3 * * ? *)"
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}