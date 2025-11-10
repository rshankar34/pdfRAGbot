#!/bin/bash

# EFS Setup Script for RAG PDF Chatbot
# This script creates and configures an EFS filesystem for vector store persistence

set -euo pipefail

# Configuration
PROJECT_NAME="${PROJECT_NAME:-ragbot}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"
PERFORMANCE_MODE="${PERFORMANCE_MODE:-generalPurpose}"
THROUGHPUT_MODE="${THROUGHPUT_MODE:-bursting}"

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

# Create EFS filesystem
create_efs_filesystem() {
    log_info "Creating EFS filesystem..."
    
    # Check if filesystem already exists
    EFS_ID=$(aws efs describe-file-systems \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query "FileSystems[?Tags[?Key=='Name' && Value=='${PROJECT_NAME}-vector-store']].FileSystemId" \
        --output text)
    
    if [[ -n "$EFS_ID" && "$EFS_ID" != "None" ]]; then
        log_info "EFS filesystem already exists: $EFS_ID"
        return 0
    fi
    
    # Create filesystem
    log_info "Creating new EFS filesystem..."
    EFS_ID=$(aws efs create-file-system \
        --performance-mode "$PERFORMANCE_MODE" \
        --throughput-mode "$THROUGHPUT_MODE" \
        --encrypted \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --tags \
            Key=Name,Value="${PROJECT_NAME}-vector-store" \
            Key=Project,Value="$PROJECT_NAME" \
            Key=Environment,Value="production" \
            Key=ManagedBy,Value="setup-script" \
        --query 'FileSystemId' \
        --output text)
    
    log_info "Waiting for filesystem to become available..."
    aws efs wait file-system-available \
        --file-system-id "$EFS_ID" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "EFS filesystem created: $EFS_ID"
}

# Configure lifecycle policy
configure_lifecycle_policy() {
    log_info "Configuring lifecycle policy..."
    
    aws efs put-lifecycle-configuration \
        --file-system-id "$EFS_ID" \
        --lifecycle-policies 'TransitionToIA=AFTER_30_DAYS' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "Lifecycle policy configured"
}

