#!/bin/bash

# ========================================
# AWS 設定自動化スクリプト
# ========================================

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 環境変数ファイルの存在チェック
check_env_file() {
    if [ ! -f ".env" ]; then
        log_error ".envファイルが見つかりません"
        log_info "env.exampleをコピーして.envファイルを作成してください"
        exit 1
    fi
}

# AWS CLIのインストールチェック
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLIがインストールされていません"
        log_info "以下のコマンドでインストールしてください:"
        echo "curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
        echo "unzip awscliv2.zip"
        echo "sudo ./aws/install"
        exit 1
    fi
}

# AWS認証情報の設定
setup_aws_credentials() {
    log_info "AWS認証情報を設定します..."
    
    # .envファイルから認証情報を読み込み
    source .env
    
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        log_error "AWS_ACCESS_KEY_IDまたはAWS_SECRET_ACCESS_KEYが設定されていません"
        exit 1
    fi
    
    # AWS CLI設定
    aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
    aws configure set region "$AWS_REGION"
    aws configure set output json
    
    log_success "AWS認証情報を設定しました"
}

# S3バケットの作成
create_s3_bucket() {
    log_info "S3バケットを作成します..."
    
    source .env
    
    if [ -z "$S3_BUCKET_NAME" ]; then
        log_error "S3_BUCKET_NAMEが設定されていません"
        exit 1
    fi
    
    # バケットが存在するかチェック
    if aws s3 ls "s3://$S3_BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
        # バケットを作成
        aws s3 mb "s3://$S3_BUCKET_NAME" --region "$S3_BUCKET_REGION"
        
        # 静的ウェブサイトホスティング設定
        aws s3 website "s3://$S3_BUCKET_NAME" --index-document index.html --error-document error.html
        
        # バケットポリシー設定
        cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$S3_BUCKET_NAME/*"
        }
    ]
}
EOF
        
        aws s3api put-bucket-policy --bucket "$S3_BUCKET_NAME" --policy file://bucket-policy.json
        
        log_success "S3バケットを作成しました: $S3_BUCKET_NAME"
    else
        log_warning "S3バケットは既に存在します: $S3_BUCKET_NAME"
    fi
}

# CloudFrontディストリビューションの作成
create_cloudfront_distribution() {
    log_info "CloudFrontディストリビューションを作成します..."
    
    source .env
    
    if [ -z "$S3_BUCKET_NAME" ]; then
        log_error "S3_BUCKET_NAMEが設定されていません"
        exit 1
    fi
    
    # ディストリビューション設定ファイル作成
    cat > cloudfront-config.json << EOF
{
    "CallerReference": "security-camera-$(date +%s)",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3-Origin",
                "DomainName": "$S3_BUCKET_NAME.s3.amazonaws.com",
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000
    },
    "Enabled": true,
    "Comment": "Security Camera Frontend"
}
EOF
    
    # CloudFrontディストリビューション作成
    DISTRIBUTION_ID=$(aws cloudfront create-distribution --distribution-config file://cloudfront-config.json --query 'Distribution.Id' --output text)
    
    # .envファイルにディストリビューションIDを追加
    if ! grep -q "CLOUDFRONT_DISTRIBUTION_ID" .env; then
        echo "CLOUDFRONT_DISTRIBUTION_ID=$DISTRIBUTION_ID" >> .env
    else
        # 既存の値を更新
        sed -i "s/CLOUDFRONT_DISTRIBUTION_ID=.*/CLOUDFRONT_DISTRIBUTION_ID=$DISTRIBUTION_ID/" .env
    fi
    
    log_success "CloudFrontディストリビューションを作成しました: $DISTRIBUTION_ID"
}

