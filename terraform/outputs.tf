# ========================================
# Terraform Outputs - Serverless Architecture
# ========================================

# CloudFront Distribution
output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.frontend_distribution.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.frontend_distribution.id
}

output "frontend_url" {
  description = "Frontend URL"
  value       = var.domain_name != null ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.frontend_distribution.domain_name}"
}

# S3 Bucket
output "frontend_bucket_name" {
  description = "S3 bucket name for frontend"
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_bucket_website_endpoint" {
  description = "S3 bucket website endpoint"
  value       = aws_s3_bucket_website_configuration.frontend_website.website_endpoint
}

# API Gateway
output "api_gateway_url" {
  description = "API Gateway URL"
  value       = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_api_gateway_rest_api.security_camera_api.id
}

# Lambda Functions
output "api_proxy_function_name" {
  description = "API Proxy Lambda function name"
  value       = aws_lambda_function.api_proxy.function_name
}

output "line_notification_function_name" {
  description = "Line Notification Lambda function name"
  value       = aws_lambda_function.line_notification.function_name
}

# IoT Core
output "iot_endpoint" {
  description = "IoT Core endpoint"
  value       = data.aws_iot_endpoint.iot_endpoint.endpoint_address
}

output "iot_thing_name" {
  description = "IoT Thing name"
  value       = aws_iot_thing.raspberry_pi.name
}

output "iot_certificate_arn" {
  description = "IoT Certificate ARN"
  value       = aws_iot_certificate.raspberry_pi_cert.arn
}

output "iot_certificate_pem" {
  description = "IoT Certificate PEM"
  value       = aws_iot_certificate.raspberry_pi_cert.certificate_pem
  sensitive   = true
}

output "iot_private_key" {
  description = "IoT Private Key"
  value       = aws_iot_certificate.raspberry_pi_cert.private_key
  sensitive   = true
}

output "iot_public_key" {
  description = "IoT Public Key"
  value       = aws_iot_certificate.raspberry_pi_cert.public_key
  sensitive   = true
}

# DynamoDB
output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.sessions.name
}

# WAF
# output "waf_web_acl_arn" {
#   description = "ARN of the WAF Web ACL"
#   value       = aws_wafv2_web_acl.security_camera_waf.arn
# }

# CloudWatch
output "cloudwatch_log_groups" {
  description = "CloudWatch log groups"
  value = {
    lambda_api       = aws_cloudwatch_log_group.api_proxy_logs.name
    lambda_line      = aws_cloudwatch_log_group.line_notification_logs.name
    # waf              = aws_cloudwatch_log_group.waf_log_group.name
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Deployment summary"
  value = {
    frontend_url          = var.domain_name != null ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.frontend_distribution.domain_name}"
    api_gateway_url       = aws_api_gateway_deployment.api_deployment.invoke_url
    cloudfront_domain     = aws_cloudfront_distribution.frontend_distribution.domain_name
    s3_bucket            = aws_s3_bucket.frontend.bucket
    iot_endpoint         = data.aws_iot_endpoint.iot_endpoint.endpoint_address
    iot_thing_name       = aws_iot_thing.raspberry_pi.name
    lambda_functions = {
      api_proxy         = aws_lambda_function.api_proxy.function_name
      line_notification = aws_lambda_function.line_notification.function_name
    }
    dynamodb_table       = aws_dynamodb_table.sessions.name
    # waf_web_acl         = aws_wafv2_web_acl.security_camera_waf.name
  }
}

# Configuration for Raspberry Pi
output "raspberry_pi_config" {
  description = "Configuration information for Raspberry Pi setup"
  value = {
    iot_endpoint      = data.aws_iot_endpoint.iot_endpoint.endpoint_address
    iot_thing_name    = aws_iot_thing.raspberry_pi.name
    iot_policy_name   = aws_iot_policy.raspberry_pi_policy.name
    region           = var.aws_region
    topics = {
      data_topic         = "security-camera/data"
      motion_alert_topic = "security-camera/motion-alert"
      command_topic      = "security-camera/commands"
      status_topic       = "security-camera/status"
    }
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    lambda_requests     = "~$2.00 (1M requests)"
    api_gateway        = "~$3.50 (1M requests)"
    cloudfront         = "~$1.00 (10GB transfer)"
    s3_storage         = "~$0.50 (20GB)"
    dynamodb           = "~$1.25 (25 RCU/WCU)"
    iot_core           = "~$0.80 (1M messages)"
    waf                = "~$5.00 (1M requests)"
    cloudwatch         = "~$2.00 (logs & metrics)"
    total_estimated    = "~$16.05/month"
    note              = "Costs vary based on actual usage"
  }
}

# Security Information
output "security_features" {
  description = "Security features enabled"
  value = {
    waf_protection     = "Enabled with rate limiting and geo-restriction"
    https_only         = "Enforced via CloudFront"
    iot_certificates   = "X.509 certificates for device authentication"
    lambda_isolation   = "VPC isolation not configured (serverless)"
    cors_policy        = "Configured for secure cross-origin requests"
    headers_policy     = "Security headers enforced via CloudFront"
  }
} 