# Define local variables
locals {
  name           = "reka-puppies"
  codeConnection = "arn:aws:codeconnections:eu-west-1:774023531476:connection/f2d3434b-731c-4533-8621-973555b81a84"
  repository     = "rekabojtor/cloud_project_website"
}

# Creating an S3 bucket resource
resource "aws_s3_bucket" "main" {
  bucket = local.name
}

# Configuring the S3 bucket to be able to accessed by public users
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
        Resource = [
          "${aws_s3_bucket.main.arn}/index.html",
          "${aws_s3_bucket.main.arn}/gemini.txt"
        ]
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

    # Codepipeline downloads from GitHub repository as a zip file
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

# Creating a role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Defining policy for the Lambda function role
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode(
    # Allows PutObject (and overwrite) action on gemini.txt in the main S3 bucket
    {
      Version = "2012-10-17",
      Statement = [
        {
          Sid    = "AllowS3Write",
          Effect = "Allow",
          Action = [
            "s3:PutObject"
          ],
          Resource = [
            "${aws_s3_bucket.main.arn}/gemini.txt"
          ]
        },
        # Allow reading secrets from Secrets Manager
        {
          Sid    = "AccessSecretsManager",
          Effect = "Allow",
          Action = [
            "secretsmanager:GetSecretValue"
          ],
          Resource = ["*"]
        }
      ]
  })
}

# Creating a Secrets Manager secret to store the Gemini API key
resource "aws_secretsmanager_secret" "gemini_api_key" {
  name = "${local.name}-gemini-api-key"
}

# Storing the Gemini API key from the .gemini_api_key file into the Secrets Manager secret
resource "aws_secretsmanager_secret_version" "gemini_api_key_version" {
  secret_id     = aws_secretsmanager_secret.gemini_api_key.id
  secret_string = file(".gemini_api_key")
}

# Creating the Lambda function to call Gemini API and store the result in the main S3 bucket
resource "aws_lambda_function" "gemini_api_call" {
  function_name = "${local.name}-gemini-api-call"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.13"
  filename      = "./gemini_api_call/lambda_function.zip"

  # Setting environment variables for the Lambda function
  environment {
    variables = {
      BUCKET_NAME        = aws_s3_bucket.main.bucket
      GEMINI_API_KEY_ARN = aws_secretsmanager_secret.gemini_api_key.arn
    }
  }
}

# Creating a CloudWatch EventBridge rule to trigger the Lambda function daily
resource "aws_cloudwatch_event_rule" "gemini_api_trigger_rule" {
  name                = "${local.name}-trigger-rule"
  schedule_expression = "rate(1 day)"
}

# Adding the Lambda function as a target for the EventBridge rule
resource "aws_cloudwatch_event_target" "gemini_api_trigger_target" {
  rule      = aws_cloudwatch_event_rule.gemini_api_trigger_rule.name
  target_id = "${local.name}-trigger-target"
  arn       = aws_lambda_function.gemini_api_call.arn
}

# Granting permission by the Lambda function to be invoked by EventBridge
resource "aws_lambda_permission" "allow_eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridgeDailyRate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.gemini_api_call.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.gemini_api_trigger_rule.arn
}