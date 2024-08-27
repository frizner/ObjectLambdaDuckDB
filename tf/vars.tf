variable "owner" {
  description = "Owner of a deployment/workload"
  type        = string
  default     = "john"
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment"
  type        = string
  default     = "demo"
}

variable "bucket_name" {
  description = "Name of the bucket for a dataset"
  type        = string
  default     = "objectlambda-dataset"
}

variable "logs_retention_in_days" {
  description = "Specifies the number of days you want to retain log events in a log group for Object Lambda function."
  type        = number
  default     = 3
}

variable "lambda_ram" {
  description = "RAM for Object Lambda function"
  type        = number
  default     = 256
}

variable "lambda_storage" {
  description = "Storage for Object Lambda function"
  type        = number
  default     = 512
}