resource "aws_s3_bucket" "data_lake" {
  bucket = lower("${var.data_lake_bucket_name}")
  tags = var.tags
}

resource "aws_s3_bucket" "build_storage" {
  bucket = lower("${var.build_storage_bucket_name}")
  tags = var.tags
}

resource "aws_s3_object" "data_folders" {
  for_each = toset([
    var.raw_data_folder,
    var.deltalake_folder,
    var.processed_data_folder,
  ])

  bucket  = aws_s3_bucket.data_lake.id
  key     = "${each.value}/"
  content = ""
}


resource "aws_s3_bucket_versioning" "data_lake_versioning" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Disabled"
  }
}

# Block public access for both buckets
resource "aws_s3_bucket_public_access_block" "data_lake_block" {
  bucket = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}