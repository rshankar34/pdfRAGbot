#!/bin/bash

# AWS Secrets Manager Setup Script for RAG PDF Chatbot
# This script creates and configures AWS Secrets Manager for storing sensitive data

set -euo pipefail

# Configuration
PROJECT_NAME="${PROJECT_NAME:-ragbot}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"
SECRET_NAME="${SECRET_NAME:-ragbot/openai-api-key}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
ROTATION_ENABLED="${ROTATION_ENABLED:-false}"

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

# Prompt for OpenAI API key if not provided
prompt_for_api_key() {
    if [[ -z "$OPENAI_API_KEY" ]]; then
        log_info "OpenAI API key not provided"
        echo
        echo "Please enter your OpenAI API key:"
        echo "You can get this from https://platform.openai.com/api-keys"
        echo
        read -rsp "OpenAI API Key: " OPENAI_API_KEY
        echo
        echo
        
        if [[ -z "$OPENAI_API_KEY" ]]; then
            log_error "OpenAI API key is required"
            exit 1
        fi
    fi
    
    # Validate API key format
    if [[ ! "$OPENAI_API_KEY" =~ ^sk-[a-zA-Z0-9]{20,}$ ]]; then
        log_warning "API key format doesn't match expected pattern"
        echo "Expected format: sk-..."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check if secret already exists
check_secret_exists() {
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --profile "$AWS_PROFILE" --region "$AWS_REGION" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Create secret
create_secret() {
    log_info "Creating secret: $SECRET_NAME"
    
    # Check if secret already exists
    if check_secret_exists; then
        log_warning "Secret $SECRET_NAME already exists"
        
        read -p "Do you want to update it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_secret
        fi
        return 0
    fi
    
    # Create secret
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "OpenAI API key for RAG PDF Chatbot" \
        --secret-string "{\"OPENAI_API_KEY\":\"$OPENAI_API_KEY\"}" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --tags \
            Key=Project,Value="$PROJECT_NAME" \
            Key=Environment,Value="production" \
            Key=ManagedBy,Value="setup-script"
    
    log_success "Secret created successfully"
}

# Update secret
update_secret() {
    log_info "Updating secret: $SECRET_NAME"
    
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "{\"OPENAI_API_KEY\":\"$OPENAI_API_KEY\"}" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "Secret updated successfully"
}

# Configure rotation (optional)
configure_rotation() {
    if [[ "$ROTATION_ENABLED" != "true" ]]; then
        log_info "Skipping rotation setup"
        return 0
    fi
    
    log_info "Configuring secret rotation..."
    
    # Create Lambda function for rotation (simplified version)
    # In production, you would use a more sophisticated rotation function
    cat > /tmp/rotation-function.py <<'EOF'
import json
import boto3
import secrets
import string

def lambda_handler(event, context):
    """Simple rotation function for OpenAI API key"""
    # This is a placeholder - in production, you'd implement actual key rotation
    # For OpenAI, this would involve:
    # 1. Creating a new API key via OpenAI API
    # 2. Updating the secret
    # 3. Deleting the old API key
    
    print("Rotation triggered")
    print(f"Event: {json.dumps(event)}")
    
    # For now, just return success
    return {
        'statusCode': 200,
        'body': json.dumps('Rotation completed successfully')
    }
EOF
    
    log_warning "Rotation setup requires manual configuration of Lambda function"
    log_info "See AWS documentation for implementing secret rotation"
}

# Create IAM policy for accessing the secret
create_iam_policy() {
    log_info "Creating IAM policy for secret access..."
    
    local POLICY_NAME="${PROJECT_NAME}-secrets-policy"
    local POLICY_ARN="arn:aws:iam::$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query 'Account' --output text):policy/$POLICY_NAME"
    
    # Check if policy already exists
    if aws iam get-policy --policy-arn "$POLICY_ARN" --profile "$AWS_PROFILE" &>/dev/null; then
        log_info "Policy $POLICY_NAME already exists"
        return 0
    fi
    
    # Create policy document
    cat > /tmp/secrets-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "arn:aws:secretsmanager:${AWS_REGION}:$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query 'Account' --output text):secret:${PROJECT_NAME}/*"
        }
    ]
}
EOF
    
    # Create policy
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/secrets-policy.json \
        --profile "$AWS_PROFILE"
    
    rm /tmp/secrets-policy.json
    
    log_success "IAM policy created: $POLICY_NAME"
    log_info "Policy ARN: $POLICY_ARN"
}