# Lambda関数の作成
create_lambda_function() {
    log_info "Lambda関数を作成します..."
    
    source .env
    
    if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
        log_error "LAMBDA_FUNCTION_NAMEが設定されていません"
        exit 1
    fi
    
    # Lambda関数のコード作成
    cat > lambda-function.js << 'EOF'
exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const uri = request.uri;
    
    // APIリクエストの場合（/api/で始まる）
    if (uri.startsWith('/api/')) {
        const raspberryPiIP = process.env.RASPBERRY_PI_IP || '192.168.1.100';
        const apiPath = uri.replace('/api', '');
        
        try {
            // ラズパイのカメラサーバーにプロキシ
            const response = await fetch(`http://${raspberryPiIP}:3000${apiPath}`, {
                method: request.method,
                headers: request.headers,
                body: request.body
            });
            
            return {
                status: response.status.toString(),
                statusDescription: response.statusText,
                headers: {
                    'content-type': [{
                        key: 'Content-Type',
                        value: 'application/json'
                    }],
                    'access-control-allow-origin': [{
                        key: 'Access-Control-Allow-Origin',
                        value: '*'
                    }]
                },
                body: await response.text()
            };
        } catch (error) {
            return {
                status: '502',
                statusDescription: 'Bad Gateway',
                body: JSON.stringify({ error: 'Camera server unavailable' })
            };
        }
    }
    
    // 静的ファイルの場合は通常通りS3から配信
    return request;
};
EOF
    
    # Lambda関数をZIP化
    zip -r lambda-function.zip lambda-function.js
    
    # Lambda関数作成
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime nodejs18.x \
        --role "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/lambda-execution-role" \
        --handler lambda-function.handler \
        --zip-file fileb://lambda-function.zip \
        --environment Variables="{RASPBERRY_PI_IP=$RASPBERRY_PI_IP}" \
        --timeout 30 \
        --memory-size 128
    
    log_success "Lambda関数を作成しました: $LAMBDA_FUNCTION_NAME"
}

