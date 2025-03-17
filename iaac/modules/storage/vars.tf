variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "data_lake_bucket_name" {
  type = string
}

variable "raw_data_folder" {
  type = string
}

variable "deltalake_folder" {
  type = string
}

variable "processed_data_folder" {
  type = string
}

variable "build_storage_bucket_name" {
  type = string
}