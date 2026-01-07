locals {
  name           = "reka-cloudproject"
  codeConnection = "arn:aws:codeconnections:eu-west-1:774023531476:connection/f2d3434b-731c-4533-8621-973555b81a84"
  repository     = "rekabojtor/cloud_project_website"
}

resource "aws_s3_bucket" "main" {
  bucket = local.name
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
        Sid       = "AllowPublicReadIndexObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.main.arn}/index.html"
      }
    ]
  })
}


// CodePipeline: reka-git-to-s3-pipeline
// Service role for the pipeline
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

resource "aws_iam_role_policy" "reka_git_to_s3_pipeline_policy" {
  name = "${local.name}-git-to-s3-pipeline-policy"
  role = aws_iam_role.reka_git_to_s3_pipeline_role.id

  policy = jsonencode({
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

resource "aws_codepipeline" "reka_git_to_s3_pipeline" {
  name     = "${local.name}-git-to-s3-pipeline"
  role_arn = aws_iam_role.reka_git_to_s3_pipeline_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.main.bucket
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
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

    action {
      name            = "DeployToS3"
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


