# AWS Deployment Guide - RAG PDF Chatbot

Complete step-by-step guide for deploying the RAG PDF Chatbot on AWS with cost optimization and security best practices.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Step-by-Step Deployment](#step-by-step-deployment)
4. [Configuration Details](#configuration-details)
5. [Post-Deployment Verification](#post-deployment-verification)
6. [Cost Optimization](#cost-optimization)
7. [Security Best Practices](#security-best-practices)
8. [Monitoring & Maintenance](#monitoring--maintenance)

---

## 🎯 Prerequisites

### Required Accounts & Tools

- **AWS Account** with Free Tier eligibility (12 months)
- **OpenAI Account** with API key
- **AWS CLI** installed and configured
- **Git** for version control
- **Python 3.10+** for local testing

### Local Setup

```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS credentials
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter region: us-east-1
# Output format: json

# Verify configuration
aws sts get-caller-identity
```

### OpenAI API Key

1. Go to [OpenAI Platform](https://platform.openai.com/api-keys)
2. Create a new API key
3. Set up billing with usage limits ($5-15/month recommended)
4. Copy your API key for later use

---

## 🏗️ Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────┐
│                  Internet                        │
└───────────────────┬─────────────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │   Route 53 (DNS)     │  Optional: Custom domain
         └──────────┬───────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  EC2 t2.micro        │  ← Streamlit App (Free Tier)
         │  Ubuntu 22.04        │
         └──────────┬───────────┘
                    │
        ┌───────────┴──────────┐
        │                      │
        ▼                      ▼
┌─────────────────┐   ┌──────────────────┐
│  EFS (5GB Free) │   │   OpenAI API     │
│  Vector Store   │   │  (Pay per query) │
└─────────────────┘   └──────────────────┘
        │
        ▼
┌─────────────────┐
│   S3 Bucket     │  ← PDF Storage (5GB Free)
│  (Read-only)    │
└─────────────────┘
```

### Component Details

| Component | Service | Free Tier | Purpose |
|-----------|---------|-----------|---------|
| **Compute** | EC2 t2.micro | 750 hrs/month | Streamlit application |
| **Storage** | EFS Standard | 5GB/month | Vector store persistence |
| **Object Storage** | S3 Standard | 5GB/month | PDF backup storage |
| **Secrets** | Secrets Manager | 30 days free | API key management |
| **Monitoring** | CloudWatch | Free tier | Logs and metrics |

---

## 🚀 Step-by-Step Deployment

### Phase 1: Local Preparation (15 minutes)

#### Step 1.1: Clone Repository

```bash
# Clone the repository
git clone https://github.com/yourusername/v3_RAGBOT.git
cd v3_RAGBOT

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

#### Step 1.2: Process PDFs Locally

```bash
# Create data directories
mkdir -p data/pdfs data/vector_store

# Copy your PDFs to data/pdfs/
# Process all PDFs locally (one-time, FREE)
python scripts/process-pdfs-local.py

# This creates the vector store in data/vector_store/
# Takes 30-60 minutes for 500 PDFs
```

#### Step 1.3: Test Locally

```bash
# Set OpenAI API key
export OPENAI_API_KEY="your-api-key-here"

# Test the application
streamlit run app.py

# Verify it works at http://localhost:8501
```

#### Step 1.4: Create Deployment Package

```bash
# Create deployment package
tar -czf deployment-package.tar.gz \
    app.py \
    requirements.txt \
    config/ \
    data/vector_store/ \
    .env.example

# Upload to S3 (optional, for easy deployment)
aws s3 cp deployment-package.tar.gz s3://your-bucket-name/
```

---

### Phase 2: AWS Infrastructure Setup (20 minutes)

#### Step 2.1: Run Automated Setup Script

```bash
# Make script executable
chmod +x deploy/aws-setup.sh

# Run setup (interactive)
./deploy/aws-setup.sh

# Or run with parameters (non-interactive)
PROJECT_NAME="ragbot-demo" \
OPENAI_API_KEY="sk-..." \
./deploy/aws-setup.sh --skip-confirmation
```

**What the script does:**
- Creates S3 bucket for PDF storage
- Creates EFS filesystem for vector store
- Stores OpenAI API key in Secrets Manager
- Creates IAM role with necessary permissions
- Creates security group with proper rules
- Uploads deployment package to S3

#### Step 2.2: Manual Verification

```bash
# Check created resources
aws s3 ls
aws efs describe-file-systems
aws secretsmanager list-secrets
aws ec2 describe-security-groups
```

---

### Phase 3: Launch EC2 Instance (10 minutes)

#### Step 3.1: Launch Instance with User Data

```bash
# Get your configuration values
source ~/.ragbot/config.sh

# Launch EC2 instance
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.micro \
  --key-name your-key-pair \
  --security-group-ids $SECURITY_GROUP_ID \
  --iam-instance-profile Name=$IAM_INSTANCE_PROFILE \
  --user-data file://deploy/user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ragbot-demo}]' \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20}}]' \
  --region us-east-1
```

#### Step 3.2: Wait for Instance to Initialize

```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=ragbot-demo" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Wait for instance to be running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "Instance running at: $PUBLIC_IP"
```

---

### Phase 4: Application Deployment (15 minutes)

#### Step 4.1: Connect to Instance

```bash
# SSH into instance
ssh -i ~/.ssh/your-key.pem ubuntu@$PUBLIC_IP

# Or use AWS Systems Manager (no key needed)
aws ssm start-session --target $INSTANCE_ID
```

#### Step 4.2: Monitor Deployment Progress

```bash
# Check user-data script progress
tail -f /var/log/cloud-init-output.log

# Check system logs
sudo journalctl -u ragbot -f

# Check application logs
tail -f /var/log/ragbot/app.log
```

#### Step 4.3: Verify Application Status

```bash
# Check if service is running
sudo systemctl status ragbot

# Check port 8501
sudo netstat -tlnp | grep 8501

# Test local connection
curl http://localhost:8501
```

---

### Phase 5: Configure Domain & SSL (Optional, 10 minutes)

#### Step 5.1: Allocate Elastic IP

```bash
# Allocate Elastic IP (free when attached)
ALLOCATION_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --query 'AllocationId' \
  --output text)

# Associate with instance
aws ec2 associate-address \
  --instance-id $INSTANCE_ID \
  --allocation-id $ALLOCATION_ID
```

#### Step 5.2: Setup Route 53 Domain

```bash
# Create hosted zone (if you have a domain)
aws route53 create-hosted-zone \
  --name yourdomain.com \
  --caller-reference $(date +%s)

# Create A record
aws route53 change-resource-record-sets \
  --hosted-zone-id YOUR_ZONE_ID \
  --change-batch file://route53-record.json
```

#### Step 5.3: Setup SSL with Let's Encrypt

```bash
# SSH into instance
ssh -i ~/.ssh/your-key.pem ubuntu@$PUBLIC_IP

# Install certbot
sudo apt install certbot python3-certbot-nginx -y

# Get SSL certificate
sudo certbot certonly --standalone -d yourdomain.com

# Configure Streamlit for HTTPS
sudo nano /etc/systemd/system/ragbot.service
# Add SSL parameters
```

---

## ⚙️ Configuration Details

### Environment Variables

```bash
# /opt/ragbot/.env
OPENAI_API_KEY=sk-...  # Retrieved from Secrets Manager
VECTOR_STORE_PATH=/mnt/efs/vector_store
PDF_STORAGE_PATH=s3://ragbot-pdfs/pdfs/
LOG_LEVEL=INFO
MAX_QUERY_TOKENS=500
TEMPERATURE=0.3
```

### Application Configuration

```python
# config/production.py
import os

class ProductionConfig:
    # AWS Services
    S3_BUCKET = os.getenv('S3_BUCKET', 'ragbot-pdfs')
    EFS_MOUNT = '/mnt/efs'
    SECRET_NAME = 'ragbot/openai-api-key'
    
    # Application Settings
    DEBUG = False
    ALLOW_PDF_UPLOAD = True
    MAX_PDF_SIZE = 10 * 1024 * 1024  # 10MB
    RATE_LIMIT_PER_HOUR = 20
    
    # RAG Settings
    CHUNK_SIZE = 1000
    CHUNK_OVERLAP = 200
    RETRIEVAL_TOP_K = 4
    
    # OpenAI Settings
    MODEL_NAME = "gpt-3.5-turbo"
    EMBEDDING_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
```

### Systemd Service Configuration

```ini
# /etc/systemd/system/ragbot.service
[Unit]
Description=RAG PDF Chatbot
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/ragbot
Environment="PATH=/opt/ragbot/venv/bin"
Environment="PYTHONPATH=/opt/ragbot"
ExecStart=/opt/ragbot/venv/bin/streamlit run app.py \
  --server.port 8501 \
  --server.address 0.0.0.0 \
  --server.headless true \
  --server.enableCORS false \
  --server.enableXsrfProtection false
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ragbot

[Install]
WantedBy=multi-user.target
```

---

## ✅ Post-Deployment Verification

### 1. Application Health Check

```bash
# Check application URL
curl -I http://$PUBLIC_IP:8501

# Expected response:
# HTTP/1.1 200 OK
# Content-Type: text/html; charset=UTF-8
```

### 2. Functionality Testing

```bash
# Test PDF upload
# 1. Open browser: http://$PUBLIC_IP:8501
# 2. Upload a test PDF
# 3. Verify processing completes

# Test query functionality
# 1. Ask a question about the uploaded PDF
# 2. Verify response quality
# 3. Check source citations
```

### 3. Resource Verification

```bash
# Check EFS mount
df -h | grep efs

# Check disk space
df -h /

# Check memory usage
free -h

# Check CPU usage
top -bn1 | grep "Cpu(s)"
```

### 4. Security Verification

```bash
# Check security group rules
aws ec2 describe-security-groups \
  --group-ids $SECURITY_GROUP_ID \
  --query 'SecurityGroups[0].IpPermissions'

# Verify no public S3 buckets
aws s3api get-bucket-policy-status --bucket $S3_BUCKET

# Check IAM role permissions
aws iam list-attached-role-policies \
  --role-name ragbot-ec2-role
```

### 5. Cost Verification

```bash
# Check Free Tier usage
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "30 days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost

# Set up billing alerts
aws cloudwatch put-metric-alarm \
  --alarm-name ragbot-billing-alert \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --threshold 15 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:YOUR_ACCOUNT:ragbot-alerts
```

---

## 💰 Cost Optimization

### Free Tier Maximization

| Service | Free Tier | Usage | Cost |
|---------|-----------|-------|------|
| EC2 t2.micro | 750 hrs/month | 24/7 operation | $0.00 |
| EBS Storage | 30GB | 20GB used | $0.00 |
| S3 Storage | 5GB | ~3GB for PDFs | $0.00 |
| EFS Storage | 5GB | ~1GB for vectors | $0.00 |
| Data Transfer | 15GB | ~5GB/month | $0.00 |
| CloudWatch | 10 metrics | Basic monitoring | $0.00 |
| **Total AWS** | | | **$0.40/month** |

### OpenAI Cost Control

```python
# app.py - Cost control settings
COST_CONTROL = {
    "max_tokens_per_query": 500,  # Limit response length
    "temperature": 0.3,           # Factual responses
    "model": "gpt-3.5-turbo",     # Cost-effective model
    "rate_limit_per_user": 20,    # Queries per hour
    "enable_caching": True,       # Cache common questions
}
```

### Monthly Cost Estimates

| Usage Level | OpenAI Cost | AWS Cost | **Total** |
|-------------|-------------|----------|-----------|
| Light (50 queries/day) | $6/month | $0.40 | **$6.40** |
| Medium (100 queries/day) | $12/month | $0.40 | **$12.40** |
| Heavy (200 queries/day) | $24/month | $0.40 | **$24.40** |

### Cost Monitoring Commands

```bash
# Daily cost check
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-%d),End=$(date -d "tomorrow" +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost

# OpenAI usage
# Check at: https://platform.openai.com/usage
```

---

## 🔒 Security Best Practices

### 1. IAM Role Configuration

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::ragbot-pdfs/*",
        "arn:aws:s3:::ragbot-pdfs"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:ragbot/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    }
  ]
}
```

### 2. Security Group Rules

```bash
# SSH access - only from your IP
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp \
  --port 22 \
  --cidr "$(curl -s https://checkip.amazonaws.com)/32"

# Application access - public
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp \
  --port 8501 \
  --cidr "0.0.0.0/0"
```

### 3. Secrets Management

```python
# Secure API key retrieval
import boto3
from botocore.exceptions import ClientError

def get_openai_api_key():
    secret_name = "ragbot/openai-api-key"
    region_name = "us-east-1"
    
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )
    
    try:
        response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        return secret['OPENAI_API_KEY']
    except ClientError as e:
        logger.error(f"Error retrieving secret: {e}")
        raise
```

### 4. Application Security

```python
# Rate limiting
from functools import wraps
import time

def rate_limit(max_per_hour=20):
    def decorator(f):
        calls = {}
        @wraps(f)
        def wrapper(*args, **kwargs):
            ip = get_client_ip()
            now = time.time()
            
            if ip not in calls:
                calls[ip] = []
            
            # Remove old calls
            calls[ip] = [t for t in calls[ip] if now - t < 3600]
            
            if len(calls[ip]) >= max_per_hour:
                raise Exception("Rate limit exceeded")
            
            calls[ip].append(now)
            return f(*args, **kwargs)
        return wrapper
    return decorator
```

### 5. Network Security

```bash
# Enable VPC Flow Logs (for auditing)
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids $VPC_ID \
  --traffic-type ALL \
  --log-destination-type s3 \
  --log-destination arn:aws:s3:::ragbot-vpc-logs/

# Enable AWS Shield Standard (DDoS protection)
# Automatically enabled for all AWS resources
```

---

## 📊 Monitoring & Maintenance

### CloudWatch Monitoring Setup

```bash
# Install CloudWatch agent
sudo apt install amazon-cloudwatch-agent -y

# Configure CloudWatch agent
sudo nano /opt/aws/amazon-cloudwatch-agent/etc/config.json
```

```json
{
  "metrics": {
    "namespace": "RAGBot",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_iowait"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["/", "/mnt/efs"]
      },
      "mem": {
        "measurement": ["mem_used_percent"],
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
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
```

### Maintenance Tasks

#### Daily (Automated)
- [ ] Application health checks
- [ ] Log rotation
- [ ] Cost monitoring alerts
- [ ] Backup verification

#### Weekly (Manual)
- [ ] Review CloudWatch metrics
- [ ] Check for security updates
- [ ] Verify OpenAI usage
- [ ] Test application functionality

#### Monthly (Manual)
- [ ] Cost analysis and optimization
- [ ] Security audit
- [ ] Performance review
- [ ] Backup restoration test

### Backup Strategy

```bash
# Automated backup script
#!/bin/bash
# /opt/ragbot/scripts/backup.sh

# Backup vector store to S3
aws s3 sync /mnt/efs/vector_store/ s3://ragbot-backups/vector_store/$(date +%Y%m%d)/

# Backup application logs
aws s3 cp /var/log/ragbot/app.log s3://ragbot-backups/logs/app-$(date +%Y%m%d).log

# Cleanup old backups (keep 7 days)
aws s3 ls s3://ragbot-backups/ | head -n -7 | awk '{print $2}' | xargs -I {} aws s3 rm s3://ragbot-backups/{} --recursive

# Add to crontab
# 0 2 * * * /opt/ragbot/scripts/backup.sh
```

### Troubleshooting Commands

```bash
# Application issues
sudo systemctl status ragbot
sudo journalctl -u ragbot -f
tail -f /var/log/ragbot/app.log

# System issues
top
df -h
free -h
sudo dmesg

# Network issues
curl -I http://localhost:8501
sudo netstat -tlnp
ping 8.8.8.8

# AWS issues
aws ec2 describe-instance-status --instance-ids $INSTANCE_ID
aws logs tail ragbot-application --follow
```

---

## 📞 Support & Resources

### AWS Documentation
- [EC2 User Guide](https://docs.aws.amazon.com/ec2/)
- [EFS User Guide](https://docs.aws.amazon.com/efs/)
- [S3 User Guide](https://docs.aws.amazon.com/s3/)
- [Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)

### Application Documentation
- [Streamlit Documentation](https://docs.streamlit.io/)
- [LangChain Documentation](https://python.langchain.com/)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)

### Community Support
- [AWS Forums](https://forums.aws.amazon.com/)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/aws)
- [GitHub Issues](https://github.com/yourusername/v3_RAGBOT/issues)

---

## ✅ Deployment Checklist

### Pre-Deployment
- [ ] AWS account created with Free Tier
- [ ] OpenAI API key obtained
- [ ] AWS CLI configured
- [ ] PDFs processed locally
- [ ] Application tested locally
- [ ] Deployment package created

### Infrastructure Setup
- [ ] S3 bucket created
- [ ] EFS filesystem created
- [ ] Secrets Manager configured
- [ ] IAM role created
- [ ] Security group configured
- [ ] EC2 instance launched

### Application Deployment
- [ ] Application uploaded to EC2
- [ ] Dependencies installed
- [ ] Environment configured
- [ ] Service started and verified
- [ ] Application accessible publicly

### Post-Deployment
- [ ] Functionality tested
- [ ] Security verified
- [ ] Monitoring configured
- [ ] Backups scheduled
- [ ] Cost alerts set up
- [ ] Documentation updated

---

**Total Deployment Time: ~30 minutes**  
**Expected Monthly Cost: $5-15/month (Free Tier + OpenAI)**  
**Support: 5-10 concurrent users, 200+ PDFs**

For troubleshooting, see [AWS_TROUBLESHOOTING.md](AWS_TROUBLESHOOTING.md)