# ========================================
# Lambda Functions Configuration
# ========================================

# Lambda Execution Role
resource "aws_iam_role" "lambda_execution_role" {
  name = "security-camera-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# Lambda Execution Policy
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "security-camera-lambda-execution-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.sessions.arn,
          "${aws_dynamodb_table.sessions.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iot:Publish",
          "iot:Subscribe",
          "iot:Connect",
          "iot:Receive"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS Lambda Basic Execution Role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Lambda Layer for Node.js dependencies
resource "aws_lambda_layer_version" "nodejs_dependencies" {
  filename         = "${path.module}/lambda/layers/nodejs-dependencies.zip"
  layer_name       = "security-camera-nodejs-dependencies"
  compatible_runtimes = ["nodejs18.x"]
  description      = "Node.js dependencies for Security Camera Lambda functions"

  depends_on = [null_resource.build_lambda_layer]
}

# Build Lambda Layer
resource "null_resource" "build_lambda_layer" {
  triggers = {
    package_json_hash = filemd5("${path.module}/lambda/layers/package.json")
  }

  provisioner "local-exec" {
    command = <<EOF
      cd ${path.module}/lambda/layers
      npm install --production
      mkdir -p nodejs
      cp -r node_modules nodejs/
      zip -r nodejs-dependencies.zip nodejs/
    EOF
  }
}

# API Proxy Lambda Function
resource "aws_lambda_function" "api_proxy" {
  filename         = "${path.module}/lambda/api-proxy.zip"
  function_name    = var.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = var.lambda_handler
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  layers = [aws_lambda_layer_version.nodejs_dependencies.arn]

  environment {
    variables = {
      RASPBERRY_PI_IP   = var.raspberry_pi_ip
      RASPBERRY_PI_PORT = var.raspberry_pi_port
      DYNAMODB_TABLE    = aws_dynamodb_table.sessions.name
      IOT_ENDPOINT      = data.aws_iot_endpoint.iot_endpoint.endpoint_address
      IOT_THING_NAME    = var.iot_thing_name
    }
  }

  depends_on = [null_resource.build_api_proxy_lambda]

  tags = merge(var.common_tags, {
    Name = var.lambda_function_name
  })
}

# Build API Proxy Lambda
resource "null_resource" "build_api_proxy_lambda" {
  triggers = {
    source_hash = filemd5("${path.module}/lambda/api-proxy/index.js")
  }

  provisioner "local-exec" {
    command = <<EOF
      cd ${path.module}/lambda/api-proxy
      zip -r ../api-proxy.zip .
    EOF
  }
}

# Line Notification Lambda Function
resource "aws_lambda_function" "line_notification" {
  filename         = "${path.module}/lambda/line-notification.zip"
  function_name    = "security-camera-line-notification"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.handler"
  runtime         = var.lambda_runtime
  timeout         = 30
  memory_size     = 128

  layers = [aws_lambda_layer_version.nodejs_dependencies.arn]

  environment {
    variables = {
      LINE_CHANNEL_ACCESS_TOKEN = var.line_channel_access_token
      LINE_CHANNEL_SECRET       = var.line_channel_secret
      LINE_USER_ID             = var.line_user_id
    }
  }

  depends_on = [null_resource.build_line_notification_lambda]

  tags = merge(var.common_tags, {
    Name = "security-camera-line-notification"
  })
}

# Build Line Notification Lambda
resource "null_resource" "build_line_notification_lambda" {
  triggers = {
    source_hash = filemd5("${path.module}/lambda/line-notification/index.js")
  }

  provisioner "local-exec" {
    command = <<EOF
      cd ${path.module}/lambda/line-notification
      zip -r ../line-notification.zip .
    EOF
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "api_proxy_logs" {
  name              = "/aws/lambda/${aws_lambda_function.api_proxy.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "line_notification_logs" {
  name              = "/aws/lambda/${aws_lambda_function.line_notification.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.common_tags
}

# DynamoDB Table for Session Management
resource "aws_dynamodb_table" "sessions" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "session_id"

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  global_secondary_index {
    name            = "user-index"
    hash_key        = "user_id"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = merge(var.common_tags, {
    Name = var.dynamodb_table_name
  })
}

# API Gateway
resource "aws_api_gateway_rest_api" "security_camera_api" {
  name        = var.api_gateway_name
  description = "Security Camera API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.common_tags
}

# API Gateway Resource - API
resource "aws_api_gateway_resource" "api_resource" {
  rest_api_id = aws_api_gateway_rest_api.security_camera_api.id
  parent_id   = aws_api_gateway_rest_api.security_camera_api.root_resource_id
  path_part   = "api"
}

# API Gateway Resource - Proxy
resource "aws_api_gateway_resource" "proxy_resource" {
  rest_api_id = aws_api_gateway_rest_api.security_camera_api.id
  parent_id   = aws_api_gateway_resource.api_resource.id
  path_part   = "{proxy+}"
}

# API Gateway Method
resource "aws_api_gateway_method" "proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.security_camera_api.id
  resource_id   = aws_api_gateway_resource.proxy_resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

# API Gateway Integration
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.security_camera_api.id
  resource_id = aws_api_gateway_resource.proxy_resource.id
  http_method = aws_api_gateway_method.proxy_method.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.api_proxy.invoke_arn
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [aws_api_gateway_integration.lambda_integration]

  rest_api_id = aws_api_gateway_rest_api.security_camera_api.id
  stage_name  = var.api_gateway_stage_name

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_proxy.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.security_camera_api.execution_arn}/*/*"
}

# API Gateway CORS
resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.security_camera_api.id
  resource_id   = aws_api_gateway_resource.proxy_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.security_camera_api.id
  resource_id = aws_api_gateway_resource.proxy_resource.id
  http_method = aws_api_gateway_method.options_method.http_method

  type = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_response" {
  rest_api_id = aws_api_gateway_rest_api.security_camera_api.id
  resource_id = aws_api_gateway_resource.proxy_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.security_camera_api.id
  resource_id = aws_api_gateway_resource.proxy_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT,DELETE'"
    "method.response.header.Access-Control-Allow-Origin"  = "'https://d3n8o5om0tprho.cloudfront.net'"
  }
} 