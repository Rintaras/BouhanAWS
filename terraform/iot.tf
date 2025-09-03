# ========================================
# IoT Core Configuration
# ========================================

# IoT Thing for Raspberry Pi
resource "aws_iot_thing" "raspberry_pi" {
  name = var.iot_thing_name

  attributes = {
    device_type = "camera"
    location    = "home"
    version     = "1.0"
  }

  # IoT Things don't support tags in this provider version
}

# IoT Policy for Raspberry Pi
resource "aws_iot_policy" "raspberry_pi_policy" {
  name = var.iot_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Connect",
          "iot:Publish",
          "iot:Subscribe",
          "iot:Receive"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iot:GetThingShadow",
          "iot:UpdateThingShadow",
          "iot:DeleteThingShadow"
        ]
        Resource = [
          "arn:aws:iot:${var.aws_region}:*:thing/${var.iot_thing_name}"
        ]
      }
    ]
  })

  # IoT Policies don't support tags in this provider version
}

# IoT Certificate
resource "aws_iot_certificate" "raspberry_pi_cert" {
  active = true

  # IoT Certificates don't support tags in this provider version
}

# Attach policy to certificate
resource "aws_iot_policy_attachment" "raspberry_pi_policy_attachment" {
  policy = aws_iot_policy.raspberry_pi_policy.name
  target = aws_iot_certificate.raspberry_pi_cert.arn
}

# Attach certificate to thing
resource "aws_iot_thing_principal_attachment" "raspberry_pi_cert_attachment" {
  principal = aws_iot_certificate.raspberry_pi_cert.arn
  thing     = aws_iot_thing.raspberry_pi.name
}

# IoT Rule for processing camera data
resource "aws_iot_topic_rule" "camera_data_rule" {
  name        = "security_camera_data_rule"
  description = "Process camera data from Raspberry Pi"
  enabled     = true
  sql         = "SELECT * FROM 'security-camera/data'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.api_proxy.arn
  }

  # IoT Rules don't support tags in this provider version
}

# IoT Rule for motion detection alerts
resource "aws_iot_topic_rule" "motion_alert_rule" {
  name        = "security_camera_motion_alert_rule"
  description = "Process motion detection alerts"
  enabled     = true
  sql         = "SELECT * FROM 'security-camera/motion-alert'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.line_notification.arn
  }

  # IoT Rules don't support tags in this provider version
}

# Lambda permission for IoT Rule
resource "aws_lambda_permission" "iot_invoke_lambda" {
  statement_id  = "AllowExecutionFromIoT"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_proxy.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.camera_data_rule.arn
}

# Lambda permission for motion alert IoT Rule
resource "aws_lambda_permission" "iot_invoke_line_lambda" {
  statement_id  = "AllowExecutionFromIoTMotionAlert"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.line_notification.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.motion_alert_rule.arn
}

# IoT Endpoint data source
data "aws_iot_endpoint" "iot_endpoint" {
  endpoint_type = "iot:Data-ATS"
} 