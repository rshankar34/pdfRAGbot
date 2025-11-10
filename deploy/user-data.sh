#!/bin/bash

# EC2 User Data Script for RAG PDF Chatbot
# This script runs on first boot of the EC2 instance
# It sets up the environment and starts the application

set -euo pipefail

# Configuration
APP_DIR="/opt/ragbot"
EFS_MOUNT_POINT="/mnt/efs"
VECTOR_STORE_DIR="$EFS_MOUNT_POINT/vector_store"
PDF_STORAGE_DIR="$EFS_MOUNT_POINT/pdfs"
S3_BUCKET="${S3_BUCKET:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SECRET_NAME="${SECRET_NAME:-ragbot/openai-api-key}"

# Logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Starting RAG PDF Chatbot Setup ==="
echo "Timestamp: $(date)"

# Update system packages
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required packages
echo "Installing required packages..."
apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3-pip \
    git \
    curl \
    wget \
    unzip \
    amazon-efs-utils \
    awscli \
    cloud-init \
    systemd

# Install Docker (optional, for containerized deployment)
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# Install Docker Compose
echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create application directory
echo "Creating application directory..."
mkdir -p "$APP_DIR"
mkdir -p "$EFS_MOUNT_POINT"
mkdir -p "$VECTOR_STORE_DIR"
mkdir -p "$PDF_STORAGE_DIR"
mkdir -p /var/log/ragbot

# Mount EFS filesystem
echo "Mounting EFS filesystem..."
# Get EFS ID from tags
EFS_ID=$(aws efs describe-file-systems \
    --region "$AWS_REGION" \
    --query "FileSystems[?Tags[?Key=='Name' && Value=='ragbot-vector-store']].FileSystemId" \
    --output text)

if [[ -n "$EFS_ID" && "$EFS_ID" != "None" ]]; then
    echo "Mounting EFS filesystem $EFS_ID..."
    mount -t efs -o tls "$EFS_ID:/" "$EFS_MOUNT_POINT"
    
    # Add to fstab for automatic mounting on reboot
    echo "$EFS_ID:/ $EFS_MOUNT_POINT efs defaults,_netdev,tls 0 0" >> /etc/fstab
    
    log_success "EFS mounted successfully at $EFS_MOUNT_POINT"
else
    echo "Warning: EFS filesystem not found. Using local storage."
    VECTOR_STORE_DIR="$APP_DIR/data/vector_store"
    PDF_STORAGE_DIR="$APP_DIR/data/pdfs"
    mkdir -p "$VECTOR_STORE_DIR"
    mkdir -p "$PDF_STORAGE_DIR"
fi

# Clone or download application code
echo "Setting up application code..."
cd "$APP_DIR"

# Try to get code from S3 first (if deployment package exists)
if aws s3 ls "s3://$S3_BUCKET/deployment/app.tar.gz" &>/dev/null; then
    echo "Downloading application from S3..."
    aws s3 cp "s3://$S3_BUCKET/deployment/app.tar.gz" /tmp/app.tar.gz
    tar -xzf /tmp/app.tar.gz -C "$APP_DIR"
    rm /tmp/app.tar.gz
else
    echo "Cloning repository from GitHub..."
    git clone https://github.com/yourusername/v3_RAGBOT.git "$APP_DIR" || {
        echo "Warning: Could not clone repository. Creating minimal setup."
        mkdir -p "$APP_DIR/data"
    }
fi

# Set ownership
chown -R ubuntu:ubuntu "$APP_DIR"
chown -R ubuntu:ubuntu "$EFS_MOUNT_POINT"

# Create Python virtual environment
echo "Creating Python virtual environment..."
cd "$APP_DIR"
sudo -u ubuntu python3.11 -m venv venv
sudo -u ubuntu "$APP_DIR/venv/bin/pip" install --upgrade pip

# Install Python dependencies
echo "Installing Python dependencies..."
if [[ -f "$APP_DIR/requirements.txt" ]]; then
    sudo -u ubuntu "$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt"
else
    echo "Warning: requirements.txt not found. Installing minimal dependencies."
    sudo -u ubuntu "$APP_DIR/venv/bin/pip" install \
        streamlit \
        python-dotenv \
        langchain \
        langchain-openai \
        langchain-community \
        faiss-cpu \
        sentence-transformers \
        pypdf \
        openai \
        tiktoken \
        boto3
fi

