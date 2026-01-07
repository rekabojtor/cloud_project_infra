resource "aws_s3_bucket" "main" {
  bucket = "reka-cloud-project"

  tags = {
    Name = "reka_cloud_project"
  }
}

# Allow a public bucket policy (we keep the ability to attach a public policy but do not make the whole bucket public)
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  # Allow public policies and ACLs at the bucket level so we can make only a single object public
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Bucket policy that only allows public read (GetObject) for the single object index.html
resource "aws_s3_bucket_policy" "index_public" {
  bucket = aws_s3_bucket.main.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "AllowPublicReadIndexObject",
        Effect = "Allow",
        Principal = "*",
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.main.arn}/index.html"
      }
    ]
  })
}

