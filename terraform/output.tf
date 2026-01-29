output "raw_bucket" {
  value = aws_s3_bucket.raw.bucket
}

output "processed_bucket" {
  value = aws_s3_bucket.processed.bucket
}

output "final_bucket" {
  value = aws_s3_bucket.final.bucket
}

output "lab_role_arn" {
  value = data.aws_iam_role.lab_role.arn
}

output "raw_database" {
  value = aws_glue_catalog_database.raw_db.name
}

output "processed_database" {
  value = aws_glue_catalog_database.processed_db.name
}

output "final_database" {
  value = aws_glue_catalog_database.final_db.name
}