# WAF Web ACLの作成
create_waf_web_acl() {
    log_info "WAF Web ACLを作成します..."
    
    source .env
    
    # WAF Web ACL設定ファイル作成
    cat > waf-web-acl.json << EOF
{
    "Name": "SecurityCameraWebACL",
    "Description": "Security Camera WAF Web ACL",
    "Scope": "REGIONAL",
    "DefaultAction": {
        "Allow": {}
    },
    "Rules": [
        {
            "Name": "RateLimit",
            "Priority": 1,
            "Statement": {
                "RateBasedStatement": {
                    "Limit": 2000,
                    "AggregateKeyType": "IP"
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "RateLimitRule"
            }
        }
    ],
    "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "SecurityCameraWebACL"
    }
}
EOF
    
    # WAF Web ACL作成
    WEB_ACL_ID=$(aws wafv2 create-web-acl --cli-input-json file://waf-web-acl.json --query 'Summary.Id' --output text)
    
    # .envファイルにWeb ACL IDを追加
    if ! grep -q "WAF_WEB_ACL_ID" .env; then
        echo "WAF_WEB_ACL_ID=$WEB_ACL_ID" >> .env
    else
        # 既存の値を更新
        sed -i "s/WAF_WEB_ACL_ID=.*/WAF_WEB_ACL_ID=$WEB_ACL_ID/" .env
    fi
    
    log_success "WAF Web ACLを作成しました: $WEB_ACL_ID"
}

# フロントエンドのデプロイ
deploy_frontend() {
    log_info "フロントエンドをデプロイします..."
    
    source .env
    
    if [ -z "$S3_BUCKET_NAME" ]; then
        log_error "S3_BUCKET_NAMEが設定されていません"
        exit 1
    fi
    
    # フロントエンドをビルド
    cd monitor-client
    npm install
    npm run build
    
    # S3にアップロード
    aws s3 sync dist/ "s3://$S3_BUCKET_NAME" --delete
    
    # CloudFrontキャッシュ無効化
    if [ ! -z "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
        aws cloudfront create-invalidation \
            --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
            --paths "/*"
    fi
    
    cd ..
    
    log_success "フロントエンドをデプロイしました"
}

# メイン処理
main() {
    log_info "AWS設定を開始します..."
    
    # 環境チェック
    check_env_file
    check_aws_cli
    
    # AWS認証情報設定
    setup_aws_credentials
    
    # リソース作成
    create_s3_bucket
    create_cloudfront_distribution
    create_lambda_function
    create_waf_web_acl
    
    # フロントエンドデプロイ
    deploy_frontend
    
    log_success "AWS設定が完了しました！"
    
    # 設定情報の表示
    source .env
    echo ""
    echo "=== 設定情報 ==="
    echo "S3バケット: $S3_BUCKET_NAME"
    echo "CloudFrontディストリビューション: $CLOUDFRONT_DISTRIBUTION_ID"
    echo "Lambda関数: $LAMBDA_FUNCTION_NAME"
    echo "WAF Web ACL: $WAF_WEB_ACL_ID"
    echo ""
    echo "アクセスURL: https://$CLOUDFRONT_DISTRIBUTION_ID.cloudfront.net"
}

# スクリプト実行
main "$@" 

# ========================================
# AWS 設定自動化スクリプト
# ========================================

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 環境変数ファイルの存在チェック
check_env_file() {
    if [ ! -f ".env" ]; then
        log_error ".envファイルが見つかりません"
        log_info "env.exampleをコピーして.envファイルを作成してください"
        exit 1
    fi
}

# AWS CLIのインストールチェック
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLIがインストールされていません"
        log_info "以下のコマンドでインストールしてください:"
        echo "curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
        echo "unzip awscliv2.zip"
        echo "sudo ./aws/install"
        exit 1
    fi
}

# AWS認証情報の設定
setup_aws_credentials() {
    log_info "AWS認証情報を設定します..."
    
    # .envファイルから認証情報を読み込み
    source .env
    
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        log_error "AWS_ACCESS_KEY_IDまたはAWS_SECRET_ACCESS_KEYが設定されていません"
        exit 1
    fi
    
    # AWS CLI設定
    aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
    aws configure set region "$AWS_REGION"
    aws configure set output json
    
    log_success "AWS認証情報を設定しました"
}

# S3バケットの作成
create_s3_bucket() {
    log_info "S3バケットを作成します..."
    
    source .env
    
    if [ -z "$S3_BUCKET_NAME" ]; then
        log_error "S3_BUCKET_NAMEが設定されていません"
        exit 1
    fi
    
    # バケットが存在するかチェック
    if aws s3 ls "s3://$S3_BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
        # バケットを作成
        aws s3 mb "s3://$S3_BUCKET_NAME" --region "$S3_BUCKET_REGION"
        
        # 静的ウェブサイトホスティング設定
        aws s3 website "s3://$S3_BUCKET_NAME" --index-document index.html --error-document error.html
        
        # バケットポリシー設定
        cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$S3_BUCKET_NAME/*"
        }
    ]
}
EOF
        
        aws s3api put-bucket-policy --bucket "$S3_BUCKET_NAME" --policy file://bucket-policy.json
        
        log_success "S3バケットを作成しました: $S3_BUCKET_NAME"
    else
        log_warning "S3バケットは既に存在します: $S3_BUCKET_NAME"
    fi
}

# CloudFrontディストリビューションの作成
create_cloudfront_distribution() {
    log_info "CloudFrontディストリビューションを作成します..."
    
    source .env
    
    if [ -z "$S3_BUCKET_NAME" ]; then
        log_error "S3_BUCKET_NAMEが設定されていません"
        exit 1
    fi
    
    # ディストリビューション設定ファイル作成
    cat > cloudfront-config.json << EOF
{
    "CallerReference": "security-camera-$(date +%s)",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3-Origin",
                "DomainName": "$S3_BUCKET_NAME.s3.amazonaws.com",
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000
    },
    "Enabled": true,
    "Comment": "Security Camera Frontend"
}
EOF
    
    # CloudFrontディストリビューション作成
    DISTRIBUTION_ID=$(aws cloudfront create-distribution --distribution-config file://cloudfront-config.json --query 'Distribution.Id' --output text)
    
    # .envファイルにディストリビューションIDを追加
    if ! grep -q "CLOUDFRONT_DISTRIBUTION_ID" .env; then
        echo "CLOUDFRONT_DISTRIBUTION_ID=$DISTRIBUTION_ID" >> .env
    else
        # 既存の値を更新
        sed -i "s/CLOUDFRONT_DISTRIBUTION_ID=.*/CLOUDFRONT_DISTRIBUTION_ID=$DISTRIBUTION_ID/" .env
    fi
    
    log_success "CloudFrontディストリビューションを作成しました: $DISTRIBUTION_ID"
}

# Lambda関数の作成
create_lambda_function() {
    log_info "Lambda関数を作成します..."
    
    source .env
    
    if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
        log_error "LAMBDA_FUNCTION_NAMEが設定されていません"
        exit 1
    fi
    
    # Lambda関数のコード作成
    cat > lambda-function.js << 'EOF'
exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const uri = request.uri;
    
    // APIリクエストの場合（/api/で始まる）
    if (uri.startsWith('/api/')) {
        const raspberryPiIP = process.env.RASPBERRY_PI_IP || '192.168.1.100';
        const apiPath = uri.replace('/api', '');
        
        try {
            // ラズパイのカメラサーバーにプロキシ
            const response = await fetch(`http://${raspberryPiIP}:3000${apiPath}`, {
                method: request.method,
                headers: request.headers,
                body: request.body
            });
            
            return {
                status: response.status.toString(),
                statusDescription: response.statusText,
                headers: {
                    'content-type': [{
                        key: 'Content-Type',
                        value: 'application/json'
                    }],
                    'access-control-allow-origin': [{
                        key: 'Access-Control-Allow-Origin',
                        value: '*'
                    }]
                },
                body: await response.text()
            };
        } catch (error) {
            return {
                status: '502',
                statusDescription: 'Bad Gateway',
                body: JSON.stringify({ error: 'Camera server unavailable' })
            };
        }
    }
    
    // 静的ファイルの場合は通常通りS3から配信
    return request;
};
EOF
    
    # Lambda関数をZIP化
    zip -r lambda-function.zip lambda-function.js
    
    # Lambda関数作成
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime nodejs18.x \
        --role "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/lambda-execution-role" \
        --handler lambda-function.handler \
        --zip-file fileb://lambda-function.zip \
        --environment Variables="{RASPBERRY_PI_IP=$RASPBERRY_PI_IP}" \
        --timeout 30 \
        --memory-size 128
    
    log_success "Lambda関数を作成しました: $LAMBDA_FUNCTION_NAME"
}

