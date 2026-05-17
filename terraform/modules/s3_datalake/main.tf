resource "aws_s3_bucket" "data_lake" {
  bucket = "smart-city-platform-data-lake"

  tags = {
    Project = "smart-city-platform"
    Env     = "sandbox"
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.data_lake.id

  versioning_configuration {
    status = "Enabled"
  }
}