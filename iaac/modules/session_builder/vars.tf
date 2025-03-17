# Variables for the networking module

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "resources_name_prefix" {
   description = "Prefix for the resource names"
   type = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "data_lake_bucket_name" {
  type = string
}

variable "data_lake_bucket_arn" {
  type = string
}

variable "raw_data_folder_name" {
  type = string
}

variable "processed_data_folder_name" {
  type = string 
}

variable "deltalake_folder_name" {
  type = string 
}

variable "build_storage_bucket_name" {
  type = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "worker_count" {
  type = number
}

variable "spark_ami_id" {
  type = string
}

variable "worker_instance_type" {
  type = string
}

variable "master_instance_type" {
  type = string
}

variable "private_subnet_id" {
  type = string
}