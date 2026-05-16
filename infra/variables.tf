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



