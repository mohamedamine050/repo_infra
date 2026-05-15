variable "aws_region" {
  type        = string
  description = "AWS region to deploy into."
  default     = "us-east-1"
}

variable "create_temp_bucket" {
  type        = bool
  description = "Whether to create an optional temp bucket for Glue staging."
  default     = false
}



variable "db_identifier" {
  type        = string
  description = "RDS identifier"
  default     = "postgres-rds"
}

variable "db_name" {
  type        = string
  description = "Database name"
  default     = "mydatabase"
}

variable "db_username" {
  type        = string
  description = "Database username"
  default     = "admin"
}

variable "db_password" {
  type        = string
  description = "Database password"
  sensitive   = true
}

variable "instance_class" {
  type        = string
  description = "RDS instance class"
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  type        = number
  description = "Storage size in GB"
  default     = 20
}