# Create mount targets
create_mount_targets() {
    log_info "Creating mount targets..."
    
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
    
    # Get subnets
    SUBNETS=$(aws ec2 describe-subnets \
        --filters Name=vpc-id,Values="$VPC_ID" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Subnets[*].{ID:SubnetId,AZ:AvailabilityZone}' \
        --output json)
    
    # Get or create security group
    SECURITY_GROUP_ID=$(setup_security_group "$VPC_ID")
    
    # Create mount targets for each subnet
    echo "$SUBNETS" | jq -r '.[].ID' | while read -r SUBNET_ID; do
        # Check if mount target already exists
        EXISTING_MT=$(aws efs describe-mount-targets \
            --file-system-id "$EFS_ID" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" \
            --query "MountTargets[?SubnetId=='$SUBNET_ID'].MountTargetId" \
            --output text)
        
        if [[ -n "$EXISTING_MT" && "$EXISTING_MT" != "None" ]]; then
            log_info "Mount target already exists in subnet $SUBNET_ID"
            continue
        fi
        
        log_info "Creating mount target in subnet $SUBNET_ID..."
        MT_ID=$(aws efs create-mount-target \
            --file-system-id "$EFS_ID" \
            --subnet-id "$SUBNET_ID" \
            --security-groups "$SECURITY_GROUP_ID" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" \
            --query 'MountTargetId' \
            --output text)
        
        # Wait for mount target to be available
        log_info "Waiting for mount target $MT_ID to become available..."
        aws efs wait mount-target-available \
            --file-system-id "$EFS_ID" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE"
        
        log_success "Mount target created: $MT_ID"
    done
}

# Setup security group for EFS
setup_security_group() {
    local VPC_ID="$1"
    
    # Check if security group already exists
    SG_ID=$(aws ec2 describe-security-groups \
        --filters \
            Name=group-name,Values="${PROJECT_NAME}-efs-sg" \
            Name=vpc-id,Values="$VPC_ID" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)
    
    if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
        echo "$SG_ID"
        return 0
    fi
    
    # Create security group
    log_info "Creating security group for EFS..."
    SG_ID=$(aws ec2 create-security-group \
        --group-name "${PROJECT_NAME}-efs-sg" \
        --description "Security group for RAGBot EFS access" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'GroupId' \
        --output text)
    
    # Add inbound rule for NFS (port 2049) from VPC CIDR
    VPC_CIDR=$(aws ec2 describe-vpcs \
        --vpc-ids "$VPC_ID" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Vpcs[0].CidrBlock' \
        --output text)
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 2049 \
        --cidr "$VPC_CIDR" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
    
    log_success "Security group created: $SG_ID"
    echo "$SG_ID"
}

# Create access points
create_access_points() {
    log_info "Creating EFS access points..."
    
    # Vector store access point
    VECTOR_AP_ID=$(aws efs create-access-point \
        --file-system-id "$EFS_ID" \
        --posix-user Uid=1000,Gid=1000 \
        --root-directory "Path=/vector_store,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=755}" \
        --tags Key=Name,Value="${PROJECT_NAME}-vector-store-ap" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'AccessPointId' \
        --output text)
    
    # PDFs access point
    PDFS_AP_ID=$(aws efs create-access-point \
        --file-system-id "$EFS_ID" \
        --posix-user Uid=1000,Gid=1000 \
        --root-directory "Path=/pdfs,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=755}" \
        --tags Key=Name,Value="${PROJECT_NAME}-pdfs-ap" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'AccessPointId' \
        --output text)
    
    log_success "Access points created:"
    log_info "  Vector store: $VECTOR_AP_ID"
    log_info "  PDFs: $PDFS_AP_ID"
}

# Backup configuration
backup_configuration() {
    log_info "Backing up EFS configuration..."
    
    mkdir -p "$HOME/.ragbot"
    
    cat > "$HOME/.ragbot/efs-config.json" <<EOF
{
    "file_system_id": "$EFS_ID",
    "region": "$AWS_REGION",
    "performance_mode": "$PERFORMANCE_MODE",
    "throughput_mode": "$THROUGHPUT_MODE",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_success "Configuration saved to $HOME/.ragbot/efs-config.json"
}

# Display connection information
display_connection_info() {
    log_success "=== EFS Setup Completed Successfully ==="
    echo
    echo "Connection Information:"
    echo "----------------------"
    echo "File System ID: $EFS_ID"
    echo "Region: $AWS_REGION"
    echo
    echo "Mount Commands:"
    echo "--------------"
    echo "# Install amazon-efs-utils if not already installed"
    echo "sudo apt-get install -y amazon-efs-utils"
    echo
    echo "# Mount using EFS mount helper (recommended)"
    echo "sudo mount -t efs -o tls $EFS_ID:/ /mnt/efs"
    echo
    echo "# Mount using NFS (alternative)"
    echo "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $EFS_ID.efs.$AWS_REGION.amazonaws.com:/ /mnt/efs"
    echo
    echo "# Add to /etc/fstab for automatic mounting"
    echo "$EFS_ID:/ /mnt/efs efs defaults,_netdev,tls 0 0"
    echo
    echo "Access Points:"
    echo "-------------"
    echo "Vector Store: $VECTOR_AP_ID"
    echo "PDFs: $PDFS_AP_ID"
    echo
    echo "Mount using access points:"
    echo "sudo mount -t efs -o tls,accesspoint=$VECTOR_AP_ID $EFS_ID:/ /mnt/vector_store"
    echo "sudo mount -t efs -o tls,accesspoint=$PDFS_AP_ID $EFS_ID:/ /mnt/pdfs"
    echo
    echo "Cost Estimate:"
    echo "-------------"
    echo "EFS Standard: $0.30/GB-month"
    echo "Free Tier: 5GB-months free for 12 months"
    echo "Example: 1GB storage = $0.30/month or $0 with Free Tier"
}

# Main execution
main() {
    log_info "Starting EFS setup for RAG PDF Chatbot..."
    log_info "Region: $AWS_REGION"
    log_info "Profile: $AWS_PROFILE"
    
    check_prerequisites
    create_efs_filesystem
    configure_lifecycle_policy
    create_mount_targets
    create_access_points
    backup_configuration
    display_connection_info
    
    log_success "EFS setup completed successfully!"
}

# Run main function
main "$@"