#!/bin/bash

# S3 Setup Script for RAG PDF Chatbot
# This script creates and configures an S3 bucket for PDF storage

set -euo pipefail

# Configuration
PROJECT_NAME="${PROJECT_NAME:-ragbot}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"
BUCKET_NAME="${BUCKET_NAME:-}"
ENABLE_VERSIONING="${ENABLE_VERSIONING:-true}"
ENABLE_ENCRYPTION="${ENABLE_ENCRYPTION:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Generate bucket name if not provided
generate_bucket_name() {
    if [[ -z "$BUCKET_NAME" ]]; then
        # Generate unique bucket name
        local timestamp=$(date +%s)
        local random=$(openssl rand -hex 4 2>/dev/null || echo "abcd1234")
        BUCKET_NAME="${PROJECT_NAME}-pdfs-${timestamp}-${random}"
        log_info "Generated bucket name: $BUCKET_NAME"
    fi
}

# Check if bucket exists
check_bucket_exists() {
    if aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Create S3 bucket
create_bucket() {
    log_info "Creating S3 bucket: $BUCKET_NAME"
    
    # Check if bucket already exists
    if check_bucket_exists; then
        log_warning "Bucket $BUCKET_NAME already exists"
        return 0
    fi
    
    # Create bucket (different commands for us-east-1 vs other regions)
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE"
    else
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION" \
            --profile "$AWS_PROFILE"
    fi
    
    # Wait for bucket to be created
    log_info "Waiting for bucket to be created..."
    aws s3api wait bucket-exists \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "Bucket created successfully"
}

# Enable versioning
enable_versioning() {
    if [[ "$ENABLE_VERSIONING" != "true" ]]; then
        log_info "Skipping versioning setup"
        return 0
    fi
    
    log_info "Enabling versioning..."
    
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "Versioning enabled"
}

# Enable encryption
enable_encryption() {
    if [[ "$ENABLE_ENCRYPTION" != "true" ]]; then
        log_info "Skipping encryption setup"
        return 0
    fi
    
    log_info "Enabling server-side encryption..."
    
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "Server-side encryption enabled"
}

# Block public access
block_public_access() {
    log_info "Blocking public access..."
    
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration '{
            "BlockPublicAcls": true,
            "IgnorePublicAcls": true,
            "BlockPublicPolicy": true,
            "RestrictPublicBuckets": true
        }' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "Public access blocked"
}

# Enable logging
enable_logging() {
    log_info "Enabling access logging..."
    
    # Create logging bucket
    local LOG_BUCKET="${BUCKET_NAME}-logs"
    
    if ! check_bucket_exists "$LOG_BUCKET"; then
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3api create-bucket \
                --bucket "$LOG_BUCKET" \
                --region "$AWS_REGION" \
                --profile "$AWS_PROFILE"
        else
            aws s3api create-bucket \
                --bucket "$LOG_BUCKET" \
                --region "$AWS_REGION" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION" \
                --profile "$AWS_PROFILE"
        fi
    fi
    
    # Enable logging
    aws s3api put-bucket-logging \
        --bucket "$BUCKET_NAME" \
        --bucket-logging-status '{
            "LoggingEnabled": {
                "TargetBucket": "'"$LOG_BUCKET"'",
                "TargetPrefix": "s3-access-logs/"
            }
        }' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "Access logging enabled to $LOG_BUCKET"
}

# Configure lifecycle policy
configure_lifecycle_policy() {
    log_info "Configuring lifecycle policy..."
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" \
        --lifecycle-configuration '{
            "Rules": [
                {
                    "ID": "Transition to Infrequent Access",
                    "Status": "Enabled",
                    "Filter": {
                        "Prefix": ""
                    },
                    "Transitions": [
                        {
                            "Days": 90,
                            "StorageClass": "STANDARD_IA"
                        }
                    ]
                },
                {
                    "ID": "Delete old versions after 1 year",
                    "Status": "Enabled",
                    "Filter": {
                        "Prefix": ""
                    },
                    "NoncurrentVersionTransitions": [
                        {
                            "NoncurrentDays": 30,
                            "StorageClass": "STANDARD_IA"
                        }
                    ],
                    "NoncurrentVersionExpiration": {
                        "NoncurrentDays": 365
                    }
                }
            ]
        }' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "Lifecycle policy configured"
}

