
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

resource "random_string" "suffix" {
  length  = 18
  upper   = false
  special = false
}

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
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.scripts.arn,
          "${aws_s3_bucket.scripts.arn}/*"
        ]
      },
      {
        Sid    = "S3WriteOutput"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*"
        ]
      },
      {
        Sid    = "S3TempAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
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

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}
resource "aws_iam_role_policy_attachment" "glue_admin_access" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

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






provider "aws" {
  region = var.aws_region
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-security-group"
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
}

resource "aws_db_instance" "postgres_db" {
  identifier             = var.db_identifier
  allocated_storage      = var.allocated_storage

  engine                 = "postgres"
  engine_version         = "16.3"

  instance_class         = var.instance_class

  username               = var.db_username
  password               = var.db_password

  db_name                = var.db_name
  port                   = 5432

  publicly_accessible    = true
  skip_final_snapshot    = true
  deletion_protection    = false

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
}
