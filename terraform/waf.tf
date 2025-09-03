# ========================================
# WAF Configuration
# ========================================

# Note: WAF for CloudFront must be created in us-east-1 region
# Temporarily disabled until proper provider configuration is added

/*
# WAF Web ACL
resource "aws_wafv2_web_acl" "security_camera_waf" {
  name  = "security-camera-waf"
  description = "WAF for Security Camera System"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 1

    override_action {
      none {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }

    action {
      block {}
    }
  }

  # Geographic restriction rule
  rule {
    name     = "GeoRestrictionRule"
    priority = 2

    override_action {
      none {}
    }

    statement {
      geo_match_statement {
        country_codes = ["JP", "US"]
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "GeoRestrictionRule"
      sampled_requests_enabled   = true
    }

    action {
      allow {}
    }
  }

  # IP blocking rule (if IPs are specified)
  dynamic "rule" {
    for_each = length(var.waf_blocked_ips) > 0 ? [1] : []
    content {
      name     = "IPBlockingRule"
      priority = 3

      override_action {
        none {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.blocked_ips[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "IPBlockingRule"
        sampled_requests_enabled   = true
      }

      action {
        block {}
      }
    }
  }

  # AWS Managed Rules - Core Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 5

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "SecurityCameraWAF"
    sampled_requests_enabled   = true
  }

  tags = merge(var.common_tags, {
    Name = "security-camera-waf"
  })
}

# IP Set for blocked IPs
resource "aws_wafv2_ip_set" "blocked_ips" {
  count = length(var.waf_blocked_ips) > 0 ? 1 : 0
  
  name               = "security-camera-blocked-ips"
  description        = "IP addresses to block"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"

  addresses = var.waf_blocked_ips

  tags = merge(var.common_tags, {
    Name = "security-camera-blocked-ips"
  })
}

# CloudWatch Log Group for WAF
resource "aws_cloudwatch_log_group" "waf_log_group" {
  name              = "/aws/wafv2/security-camera"
  retention_in_days = var.waf_log_retention_days

  tags = merge(var.common_tags, {
    Name = "security-camera-waf-logs"
  })
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "waf_logging" {
  resource_arn            = aws_wafv2_web_acl.security_camera_waf.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_log_group.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}
*/ 