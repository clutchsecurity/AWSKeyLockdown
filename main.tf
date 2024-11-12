# Provider configuration for AWS
provider "aws" {
  region = var.aws_region # Dynamically set the region from a variable
  profile = var.aws_profile # Uses a specific AWS profile from your configuration
}

# Provider for generating random strings
provider "random" {}

# Fetch current AWS account details
data "aws_caller_identity" "current" {}

# Generate a random string for creating unique names
resource "random_string" "random" {
  length  = 8
  special = false
  upper   = false
}

# Package the Lambda function code into a ZIP file
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function_payload.zip"
}

# IAM role for Lambda function with a unique name
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role-${random_string.random.result}"

  # IAM policy that allows the Lambda function to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# IAM policy attached to the Lambda role
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy-${random_string.random.result}"
  role = aws_iam_role.lambda_execution_role.id

  # Policy definitions for logging and IAM access
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${aws_lambda_function.iam_access_key_deactivator.function_name}:*"
      },
      {
        Action = [
          "iam:UpdateAccessKey",
          "iam:ListAccessKeys"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

# Lambda function resource
resource "aws_lambda_function" "iam_access_key_deactivator" {
  filename         = "lambda_function_payload.zip"
  function_name    = "iam_access_key_deactivator-${random_string.random.result}"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8"

  source_code_hash = filebase64sha256(data.archive_file.lambda.output_path)
}

# CloudWatch Event Rule to trigger Lambda on IAM policy attachments
resource "aws_cloudwatch_event_rule" "iam_policy_attachment" {
  name        = "iam-policy-attachment-${random_string.random.result}"
  description = "Monitors IAM policy attachments."

  event_pattern = jsonencode({
    source      = ["aws.iam"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["AttachUserPolicy", "AttachGroupPolicy"]
      requestParameters = {
        policyArn = ["arn:aws:iam::aws:policy/AWSCompromisedKeyQuarantineV2"]
      }
    }
  })
}

# Event target that invokes the Lambda function when the event rule triggers
resource "aws_cloudwatch_event_target" "invoke_lambda" {
  rule      = aws_cloudwatch_event_rule.iam_policy_attachment.name
  target_id = "invokeLambdaFunction"
  arn       = aws_lambda_function.iam_access_key_deactivator.arn
}

# Permission for EventBridge (CloudWatch Events) to invoke the Lambda function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iam_access_key_deactivator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.iam_policy_attachment.arn
}

# CloudWatch Log Group for the Lambda function logs
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.iam_access_key_deactivator.function_name}"

  retention_in_days = 7

  lifecycle {
    prevent_destroy = false
  }
}
