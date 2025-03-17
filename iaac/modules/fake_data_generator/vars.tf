variable "resources_name_prefix" {
   description = "Prefix for the resource names"
   type = string
}

variable "data_lake_bucket_name" {
  type = string
}

variable "raw_data_folder" {
  type = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}


variable "num_users" {
  type = number
  default = 100000
}

variable "rows_per_file" {
  type = number
  default = 1000000
}

variable "num_files_per_day" {
  type = number
  default = 5
}

variable "num_api_days" {
  type = number
  default = 10
}

variable "max_days_backward" {
  type = number
  default = 5
}