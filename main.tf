# Define local variables
locals {
  name           = "reka-cloudproject"
  codeConnection = "arn:aws:codeconnections:eu-west-1:774023531476:connection/f2d3434b-731c-4533-8621-973555b81a84"
  repository     = "rekabojtor/cloud_project_website"
}

# Creating an S3 bucket resource
resource "aws_s3_bucket" "main" {
  bucket = local.name
}

# Enabling public access to the S3 bucket
# (because by default it is blocked for public access due to security)
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Allow access to anyone to do GetObject action on index.html from the S3 bucket
resource "aws_s3_bucket_policy" "index_public" {
  bucket = aws_s3_bucket.main.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowPublicReadIndexObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.main.arn}/index.html"
      }
    ]
  })
}

# Allow assumption of this role for the codepipeline
resource "aws_iam_role" "reka_git_to_s3_pipeline_role" {
  name = "${local.name}-git-to-s3-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "codepipeline.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Defining policy for the codepipeline for GitHub access and S3 bucket access
resource "aws_iam_role_policy" "reka_git_to_s3_pipeline_policy" {
  name = "${local.name}-git-to-s3-pipeline-policy"
  role = aws_iam_role.reka_git_to_s3_pipeline_role.id

  policy = jsonencode(
    # Allows any S3 action on the S3 bucket and all resources inside the S3 bucket
    # This allows the index.html file to be uploaded in the bucket
    {
      Version = "2012-10-17",
      Statement = [
        {
          Sid    = "AllowS3ArtifactAndDeploy",
          Effect = "Allow",
          Action = [
            "s3:*"
          ],
          Resource = [
            "${aws_s3_bucket.main.arn}",
            "${aws_s3_bucket.main.arn}/*"
          ]
        },
        # Allows using UseConnection action from codestar-connections service to my codestar GitHub connection
        # This allows GitHub access
        {
          Sid    = "UseCodeStarConnection",
          Effect = "Allow",
          Action = [
            "codestar-connections:UseConnection"
          ],
          Resource = [local.codeConnection]
        }
      ]
  })
}

# Configuring the codepipeline to download from GitHub and upload to S3 bucket
resource "aws_codepipeline" "reka_git_to_s3_pipeline" {
  name     = "${local.name}-git-to-s3-pipeline"
  role_arn = aws_iam_role.reka_git_to_s3_pipeline_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.main.bucket
  }
  
  stage {
    name = "Source"

    # Codepipeline downloads from GitHub
    action {
      name             = "DownloadFromGitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = local.codeConnection
        FullRepositoryId = local.repository
        BranchName       = "main"
      }
    }
  }

  stage {
    name = "Deploy"

    # Codepipeline unzips the downloaded file from GitHub and uploads to the S3 bucket
    action {
      name            = "UploadToS3Bucket"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        BucketName = aws_s3_bucket.main.bucket
        Extract    = "true"
      }
    }
  }
}
