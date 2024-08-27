provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      env   = var.env
      owner = var.owner
    }
  }
}

resource "aws_s3_bucket" "objectlambda-dataset" {
  bucket = var.bucket_name
  force_destroy = true
}

data "aws_iam_policy_document" "assume_lambda_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "ObjectLambda" {
  name               = "ObjectLambda"
  description        = "Role for ObjectLambda"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda_policy.json
}

data "aws_iam_policy" "AmazonS3ObjectLambdaExecutionRolePolicy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonS3ObjectLambdaExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ObjectLambda" {
  policy_arn = data.aws_iam_policy.AmazonS3ObjectLambdaExecutionRolePolicy.arn
  role       = aws_iam_role.ObjectLambda.id
}

locals {
  lambda_dir =  "../lambda"
  binary_dir = "../lambda/bin/"
  binary_path  = "bin/bootstrap"
  src          = "../lambda/main.go"
  archive_path = "../lambda/objectlambda.zip"
}

resource "null_resource" "objectlambda_bin" {
  triggers = {
    src = md5(file(local.src))
  }
  provisioner "local-exec" {
#     command = "GOOS=linux GOARCH=arm64 CGO_ENABLED=1 go build -C ${local.lambda_dir} -o ${local.binary_path} main.go"
    command = "CGO_ENABLED=1 go build -C ${local.lambda_dir} -o ${local.binary_path} main.go"
  }
}

data "archive_file" "objectlambda_zip" {
  depends_on  = [null_resource.objectlambda_bin]
  type        = "zip"
  source_dir = local.binary_dir
  output_path = local.archive_path
}

resource "aws_lambda_function" "ObjectLambda" {
  function_name    = "ObjectLambda"
  description      = "Object Lambda to transform s3 object"
  role             = aws_iam_role.ObjectLambda.arn
  handler          = "main"
  filename         = data.archive_file.objectlambda_zip.output_path
  runtime          = "provided.al2023"
  memory_size      = var.lambda_ram
  ephemeral_storage {
    size = var.lambda_storage
  }
  architectures    = ["arm64"]
  # looks like pre-signed URL will expire in 60 secs, therefore no sense to set up the timeout to more than 60 secs.
  timeout          = 60
  source_code_hash = data.archive_file.objectlambda_zip.output_base64sha256
  environment {
    variables = {
      HOME = "/tmp"
    }
  }
}

resource "aws_cloudwatch_log_group" "ObjectLambda" {
  name              = "/aws/lambda/${aws_lambda_function.ObjectLambda.function_name}"
  retention_in_days = var.logs_retention_in_days
}

resource "aws_s3_access_point" "LambdaObjectAccessPoint" {
  bucket = aws_s3_bucket.objectlambda-dataset.id
  name   = "objectlambda"
}

resource "aws_s3control_object_lambda_access_point" "ObjectLambda" {
  name = "objectlambda"

  configuration {
    supporting_access_point = aws_s3_access_point.LambdaObjectAccessPoint.arn

    transformation_configuration {
      actions = ["GetObject"]

      content_transformation {
        aws_lambda {
          function_arn = aws_lambda_function.ObjectLambda.arn
        }
      }
    }
  }

}
