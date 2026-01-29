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
# GLUE WORKFLOW FOR AUTOMATION
# ----------------

resource "aws_glue_workflow" "pipeline_workflow" {
  name = "reviews-pipeline-workflow"
  description = "Automated pipeline for reviews data processing"
}

resource "aws_glue_trigger" "start_raw_crawler" {
  name          = "start-raw-crawler-trigger"
  type          = "SCHEDULED"
  schedule      = "cron(0 9 ? * MON *)"
  workflow_name = aws_glue_workflow.pipeline_workflow.name

  actions {
    crawler_name = aws_glue_crawler.raw.name
  }
}

resource "aws_glue_trigger" "start_raw_to_processed_job" {
  name          = "start-raw-to-processed-job-trigger"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.pipeline_workflow.name

  predicate {
    conditions {
      crawler_name = aws_glue_crawler.raw.name
      crawl_state  = "SUCCEEDED"
    }
  }

  actions {
    job_name = aws_glue_job.raw_to_processed.name
  }
}

resource "aws_glue_trigger" "start_processed_crawler" {
  name          = "start-processed-crawler-trigger"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.pipeline_workflow.name

  predicate {
    conditions {
      job_name = aws_glue_job.raw_to_processed.name
      state    = "SUCCEEDED"
    }
  }

  actions {
    crawler_name = aws_glue_crawler.processed.name
  }
}

resource "aws_glue_trigger" "start_processed_to_final_job" {
  name          = "start-processed-to-final-job-trigger"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.pipeline_workflow.name

  predicate {
    conditions {
      crawler_name = aws_glue_crawler.processed.name
      crawl_state  = "SUCCEEDED"
    }
  }

  actions {
    job_name = aws_glue_job.processed_to_final.name
  }
}

resource "aws_glue_trigger" "start_final_crawler" {
  name          = "start-final-crawler-trigger"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.pipeline_workflow.name

  predicate {
    conditions {
      job_name = aws_glue_job.processed_to_final.name
      state    = "SUCCEEDED"
    }
  }

  actions {
    crawler_name = aws_glue_crawler.final.name
  }
}
