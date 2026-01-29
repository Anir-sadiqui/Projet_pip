provider "aws" {
  region = var.region
  # AWS Academy requires session token authentication
  # These will be set via environment variables or terraform.tfvars
}

# ----------------
# S3 BUCKETS
# ----------------

resource "aws_s3_bucket" "raw" {
  bucket = var.raw_bucket
}

resource "aws_s3_bucket" "processed" {
  bucket = var.processed_bucket
}

resource "aws_s3_bucket" "final" {
  bucket = var.final_bucket
}

# ----------------
# UPLOAD RAW DATA
# ----------------

resource "aws_s3_object" "raw_data" {
  bucket = aws_s3_bucket.raw.bucket
  key    = "raw/reviews.csv"
  source = "./data/reviews.csv"
  etag   = filemd5("./data/reviews.csv")
}

# ----------------
# UPLOAD GLUE SCRIPTS
# ----------------

resource "aws_s3_object" "raw_to_processed_script" {
  bucket = aws_s3_bucket.raw.bucket
  key    = "scripts/raw_to_processed.py"
  source = "./raw_to_processed.py"
  etag   = filemd5("./raw_to_processed.py")
}

resource "aws_s3_object" "processed_to_final_script" {
  bucket = aws_s3_bucket.raw.bucket
  key    = "scripts/processed_to_final.py"
  source = "./processed_to_final.py"
  etag   = filemd5("./processed_to_final.py")
}

# ----------------
# GLUE DATABASES
# ----------------

resource "aws_glue_catalog_database" "raw_db" {
  name = "reviews_raw_db"
}

resource "aws_glue_catalog_database" "processed_db" {
  name = "reviews_processed_db"
}

resource "aws_glue_catalog_database" "final_db" {
  name = "reviews_final_db"
}

# ----------------
# IAM ROLE DATA SOURCE (use existing LabRole)
# ----------------

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# ----------------
# DATA SOURCE FOR ACCOUNT ID
# ----------------

data "aws_caller_identity" "current" {}

# ----------------
# GLUE JOBS
# ----------------

resource "aws_glue_job" "raw_to_processed" {
  name     = "raw-to-processed-job"
  role_arn = data.aws_iam_role.lab_role.arn
  
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.raw.bucket}/scripts/raw_to_processed.py"
    python_version  = "3"
  }
  
  glue_version = "4.0"
  number_of_workers = 2
  worker_type = "G.1X"
  
  default_arguments = {
    "--job-language"        = "python"
    "--enable-job-insights" = "true"
  }
  
  depends_on = [aws_s3_object.raw_to_processed_script]
}

resource "aws_glue_job" "processed_to_final" {
  name     = "processed-to-final-job"
  role_arn = data.aws_iam_role.lab_role.arn
  
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.raw.bucket}/scripts/processed_to_final.py"
    python_version  = "3"
  }
  
  glue_version = "4.0"
  number_of_workers = 2
  worker_type = "G.1X"
  
  default_arguments = {
    "--job-language"        = "python"
    "--enable-job-insights" = "true"
  }
  
  depends_on = [aws_s3_object.processed_to_final_script]
}

# ----------------
# CRAWLERS
# ----------------

resource "aws_glue_crawler" "raw" {
  name          = "crawler-raw"
  role          = data.aws_iam_role.lab_role.arn
  database_name = aws_glue_catalog_database.raw_db.name

  s3_target {
    path = "s3://${aws_s3_bucket.raw.bucket}/raw/"
  }

  table_prefix = "raw_"
  
  depends_on = [aws_s3_object.raw_data]
}

resource "aws_glue_crawler" "processed" {
  name          = "crawler-processed"
  role          = data.aws_iam_role.lab_role.arn
  database_name = aws_glue_catalog_database.processed_db.name

  s3_target {
    path = "s3://${aws_s3_bucket.processed.bucket}/processed/"
  }

  table_prefix = "processed_"
}

resource "aws_glue_crawler" "final" {
  name          = "crawler-final"
  role          = data.aws_iam_role.lab_role.arn
  database_name = aws_glue_catalog_database.final_db.name

  s3_target {
    path = "s3://${aws_s3_bucket.final.bucket}/final/"
  }

  table_prefix = "final_"
}

# ----------------
# SCHEDULED PIPELINE AUTOMATION
# ----------------

