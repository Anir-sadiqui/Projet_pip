variable "region" {
  default = "us-east-1"
}

variable "raw_bucket" {
  description = "S3 bucket name for raw data"
}

variable "processed_bucket" {
  description = "S3 bucket name for processed data"
}

variable "final_bucket" {
  description = "S3 bucket name for final data"
}


