# ========================================
# Security Camera System - Serverless Architecture
# Terraform Variables
# ========================================

# AWS基本設定
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "security-camera"
}

# Raspberry Pi設定
variable "raspberry_pi_ip" {
  description = "Raspberry Pi IP address"
  type        = string
}

variable "raspberry_pi_port" {
  description = "Raspberry Pi port number"
  type        = string
  default     = "3000"
}

# S3設定
variable "frontend_bucket_name" {
  description = "S3 bucket name for frontend hosting"
  type        = string
}

# CloudFront設定
variable "cloudfront_comment" {
  description = "CloudFront distribution comment"
  type        = string
  default     = "Security Camera Frontend Distribution"
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

# Lambda設定
variable "lambda_function_name" {
  description = "Lambda function name for API proxy"
  type        = string
  default     = "security-camera-api-proxy"
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs18.x"
}

variable "lambda_handler" {
  description = "Lambda handler"
  type        = string
  default     = "index.handler"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 256
}

# IoT Core設定
variable "iot_thing_name" {
  description = "IoT Thing name for Raspberry Pi"
  type        = string
  default     = "security-camera-raspberry-pi"
}

variable "iot_policy_name" {
  description = "IoT policy name"
  type        = string
  default     = "security-camera-raspberry-pi-policy"
}

# Line Messaging API設定
variable "line_channel_access_token" {
  description = "Line Channel Access Token"
  type        = string
  sensitive   = true
}

variable "line_channel_secret" {
  description = "Line Channel Secret"
  type        = string
  sensitive   = true
}

variable "line_user_id" {
  description = "Line User ID for notifications"
  type        = string
  sensitive   = true
}

# API Gateway設定
variable "api_gateway_name" {
  description = "API Gateway name"
  type        = string
  default     = "security-camera-api"
}

variable "api_gateway_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
}

# CloudWatch設定
variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 14
}

# DynamoDB設定（セッション管理用）
variable "dynamodb_table_name" {
  description = "DynamoDB table name for session management"
  type        = string
  default     = "security-camera-sessions"
}

# WAF設定
variable "waf_rate_limit" {
  description = "WAF rate limit per 5 minutes"
  type        = number
  default     = 2000
}

variable "waf_blocked_ips" {
  description = "List of IP addresses to block"
  type        = list(string)
  default     = []
}

# SSL証明書設定
variable "domain_name" {
  description = "Custom domain name (optional)"
  type        = string
  default     = null
}

variable "ssl_certificate_arn" {
  description = "SSL certificate ARN (required if domain_name is set)"
  type        = string
  default     = null
}

# 通知設定
variable "notification_enabled" {
  description = "Enable notifications"
  type        = bool
  default     = true
}

# セキュリティ設定
variable "basic_auth_enabled" {
  description = "Enable basic authentication"
  type        = bool
  default     = true
}

variable "basic_auth_username" {
  description = "Basic auth username"
  type        = string
  default     = "admin"
}

variable "basic_auth_password" {
  description = "Basic auth password"
  type        = string
  sensitive   = true
  default     = null
}

# タグ設定
variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "security-camera"
    Environment = "production"
    ManagedBy   = "terraform"
  }
} 