# Get OpenAI API key from Secrets Manager
echo "Retrieving OpenAI API key from Secrets Manager..."
OPENAI_API_KEY=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$AWS_REGION" \
    --query 'SecretString' \
    --output text | grep -o '"OPENAI_API_KEY":"[^"]*' | cut -d'"' -f4)

if [[ -z "$OPENAI_API_KEY" ]]; then
    echo "Error: Could not retrieve OpenAI API key from Secrets Manager"
    exit 1
fi

# Create .env file
echo "Creating environment configuration..."
sudo -u ubuntu tee "$APP_DIR/.env" > /dev/null <<EOF
# OpenAI API Configuration
OPENAI_API_KEY=$OPENAI_API_KEY

# Application Configuration
VECTOR_STORE_PATH=$VECTOR_STORE_DIR
PDF_STORAGE_DIR=$PDF_STORAGE_DIR
AWS_REGION=$AWS_REGION
S3_BUCKET=$S3_BUCKET

# Model Configuration
LLM_MODEL=gpt-3.5-turbo
TEMPERATURE=0.3
MAX_TOKENS=500
CHUNK_SIZE=1000
CHUNK_OVERLAP=200
RETRIEVAL_TOP_K=4

# Logging
LOG_LEVEL=INFO
EOF

# Download existing vector store from S3 if available
echo "Checking for existing vector store in S3..."
if [[ -n "$S3_BUCKET" ]] && aws s3 ls "s3://$S3_BUCKET/vector_store/" &>/dev/null; then
    echo "Downloading vector store from S3..."
    aws s3 sync "s3://$S3_BUCKET/vector_store/" "$VECTOR_STORE_DIR/"
    chown -R ubuntu:ubuntu "$VECTOR_STORE_DIR"
fi

# Download PDFs from S3 if available
echo "Checking for existing PDFs in S3..."
if [[ -n "$S3_BUCKET" ]] && aws s3 ls "s3://$S3_BUCKET/pdfs/" &>/dev/null; then
    echo "Downloading PDFs from S3..."
    aws s3 sync "s3://$S3_BUCKET/pdfs/" "$PDF_STORAGE_DIR/"
    chown -R ubuntu:ubuntu "$PDF_STORAGE_DIR"
fi

# Create systemd service file
echo "Creating systemd service..."
cat > /etc/systemd/system/ragbot.service <<EOF
[Unit]
Description=RAG PDF Chatbot
After=network.target
Wants=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=$APP_DIR
Environment=PATH=$APP_DIR/venv/bin
Environment=PYTHONUNBUFFERED=1
Environment=HOME=/home/ubuntu
ExecStartPre=/bin/sleep 30
ExecStart=$APP_DIR/venv/bin/streamlit run app.py \
    --server.port=8501 \
    --server.address=0.0.0.0 \
    --server.headless=true \
    --server.enableCORS=false \
    --server.enableXsrfProtection=false \
    --server.maxUploadSize=50 \
    --server.maxMessageSize=50
Restart=always
RestartSec=10
StandardOutput=append:/var/log/ragbot/app.log
StandardError=append:/var/log/ragbot/error.log

[Install]
WantedBy=multi-user.target
EOF

# Create log rotation configuration
cat > /etc/logrotate.d/ragbot <<EOF
/var/log/ragbot/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 ubuntu ubuntu
    sharedscripts
    postrotate
        systemctl reload ragbot > /dev/null 2>&1 || true
    endscript
}
EOF

# Setup CloudWatch agent
echo "Setting up CloudWatch agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "root"
    },
    "metrics": {
        "namespace": "RAGBot",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "totalcpu": false
            },
            "disk": {
                "measurement": [
                    "used_percent",
                    "inodes_free"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "swap": {
                "measurement": [
                    "swap_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/ragbot/app.log",
                        "log_group_name": "ragbot-application",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 7
                    },
                    {
                        "file_path": "/var/log/ragbot/error.log",
                        "log_group_name": "ragbot-errors",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 7
                    },
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "ragbot-user-data",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 3
                    }
                ]
            }
        }
    }
}
EOF

# Enable and start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Reload systemd and start the service
echo "Starting RAG PDF Chatbot service..."
systemctl daemon-reload
systemctl enable ragbot.service
systemctl start ragbot.service

# Wait for service to start
sleep 10

# Check service status
if systemctl is-active --quiet ragbot.service; then
    echo "=== RAG PDF Chatbot Setup Completed Successfully ==="
    echo "Service is running and accessible at http://$(curl -s https://checkip.amazonaws.com):8501"
    echo "Logs are available at: /var/log/ragbot/"
    echo "CloudWatch metrics and logs are being sent to AWS"
else
    echo "=== RAG PDF Chatbot Setup Failed ==="
    echo "Service failed to start. Check logs:"
    echo "  journalctl -u ragbot.service"
    echo "  tail -f /var/log/ragbot/error.log"
    exit 1
fi

echo "Setup completed at $(date)"