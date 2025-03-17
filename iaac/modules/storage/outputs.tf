output "data_lake_bucket_name" {
    value = aws_s3_bucket.data_lake.bucket
}

output "build_storage_bucket_name" {
    value = aws_s3_bucket.build_storage.bucket
}