# ─────────────────────────────────────────────────────────────────────────────
# Remote backend — state stored in S3, locking via DynamoDB
# (Provisioned by the bootstrap/ folder)
# ─────────────────────────────────────────────────────────────────────────────
terraform {
  backend "s3" {
    bucket         = "tfstate-etl-spark-pipelineghaith-py2mlgjz"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tflock-etl-spark-pipelineghaith-py2mlgjz"
    encrypt        = true
  }
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─────────────────────────────────────────────────────────────────────────────
# Data sources
# ─────────────────────────────────────────────────────────────────────────────
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Random suffix
# ─────────────────────────────────────────────────────────────────────────────
resource "random_string" "suffix" {
  length  = 18
  upper   = false
  special = false
}

# ─────────────────────────────────────────────────────────────────────────────
# S3 Buckets
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "scripts" {
  bucket        = "data-pipeline-scripts-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket" "output" {
  bucket        = "data-pipeline-output-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket" "temp" {
  count         = var.create_temp_bucket ? 1 : 0
  bucket        = "data-pipeline-temp-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "scripts" {
  bucket = aws_s3_bucket.scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "temp" {
  count  = var.create_temp_bucket ? 1 : 0
  bucket = aws_s3_bucket.temp[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "scripts" {
  bucket = aws_s3_bucket.scripts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "temp" {
  count  = var.create_temp_bucket ? 1 : 0
  bucket = aws_s3_bucket.temp[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "scripts" {
  bucket                  = aws_s3_bucket.scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "output" {
  bucket                  = aws_s3_bucket.output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "temp" {
  count                   = var.create_temp_bucket ? 1 : 0
  bucket                  = aws_s3_bucket.temp[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Glue scripts (local files + S3 upload)
# ─────────────────────────────────────────────────────────────────────────────
resource "local_file" "glue_script" {
  filename = "${path.module}/glue_etl_test.py"
  content  = <<-EOT
print("Hello from TEST script")
EOT
}

data "archive_file" "glue_script_zip" {
  type        = "zip"
  source_file = local_file.glue_script.filename
  output_path = "${path.module}/glue_etl_test.zip"
}

resource "aws_s3_object" "glue_script" {
  bucket       = aws_s3_bucket.scripts.id
  key          = "scripts/glue_etl_test.py"
  source       = local_file.glue_script.filename
  content_type = "text/x-python"
}

resource "local_file" "glue_script_product" {
  filename = "${path.module}/glue_product_etl.py"
  content  = <<-EOT
print("Hello from PRODUCT Glue script")
EOT
}

resource "aws_s3_object" "glue_script_product" {
  bucket       = aws_s3_bucket.scripts.id
  key          = "scripts/glue_product_etl.py"
  source       = local_file.glue_script_product.filename
  content_type = "text/x-python"
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM — Glue
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "glue" {
  name = "data-pipeline-glue-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "glue" {
  name = "data-pipeline-glue-policy-${random_string.suffix.result}"
  role = aws_iam_role.glue.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadScripts"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.scripts.arn,
          "${aws_s3_bucket.scripts.arn}/*"
        ]
      },
      {
        Sid    = "S3WriteOutput"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*"
        ]
      },
      {
        Sid    = "S3TempAccess"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = var.create_temp_bucket ? [
          aws_s3_bucket.temp[0].arn,
          "${aws_s3_bucket.temp[0].arn}/*"
          ] : [
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*"
        ]
      },
      {
        Sid    = "GlueLogging"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_admin_access" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ─────────────────────────────────────────────────────────────────────────────
# Glue Jobs
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_glue_job" "etl" {
  name              = "data-pipeline-etl-${random_string.suffix.result}"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "5.0"
  number_of_workers = 2
  worker_type       = "G.1X"
  timeout           = 60
  max_retries       = 0
  execution_class   = "STANDARD"

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.bucket}/scripts/glue_etl_test.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = ""
    "--TempDir"                          = var.create_temp_bucket ? "s3://${aws_s3_bucket.temp[0].bucket}/temp/" : "s3://${aws_s3_bucket.output.bucket}/temp/"
    "--output_path"                      = "s3://${aws_s3_bucket.output.bucket}/output/"
  }

  depends_on = [
    aws_s3_bucket.scripts,
    aws_s3_bucket.output,
    aws_s3_object.glue_script
  ]
}

resource "aws_glue_job" "etl_product" {
  name              = "data-pipeline-etl-product-${random_string.suffix.result}"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "5.0"
  number_of_workers = 2
  worker_type       = "G.1X"
  timeout           = 60
  max_retries       = 0
  execution_class   = "STANDARD"

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.bucket}/scripts/glue_product_etl.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = ""
    "--TempDir"                          = var.create_temp_bucket ? "s3://${aws_s3_bucket.temp[0].bucket}/temp/" : "s3://${aws_s3_bucket.output.bucket}/temp/"
    "--output_path"                      = "s3://${aws_s3_bucket.output.bucket}/output/"
  }

  depends_on = [
    aws_s3_bucket.scripts,
    aws_s3_bucket.output,
    aws_s3_object.glue_script_product
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM — Lambda
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "lambda-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "lambda-policy-${random_string.suffix.result}"
  role = aws_iam_role.lambda.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadLambdaZip"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.scripts.arn}/lambda/*"
      },
      {
        Sid    = "S3WriteOutput"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*"
        ]
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Lambda Function
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_lambda_function" "api_fetcher" {
  s3_bucket     = aws_s3_bucket.scripts.bucket
  s3_key        = "lambda/lambda_function.zip"
  function_name = "api-fetcher-${random_string.suffix.result}"
  role          = aws_iam_role.lambda.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 60

  depends_on = [
    aws_s3_bucket.scripts,
    aws_s3_bucket.output,
    aws_iam_role_policy.lambda
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM — Step Functions
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "step_functions" {
  name = "step-functions-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "step_functions" {
  name = "step-functions-policy-${random_string.suffix.result}"
  role = aws_iam_role.step_functions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GlueJobAccess"
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "glue:BatchStopJobRun"
        ]
        Resource = "*"
      },
      {
        Sid      = "LambdaInvoke"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.api_fetcher.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Step Functions — ETL Pipeline
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_sfn_state_machine" "etl_pipeline" {
  name     = "etl-pipeline-${random_string.suffix.result}"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "ETL Pipeline: Lambda fetch → Glue test → Glue product"
    StartAt = "FetchRawData"
    States = {
      FetchRawData = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.api_fetcher.arn
          Payload      = {}
        }
        ResultPath = "$.lambdaResult"
        Next       = "RunTestETL"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PipelineFailed"
        }]
      }
      RunTestETL = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.etl.name
        }
        ResultPath = "$.glueTestResult"
        Next       = "RunProductETL"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PipelineFailed"
        }]
      }
      RunProductETL = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.etl_product.name
        }
        ResultPath = "$.glueProductResult"
        Next       = "PipelineSucceeded"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PipelineFailed"
        }]
      }
      PipelineSucceeded = {
        Type = "Succeed"
      }
      PipelineFailed = {
        Type  = "Fail"
        Error = "ETLPipelineError"
        Cause = "One or more steps failed"
      }
    }
  })

  depends_on = [
    aws_lambda_function.api_fetcher,
    aws_glue_job.etl,
    aws_glue_job.etl_product
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM — EventBridge
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "eventbridge" {
  name = "eventbridge-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge" {
  name = "eventbridge-policy-${random_string.suffix.result}"
  role = aws_iam_role.eventbridge.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "StartStepFunctions"
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = aws_sfn_state_machine.etl_pipeline.arn
    }]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# EventBridge — Schedule Step Functions toutes les heures
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_event_rule" "hourly" {
  name                = "etl-pipeline-hourly-${random_string.suffix.result}"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "step_functions" {
  rule     = aws_cloudwatch_event_rule.hourly.name
  arn      = aws_sfn_state_machine.etl_pipeline.arn
  role_arn = aws_iam_role.eventbridge.arn
}

# ─────────────────────────────────────────────────────────────────────────────
# RDS (PostgreSQL)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "rds_sg" {
  name        = "rds-security-group-${random_string.suffix.result}"
  description = "Security group for RDS"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-security-group"
  }
}

resource "random_string" "db_identifier" {
  length  = 8
  upper   = false
  special = false
}

resource "random_string" "db_name_suffix" {
  length  = 6
  upper   = false
  numeric = true
  special = false
}

resource "random_string" "db_username_suffix" {
  length  = 8
  upper   = false
  numeric = true
  special = false
}

resource "random_string" "db_password" {
  length  = 16
  upper   = true
  special = true
}

locals {
  db_name     = "db${random_string.db_name_suffix.result}"
  db_username = "db${random_string.db_username_suffix.result}"
}

resource "aws_db_instance" "postgres_db" {
  identifier        = "db-${random_string.db_identifier.result}"
  allocated_storage = 20

  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.t3.micro"

  username = local.db_username
  password = random_string.db_password.result

  db_name = local.db_name
  port    = 5432

  publicly_accessible  = true
  skip_final_snapshot  = true
  deletion_protection  = false

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
}
