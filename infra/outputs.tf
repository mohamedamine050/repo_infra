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

output "glue_job_name" {
  value = aws_glue_job.etl.id
}

output "glue_job_arn" {
  value = aws_glue_job.etl.arn
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