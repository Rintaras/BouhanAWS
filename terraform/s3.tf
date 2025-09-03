# ========================================
# S3 Configuration for Frontend Hosting
# ========================================

# S3 Bucket for Frontend
resource "aws_s3_bucket" "frontend" {
  bucket = var.frontend_bucket_name

  tags = merge(var.common_tags, {
    Name = "security-camera-frontend"
  })
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "frontend_versioning" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend_encryption" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "frontend_pab" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 Bucket Policy for CloudFront
resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend.id
  depends_on = [aws_s3_bucket_public_access_block.frontend_pab]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend_distribution.arn
          }
        }
      }
    ]
  })
}

# S3 Bucket Website Configuration
resource "aws_s3_bucket_website_configuration" "frontend_website" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# S3 Bucket CORS Configuration
resource "aws_s3_bucket_cors_configuration" "frontend_cors" {
  bucket = aws_s3_bucket.frontend.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "frontend_oac" {
  name                              = "security-camera-frontend-oac"
  description                       = "OAC for Security Camera Frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 Objects for default files
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  content_type = "text/html"
  content = templatefile("${path.module}/frontend/index.html", {
    api_gateway_url = aws_api_gateway_deployment.api_deployment.invoke_url
    region         = var.aws_region
  })
  etag = filemd5("${path.module}/frontend/index.html")

  tags = var.common_tags
}

resource "aws_s3_object" "error_html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "error.html"
  content_type = "text/html"
  source       = "${path.module}/frontend/error.html"
  etag         = filemd5("${path.module}/frontend/error.html")

  tags = var.common_tags
}

# Upload CSS files
resource "aws_s3_object" "css_files" {
  for_each = fileset("${path.module}/frontend/css/", "**/*.css")
  
  bucket       = aws_s3_bucket.frontend.id
  key          = "css/${each.value}"
  content_type = "text/css"
  source       = "${path.module}/frontend/css/${each.value}"
  etag         = filemd5("${path.module}/frontend/css/${each.value}")

  tags = var.common_tags
}

# Upload JavaScript files
resource "aws_s3_object" "js_files" {
  for_each = fileset("${path.module}/frontend/js/", "**/*.js")
  
  bucket       = aws_s3_bucket.frontend.id
  key          = "js/${each.value}"
  content_type = "application/javascript"
  source       = "${path.module}/frontend/js/${each.value}"
  etag         = filemd5("${path.module}/frontend/js/${each.value}")

  tags = var.common_tags
}

# Upload image files
resource "aws_s3_object" "image_files" {
  for_each = fileset("${path.module}/frontend/images/", "**/*.{png,jpg,jpeg,gif,svg,ico}")
  
  bucket       = aws_s3_bucket.frontend.id
  key          = "images/${each.value}"
  content_type = lookup({
    "png"  = "image/png"
    "jpg"  = "image/jpeg"
    "jpeg" = "image/jpeg"
    "gif"  = "image/gif"
    "svg"  = "image/svg+xml"
    "ico"  = "image/x-icon"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "application/octet-stream")
  source = "${path.module}/frontend/images/${each.value}"
  etag   = filemd5("${path.module}/frontend/images/${each.value}")

  tags = var.common_tags
} 