# Create bucket policy
create_bucket_policy() {
    log_info "Creating bucket policy..."
    
    # Get AWS account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query 'Account' --output text)
    
    cat > /tmp/bucket-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowEC2Access",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-ec2-role"
            },
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy file:///tmp/bucket-policy.json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    rm /tmp/bucket-policy.json
    
    log_success "Bucket policy created"
}

# Create directory structure
create_directory_structure() {
    log_info "Creating directory structure..."
    
    # Create directories
    aws s3api put-object \
        --bucket "$BUCKET_NAME" \
        --key "pdfs/" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    aws s3api put-object \
        --bucket "$BUCKET_NAME" \
        --key "vector_store/" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    aws s3api put-object \
        --bucket "$BUCKET_NAME" \
        --key "backups/" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    aws s3api put-object \
        --bucket "$BUCKET_NAME" \
        --key "uploads/" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "Directory structure created"
}

# Backup configuration
backup_configuration() {
    log_info "Backing up S3 configuration..."
    
    mkdir -p "$HOME/.ragbot"
    
    cat > "$HOME/.ragbot/s3-config.json" <<EOF
{
    "bucket_name": "$BUCKET_NAME",
    "region": "$AWS_REGION",
    "versioning": $ENABLE_VERSIONING,
    "encryption": $ENABLE_ENCRYPTION,
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_success "Configuration saved to $HOME/.ragbot/s3-config.json"
}

# Display connection information
display_connection_info() {
    log_success "=== S3 Setup Completed Successfully ==="
    echo
    echo "Bucket Information:"
    echo "------------------"
    echo "Bucket Name: $BUCKET_NAME"
    echo "Region: $AWS_REGION"
    echo "ARN: arn:aws:s3:::$BUCKET_NAME"
    echo
    echo "Features Enabled:"
    echo "----------------"
    [[ "$ENABLE_VERSIONING" == "true" ]] && echo "✅ Versioning"
    [[ "$ENABLE_ENCRYPTION" == "true" ]] && echo "✅ Server-side encryption"
    echo "✅ Public access blocked"
    echo "✅ Access logging"
    echo "✅ Lifecycle policies"
    echo
    echo "AWS CLI Commands:"
    echo "----------------"
    echo "# List bucket contents"
    echo "aws s3 ls s3://$BUCKET_NAME/ --profile $AWS_PROFILE"
    echo
    echo "# Upload a file"
    echo "aws s3 cp local-file.pdf s3://$BUCKET_NAME/pdfs/ --profile $AWS_PROFILE"
    echo
    echo "# Download a file"
    echo "aws s3 cp s3://$BUCKET_NAME/pdfs/file.pdf local-file.pdf --profile $AWS_PROFILE"
    echo
    echo "# Sync local directory"
    echo "aws s3 sync ./local-pdfs/ s3://$BUCKET_NAME/pdfs/ --profile $AWS_PROFILE"
    echo
    echo "Cost Estimate:"
    echo "-------------"
    echo "S3 Standard: $0.023/GB-month"
    echo "S3 Standard-IA: $0.0125/GB-month"
    echo "Free Tier: 5GB free for 12 months"
    echo "Example: 3GB storage = $0.069/month or $0 with Free Tier"
}

# Main execution
main() {
    log_info "Starting S3 setup for RAG PDF Chatbot..."
    log_info "Region: $AWS_REGION"
    log_info "Profile: $AWS_PROFILE"
    
    check_prerequisites
    generate_bucket_name
    create_bucket
    enable_versioning
    enable_encryption
    block_public_access
    enable_logging
    configure_lifecycle_policy
    create_bucket_policy
    create_directory_structure
    backup_configuration
    display_connection_info
    
    log_success "S3 setup completed successfully!"
}

# Run main function
main "$@"