# EventBridge Rule: Run pipeline every week (Monday at 9 AM UTC)
resource "aws_cloudwatch_event_rule" "weekly_pipeline" {
  name                = "weekly-pipeline-trigger"
  description         = "Triggers pipeline every Monday at 9:00 AM UTC"
  schedule_expression = "cron(0 9 ? * MON *)"
}

# Target: Start raw crawler
resource "aws_cloudwatch_event_target" "weekly_start_raw_crawler" {
  rule      = aws_cloudwatch_event_rule.weekly_pipeline.name
  target_id = "StartRawCrawler"
  arn       = "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:crawler/${aws_glue_crawler.raw.name}"
  role_arn  = data.aws_iam_role.lab_role.arn
}

# EventBridge Rule: Trigger when raw crawler succeeds
resource "aws_cloudwatch_event_rule" "raw_crawler_success" {
  name        = "raw-crawler-success"
  description = "Triggers when raw crawler completes successfully"

  event_pattern = jsonencode({
    source      = ["aws.glue"]
    detail-type = ["Glue Crawler State Change"]
    detail = {
      crawlerName = [aws_glue_crawler.raw.name]
      state       = ["Succeeded"]
    }
  })
}

# Target: Start raw-to-processed job
resource "aws_cloudwatch_event_target" "start_raw_to_processed_job" {
  rule      = aws_cloudwatch_event_rule.raw_crawler_success.name
  target_id = "StartRawToProcessedJob"
  arn       = aws_glue_job.raw_to_processed.arn
  role_arn  = data.aws_iam_role.lab_role.arn

  retry_policy {
    maximum_event_age       = 3600
    maximum_retry_attempts  = 2
  }
}

# EventBridge Rule: Trigger when raw-to-processed job succeeds
resource "aws_cloudwatch_event_rule" "raw_to_processed_job_success" {
  name        = "raw-to-processed-job-success"
  description = "Triggers when raw-to-processed job completes successfully"

  event_pattern = jsonencode({
    source      = ["aws.glue"]
    detail-type = ["Glue Job State Change"]
    detail = {
      jobName = [aws_glue_job.raw_to_processed.name]
      state   = ["SUCCEEDED"]
    }
  })
}

# Target: Start processed crawler
resource "aws_cloudwatch_event_target" "start_processed_crawler" {
  rule      = aws_cloudwatch_event_rule.raw_to_processed_job_success.name
  target_id = "StartProcessedCrawler"
  arn       = "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:crawler/${aws_glue_crawler.processed.name}"
  role_arn  = data.aws_iam_role.lab_role.arn
}

# EventBridge Rule: Trigger when processed crawler succeeds
resource "aws_cloudwatch_event_rule" "processed_crawler_success" {
  name        = "processed-crawler-success"
  description = "Triggers when processed crawler completes successfully"

  event_pattern = jsonencode({
    source      = ["aws.glue"]
    detail-type = ["Glue Crawler State Change"]
    detail = {
      crawlerName = [aws_glue_crawler.processed.name]
      state       = ["Succeeded"]
    }
  })
}

# Target: Start processed-to-final job
resource "aws_cloudwatch_event_target" "start_processed_to_final_job" {
  rule      = aws_cloudwatch_event_rule.processed_crawler_success.name
  target_id = "StartProcessedToFinalJob"
  arn       = aws_glue_job.processed_to_final.arn
  role_arn  = data.aws_iam_role.lab_role.arn

  retry_policy {
    maximum_event_age       = 3600
    maximum_retry_attempts  = 2
  }
}

# EventBridge Rule: Trigger when processed-to-final job succeeds
resource "aws_cloudwatch_event_rule" "processed_to_final_job_success" {
  name        = "processed-to-final-job-success"
  description = "Triggers when processed-to-final job completes successfully"

  event_pattern = jsonencode({
    source      = ["aws.glue"]
    detail-type = ["Glue Job State Change"]
    detail = {
      jobName = [aws_glue_job.processed_to_final.name]
      state   = ["SUCCEEDED"]
    }
  })
}

# Target: Start final crawler
resource "aws_cloudwatch_event_target" "start_final_crawler" {
  rule      = aws_cloudwatch_event_rule.processed_to_final_job_success.name
  target_id = "StartFinalCrawler"
  arn       = "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:crawler/${aws_glue_crawler.final.name}"
  role_arn  = data.aws_iam_role.lab_role.arn
}
