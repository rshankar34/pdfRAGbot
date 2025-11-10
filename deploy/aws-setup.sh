#!/bin/bash

# Main AWS Setup Script for RAG PDF Chatbot
# This script orchestrates the complete AWS deployment

set -euo pipefail

# Configuration
PROJECT_NAME="${PROJECT_NAME:-ragbot}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

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
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        echo "Please install AWS CLI: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &> /dev/null; then
        log_error "AWS credentials not configured"
        echo "Please run: aws configure --profile $AWS_PROFILE"
        exit 1
    fi
    
    # Check required tools
    for tool in jq openssl; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Display welcome message
display_welcome() {
    echo
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         RAG PDF Chatbot - AWS Deployment Setup              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
    echo "This script will set up the following AWS resources:"
    echo "  • S3 bucket for PDF storage"
    echo "  • EFS filesystem for vector store persistence"
    echo "  • Secrets Manager for OpenAI API key"
    echo "  • EC2 instance with proper configuration"
    echo "  • Security groups and IAM roles"
    echo
    echo "Region: $AWS_REGION"
    echo "Profile: $AWS_PROFILE"
    echo "Project: $PROJECT_NAME"
    echo
}

# Prompt for confirmation
prompt_confirmation() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    read -p "Do you want to continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled"
        exit 0
    fi
}

# Setup S3 bucket
setup_s3() {
    log_info "Setting up S3 bucket..."
    
    export PROJECT_NAME="$PROJECT_NAME"
    export AWS_REGION="$AWS_REGION"
    export AWS_PROFILE="$AWS_PROFILE"
    
    if ! bash "$SCRIPT_DIR/setup-s3.sh"; then
        log_error "S3 setup failed"
        exit 1
    fi
    
    # Load S3 bucket name from configuration
    if [[ -f "$HOME/.ragbot/s3-config.json" ]]; then
        S3_BUCKET=$(jq -r '.bucket_name' "$HOME/.ragbot/s3-config.json")
        export S3_BUCKET
        log_success "S3 bucket configured: $S3_BUCKET"
    fi
}

# Setup EFS
setup_efs() {
    log_info "Setting up EFS filesystem..."
    
    export PROJECT_NAME="$PROJECT_NAME"
    export AWS_REGION="$AWS_REGION"
    export AWS_PROFILE="$AWS_PROFILE"
    
    if ! bash "$SCRIPT_DIR/setup-efs.sh"; then
        log_error "EFS setup failed"
        exit 1
    fi
    
    # Load EFS ID from configuration
    if [[ -f "$HOME/.ragbot/efs-config.json" ]]; then
        EFS_ID=$(jq -r '.file_system_id' "$HOME/.ragbot/efs-config.json")
        export EFS_ID
        log_success "EFS filesystem configured: $EFS_ID"
    fi
}

# Setup Secrets Manager
setup_secrets() {
    log_info "Setting up Secrets Manager..."
    
    export PROJECT_NAME="$PROJECT_NAME"
    export AWS_REGION="$AWS_REGION"
    export AWS_PROFILE="$AWS_PROFILE"
    export OPENAI_API_KEY="$OPENAI_API_KEY"
    
    if ! bash "$SCRIPT_DIR/setup-secrets.sh"; then
        log_error "Secrets Manager setup failed"
        exit 1
    fi
    
    log_success "Secrets Manager configured"
}

# Create IAM role for EC2
create_iam_role() {
    log_info "Creating IAM role for EC2..."
    
    local ROLE_NAME="${PROJECT_NAME}-ec2-role"
    local INSTANCE_PROFILE_NAME="${PROJECT_NAME}-ec2-instance-profile"
    
    # Check if role already exists
    if aws iam get-role --role-name "$ROLE_NAME" --profile "$AWS_PROFILE" &>/dev/null; then
        log_info "IAM role $ROLE_NAME already exists"
    else
        # Create trust policy
        cat > /tmp/trust-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
        
        # Create role
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file:///tmp/trust-policy.json \
            --description "IAM role for RAG PDF Chatbot EC2 instance" \
            --profile "$AWS_PROFILE"
        
        log_success "IAM role created: $ROLE_NAME"
    fi
    
    # Attach policies
    log_info "Attaching policies to role..."
    
    # AmazonS3ReadOnlyAccess
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" \
        --profile "$AWS_PROFILE"
    
    # AmazonSSMManagedInstanceCore
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" \
        --profile "$AWS_PROFILE"
    
    # SecretsManagerReadWrite
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/SecretsManagerReadWrite" \
        --profile "$AWS_PROFILE"
    
    # CloudWatchAgentServerPolicy
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" \
        --profile "$AWS_PROFILE"
    
    # Create or update instance profile
    if ! aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --profile "$AWS_PROFILE" &>/dev/null; then
        aws iam create-instance-profile \
            --instance-profile-name "$INSTANCE_PROFILE_NAME" \
            --profile "$AWS_PROFILE"
    fi
    
    # Add role to instance profile
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$INSTANCE_PROFILE_NAME" \
        --role-name "$ROLE_NAME" \
        --profile "$AWS_PROFILE"
    
    log_success "IAM role and policies configured"
    
    # Clean up
    rm -f /tmp/trust-policy.json
}