# Test secret access
test_secret_access() {
    log_info "Testing secret access..."
    
    # Try to retrieve the secret
    RETRIEVED_KEY=$(aws secretsmanager get-secret-value \
        --secret-id "$SECRET_NAME" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'SecretString' \
        --output text | grep -o '"OPENAI_API_KEY":"[^"]*' | cut -d'"' -f4)
    
    if [[ "$RETRIEVED_KEY" == "$OPENAI_API_KEY" ]]; then
        log_success "Secret access test passed"
    else
        log_error "Secret access test failed"
        exit 1
    fi
}

# Backup configuration
backup_configuration() {
    log_info "Backing up Secrets Manager configuration..."
    
    mkdir -p "$HOME/.ragbot"
    
    cat > "$HOME/.ragbot/secrets-config.json" <<EOF
{
    "secret_name": "$SECRET_NAME",
    "region": "$AWS_REGION",
    "rotation_enabled": $ROTATION_ENABLED,
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    # Also save the secret ARN
    SECRET_ARN=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET_NAME" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'ARN' \
        --output text)
    
    echo "  \"secret_arn\": \"$SECRET_ARN\"" >> "$HOME/.ragbot/secrets-config.json"
    
    log_success "Configuration saved to $HOME/.ragbot/secrets-config.json"
}

# Display connection information
display_connection_info() {
    log_success "=== Secrets Manager Setup Completed Successfully ==="
    echo
    echo "Secret Information:"
    echo "------------------"
    echo "Name: $SECRET_NAME"
    echo "ARN: $SECRET_ARN"
    echo "Region: $AWS_REGION"
    echo
    echo "AWS CLI Commands:"
    echo "----------------"
    echo "# Retrieve secret value"
    echo "aws secretsmanager get-secret-value --secret-id $SECRET_NAME --region $AWS_REGION --profile $AWS_PROFILE"
    echo
    echo "# Update secret value"
    echo "aws secretsmanager update-secret --secret-id $SECRET_NAME --secret-string '{\"OPENAI_API_KEY\":\"new_key\"}' --region $AWS_REGION --profile $AWS_PROFILE"
    echo
    echo "# List all secrets"
    echo "aws secretsmanager list-secrets --region $AWS_REGION --profile $AWS_PROFILE"
    echo
    echo "Python Integration:"
    echo "------------------"
    echo "import boto3"
    echo "import json"
    echo ""
    echo "def get_openai_api_key():"
    echo "    secret_name = '$SECRET_NAME'"
    echo "    region_name = '$AWS_REGION'"
    echo ""
    echo "    session = boto3.session.Session()"
    echo "    client = session.client("
    echo "        service_name='secretsmanager',"
    echo "        region_name=region_name"
    echo "    )"
    echo ""
    echo "    try:"
    echo "        response = client.get_secret_value(SecretId=secret_name)"
    echo "        secret = json.loads(response['SecretString'])"
    echo "        return secret['OPENAI_API_KEY']"
    echo "    except Exception as e:"
    echo "        print(f'Error retrieving secret: {e}')"
    echo "        raise"
    echo
    echo "Cost Estimate:"
    echo "-------------"
    echo "Secrets Manager: $0.40/secret/month"
    echo "API calls: $0.05/10,000 calls"
    echo "Free Tier: 30 days free trial"
    echo "Example: 1 secret + 1,000 API calls = $0.40/month"
}

# Main execution
main() {
    log_info "Starting Secrets Manager setup for RAG PDF Chatbot..."
    log_info "Region: $AWS_REGION"
    log_info "Profile: $AWS_PROFILE"
    
    check_prerequisites
    prompt_for_api_key
    create_secret
    configure_rotation
    create_iam_policy
    test_secret_access
    backup_configuration
    display_connection_info
    
    log_success "Secrets Manager setup completed successfully!"
}

# Run main function
main "$@"