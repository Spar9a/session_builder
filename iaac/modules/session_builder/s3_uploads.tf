# Upload Spark job script to S3
resource "aws_s3_object" "session_builder_script" {
  bucket = var.build_storage_bucket_name
  key    = "session_builder.py"
  source = "${path.module}/files/spark/session_builder.py"
  etag   = filemd5("${path.module}/files/spark/session_builder.py")
}