output "scripts_bucket_name" {
  value = aws_s3_bucket.scripts.id
}

output "scripts_bucket_arn" {
  value = aws_s3_bucket.scripts.arn
}

output "output_bucket_name" {
  value = aws_s3_bucket.output.id
}

output "output_bucket_arn" {
  value = aws_s3_bucket.output.arn
}

output "temp_bucket_name" {
  value       = var.create_temp_bucket ? aws_s3_bucket.temp[0].id : null
  description = "Optional temp bucket name."
}

output "temp_bucket_arn" {
  value       = var.create_temp_bucket ? aws_s3_bucket.temp[0].arn : null
  description = "Optional temp bucket ARN."
}

output "glue_script_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.bucket}/scripts/glue_etl_test.py"
}

output "glue_script_product_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.bucket}/scripts/glue_product_etl.py"
}

output "glue_job_name" {
  value = aws_glue_job.etl.id
}

output "glue_job_arn" {
  value = aws_glue_job.etl.arn
}

output "glue_job_product_name" {
  description = "Product Glue job name"
  value       = aws_glue_job.etl_product.name
}

output "glue_job_product_arn" {
  description = "Product Glue job ARN"
  value       = aws_glue_job.etl_product.arn
}

output "glue_role_name" {
  value = aws_iam_role.glue.name
}

output "glue_role_arn" {
  value = aws_iam_role.glue.arn
}

output "random_suffix" {
  value = random_string.suffix.result
}


output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.postgres_db.endpoint
}

output "rds_port" {
  description = "RDS port"
  value       = aws_db_instance.postgres_db.port
}


output "rds_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.postgres_db.identifier
}

output "database_name" {
  description = "Database name"
  value       = aws_db_instance.postgres_db.db_name
}

output "database_username" {
  description = "Database username"
  value       = aws_db_instance.postgres_db.username
}

output "database_password" {
  description = "Database password (généré aléatoirement)"
  value       = random_string.db_password.result
  sensitive   = true
}
