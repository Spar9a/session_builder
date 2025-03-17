variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "resources_name_prefix" {
   description = "Prefix for the resource names"
   type = string
}

variable "session_builder_workflow_arn" {
  type        = string
}

variable "processing_schedule" {
  description = "Cron schedule for the processing job"
  type = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment to deploy to"
  type        = string
}

variable "project_name" {
  description = "Project name for resource names"
  type        = string
}