# Create security group
create_security_group() {
    log_info "Creating security group..."
    
    local SG_NAME="${PROJECT_NAME}-sg"
    
    # Get default VPC
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters Name=is-default,Values=true \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
        log_error "No default VPC found"
        exit 1
    fi
    
    # Check if security group already exists
    SG_ID=$(aws ec2 describe-security-groups \
        --filters \
            Name=group-name,Values="$SG_NAME" \
            Name=vpc-id,Values="$VPC_ID" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)
    
    if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
        log_info "Security group $SG_NAME already exists: $SG_ID"
        export SECURITY_GROUP_ID="$SG_ID"
        return 0
    fi
    
    # Create security group
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "Security group for RAG PDF Chatbot" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'GroupId' \
        --output text)
    
    # Add inbound rules
    # SSH (port 22) - from current IP only
    CURRENT_IP=$(curl -s https://checkip.amazonaws.com)
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr "${CURRENT_IP}/32" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    # HTTP (port 8501) - from anywhere
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 8501 \
        --cidr "0.0.0.0/0" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    # HTTPS (port 443) - from anywhere
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 443 \
        --cidr "0.0.0.0/0" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "Security group created: $SG_ID"
    export SECURITY_GROUP_ID="$SG_ID"
}

# Upload deployment package to S3
upload_deployment_package() {
    log_info "Creating and uploading deployment package..."
    
    if [[ -z "${S3_BUCKET:-}" ]]; then
        log_warning "S3 bucket not configured, skipping deployment package upload"
        return 0
    fi
    
    # Create deployment package
    local PACKAGE_DIR="/tmp/ragbot-deployment"
    mkdir -p "$PACKAGE_DIR"
    
    # Copy application files
    cp -r ./* "$PACKAGE_DIR/" 2>/dev/null || true
    
    # Create tarball
    cd /tmp
    tar -czf ragbot-deployment.tar.gz -C "$PACKAGE_DIR" .
    
    # Upload to S3
    aws s3 cp ragbot-deployment.tar.gz \
        "s3://${S3_BUCKET}/deployment/ragbot-deployment.tar.gz" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    # Clean up
    rm -rf "$PACKAGE_DIR"
    rm -f ragbot-deployment.tar.gz
    
    log_success "Deployment package uploaded to S3"
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    log_info "Creating CloudWatch alarms..."
    
    # Note: This will be done after EC2 instance is launched
    # The actual alarm creation is in the user-data script
    log_info "CloudWatch alarms will be configured during instance launch"
}

# Display summary
display_summary() {
    log_success "=== AWS Setup Completed Successfully ==="
    echo
    echo "Resources Created:"
    echo "-----------------"
    [[ -n "${S3_BUCKET:-}" ]] && echo "✅ S3 Bucket: $S3_BUCKET"
    [[ -n "${EFS_ID:-}" ]] && echo "✅ EFS Filesystem: $EFS_ID"
    echo "✅ Secrets Manager: $SECRET_NAME"
    [[ -n "${SECURITY_GROUP_ID:-}" ]] && echo "✅ Security Group: $SECURITY_GROUP_ID"
    echo
    echo "Next Steps:"
    echo "----------"
    echo "1. Review the configuration in ~/.ragbot/"
    echo "2. Launch EC2 instance using the user-data script"
    echo "3. Access your application at http://<ec2-ip>:8501"
    echo
    echo "To launch EC2 instance:"
    echo "aws ec2 run-instances \\"
    echo "  --image-id ami-0c55b159cbfafe1f0 \\"
    echo "  --instance-type t2.micro \\"
    echo "  --key-name your-key-pair \\"
    echo "  --security-group-ids $SECURITY_GROUP_ID \\"
    echo "  --iam-instance-profile Name=${PROJECT_NAME}-ec2-instance-profile \\"
    echo "  --user-data file://deploy/user-data.sh \\"
    echo "  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}}]' \\"
    echo "  --region $AWS_REGION \\"
    echo "  --profile $AWS_PROFILE"
    echo
    echo "Cost Estimate:"
    echo "-------------"
    echo "EC2 t2.micro: $0.00/month (Free Tier)"
    echo "S3 Storage: $0.00/month (Free Tier - 5GB)"
    echo "EFS Storage: $0.00/month (Free Tier - 5GB)"
    echo "Secrets Manager: $0.40/month"
    echo "Total: ~$0.40/month (plus OpenAI API usage)"
}

# Main execution
main() {
    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    export SCRIPT_DIR
    
    display_welcome
    prompt_confirmation
    
    log_info "Starting AWS setup..."
    
    # Run setup steps
    setup_s3
    setup_efs
    setup_secrets
    create_iam_role
    create_security_group
    upload_deployment_package
    create_cloudwatch_alarms
    
    display_summary
    
    log_success "AWS setup completed successfully!"
}

# Handle script interruption
trap 'log_error "Setup interrupted"; exit 1' INT TERM

# Run main function
main "$@"