# WAF Web ACLの作成
create_waf_web_acl() {
    log_info "WAF Web ACLを作成します..."
    
    source .env
    
    # WAF Web ACL設定ファイル作成
    cat > waf-web-acl.json << EOF
{
    "Name": "SecurityCameraWebACL",
    "Description": "Security Camera WAF Web ACL",
    "Scope": "REGIONAL",
    "DefaultAction": {
        "Allow": {}
    },
    "Rules": [
        {
            "Name": "RateLimit",
            "Priority": 1,
            "Statement": {
                "RateBasedStatement": {
                    "Limit": 2000,
                    "AggregateKeyType": "IP"
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "RateLimitRule"
            }
        }
    ],
    "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "SecurityCameraWebACL"
    }
}
EOF
    
    # WAF Web ACL作成
    WEB_ACL_ID=$(aws wafv2 create-web-acl --cli-input-json file://waf-web-acl.json --query 'Summary.Id' --output text)
    
    # .envファイルにWeb ACL IDを追加
    if ! grep -q "WAF_WEB_ACL_ID" .env; then
        echo "WAF_WEB_ACL_ID=$WEB_ACL_ID" >> .env
    else
        # 既存の値を更新
        sed -i "s/WAF_WEB_ACL_ID=.*/WAF_WEB_ACL_ID=$WEB_ACL_ID/" .env
    fi
    
    log_success "WAF Web ACLを作成しました: $WEB_ACL_ID"
}

# フロントエンドのデプロイ
deploy_frontend() {
    log_info "フロントエンドをデプロイします..."
    
    source .env
    
    if [ -z "$S3_BUCKET_NAME" ]; then
        log_error "S3_BUCKET_NAMEが設定されていません"
        exit 1
    fi
    
    # フロントエンドをビルド
    cd monitor-client
    npm install
    npm run build
    
    # S3にアップロード
    aws s3 sync dist/ "s3://$S3_BUCKET_NAME" --delete
    
    # CloudFrontキャッシュ無効化
    if [ ! -z "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
        aws cloudfront create-invalidation \
            --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
            --paths "/*"
    fi
    
    cd ..
    
    log_success "フロントエンドをデプロイしました"
}

# メイン処理
main() {
    log_info "AWS設定を開始します..."
    
    # 環境チェック
    check_env_file
    check_aws_cli
    
    # AWS認証情報設定
    setup_aws_credentials
    
    # リソース作成
    create_s3_bucket
    create_cloudfront_distribution
    create_lambda_function
    create_waf_web_acl
    
    # フロントエンドデプロイ
    deploy_frontend
    
    log_success "AWS設定が完了しました！"
    
    # 設定情報の表示
    source .env
    echo ""
    echo "=== 設定情報 ==="
    echo "S3バケット: $S3_BUCKET_NAME"
    echo "CloudFrontディストリビューション: $CLOUDFRONT_DISTRIBUTION_ID"
    echo "Lambda関数: $LAMBDA_FUNCTION_NAME"
    echo "WAF Web ACL: $WAF_WEB_ACL_ID"
    echo ""
    echo "アクセスURL: https://$CLOUDFRONT_DISTRIBUTION_ID.cloudfront.net"
}

# スクリプト実行
main "$@" 
 