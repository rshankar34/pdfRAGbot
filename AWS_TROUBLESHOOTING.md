# AWS Deployment Troubleshooting Guide

Comprehensive guide for diagnosing and resolving common issues with RAG PDF Chatbot AWS deployment.

## 📋 Table of Contents

1. [Deployment Issues](#deployment-issues)
2. [Application Issues](#application-issues)
3. [Performance Issues](#performance-issues)
4. [Cost Issues](#cost-issues)
5. [Security Issues](#security-issues)
6. [Data Issues](#data-issues)
7. [Quick Fixes](#quick-fixes)

---

## 🚀 Deployment Issues

### Issue 1: AWS CLI Not Configured

**Symptoms:**
```
Error: AWS credentials not configured
Unable to locate credentials
```

**Solutions:**

```bash
# Solution 1: Configure AWS CLI
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter region: us-east-1
# Output format: json

# Solution 2: Set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"

# Solution 3: Use AWS profile
aws configure --profile ragbot
export AWS_PROFILE=ragbot

# Verify configuration
aws sts get-caller-identity
```

**Prevention:**
- Store AWS credentials in `~/.aws/credentials`
- Use IAM roles instead of access keys when possible
- Rotate access keys regularly

---

### Issue 2: Insufficient IAM Permissions

**Symptoms:**
```
Error: AccessDenied
User is not authorized to perform: ec2:RunInstances
```

**Solutions:**

```bash
# Attach necessary policies to your IAM user/role
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonElasticFileSystemFullAccess

aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

# Create custom policy for least privilege
cat > ragbot-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:RunInstances",
                "ec2:DescribeInstances",
                "ec2:TerminateInstances",
                "ec2:CreateSecurityGroup",
                "ec2:AuthorizeSecurityGroupIngress"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:CreateBucket",
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::ragbot-*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:CreateFileSystem",
                "elasticfilesystem:CreateMountTarget"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:CreateSecret",
                "secretsmanager:GetSecretValue"
            ],
            "Resource": "arn:aws:secretsmanager:*:*:secret:ragbot/*"
        }
    ]
}
EOF

aws iam create-policy \
  --policy-name RAGBotDeploymentPolicy \
  --policy-document file://ragbot-policy.json

aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT:policy/RAGBotDeploymentPolicy
```

---

### Issue 3: Resource Limit Exceeded

**Symptoms:**
```
Error: You have requested more instances (1) than your current instance limit of 0 allows
Error: VPC resource limit exceeded
```

**Solutions:**

```bash
# Check current limits
aws ec2 describe-account-attributes --attribute-names max-instances

# Request limit increase
# 1. Go to AWS Console → Service Quotas
# 2. Search for "Running On-Demand t2.micro instances"
# 3. Click "Request quota increase"
# 4. Enter new limit (e.g., 5)
# 5. Submit request (usually approved within minutes)

# Alternative: Use different region
export AWS_DEFAULT_REGION=us-west-2  # Oregon
# or
export AWS_DEFAULT_REGION=eu-west-1  # Ireland

# Check Free Tier eligibility in new region
aws ec2 describe-instances --region us-west-2
```

**Prevention:**
- Monitor usage with AWS Cost Explorer
- Set up billing alerts
- Use AWS Free Tier dashboard

---

### Issue 4: Security Group Configuration Errors

**Symptoms:**
```
Error: Unable to connect to instance
Connection timeout on port 8501
```

**Solutions:**

```bash
# Check security group rules
aws ec2 describe-security-groups \
  --group-ids sg-xxxxxxxx

# Add missing rules
# Allow Streamlit port (8501)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp \
  --port 8501 \
  --cidr "0.0.0.0/0"

# Allow SSH (port 22) from your IP
CURRENT_IP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr "${CURRENT_IP}/32"

# Verify rules
aws ec2 describe-security-groups \
  --group-ids sg-xxxxxxxx \
  --query 'SecurityGroups[0].IpPermissions'

# Test connectivity
telnet YOUR_EC2_IP 8501
# or
nc -vz YOUR_EC2_IP 8501
```

---

### Issue 5: User Data Script Failures

**Symptoms:**
```
Error: Application not starting
User data script didn't complete
```

**Solutions:**

```bash
# Check user data logs
sudo cat /var/log/cloud-init-output.log

# Check system logs
sudo journalctl -u cloud-init

# Common issues and fixes:

# 1. Permission issues
sudo chown -R ubuntu:ubuntu /opt/ragbot

# 2. Missing dependencies
cd /opt/ragbot
source venv/bin/activate
pip install -r requirements.txt

# 3. EFS mount issues
sudo mount -t efs fs-xxxxxxxx:/ /mnt/efs
# Check if mount succeeded
df -h | grep efs

# 4. Service start issues
sudo systemctl daemon-reload
sudo systemctl enable ragbot
sudo systemctl start ragbot
sudo systemctl status ragbot

# 5. Manual service test
cd /opt/ragbot
source venv/bin/activate
streamlit run app.py --server.port 8501 --server.address 0.0.0.0
```

---

## 💻 Application Issues

### Issue 6: Python Environment Problems

**Symptoms:**
```
Error: ModuleNotFoundError: No module named 'streamlit'
Error: ImportError: cannot import name 'load_dotenv'
```

**Solutions:**

```bash
# On EC2 instance:

# 1. Create virtual environment
cd /opt/ragbot
python3 -m venv venv
source venv/bin/activate

# 2. Install dependencies
pip install --upgrade pip
pip install -r requirements.txt

# 3. Verify installation
pip list | grep -E "streamlit|langchain|openai"

# 4. Test imports
python3 -c "import streamlit; print('Streamlit OK')"
python3 -c "from dotenv import load_dotenv; print('dotenv OK')"
python3 -c "import openai; print('OpenAI OK')"

# 5. Fix specific missing packages
pip install streamlit==1.29.0
pip install python-dotenv==1.0.0
pip install openai==1.3.7

# 6. Reinstall if corrupted
pip uninstall -y streamlit langchain openai
pip install --no-cache-dir -r requirements.txt
```

**For macOS/Homebrew users:**
```bash
# Use --break-system-packages flag
pip3 install --break-system-packages python-dotenv==1.0.0

# Or use virtual environment
python3 -m venv venv
source venv/bin/activate
pip install python-dotenv==1.0.0
```

---

### Issue 7: OpenAI API Key Issues

**Symptoms:**
```
Error: OpenAI API key not found
Error: Invalid API key
Error: Rate limit exceeded
```

**Solutions:**

```bash
# 1. Verify API key is set
echo $OPENAI_API_KEY

# 2. Check .env file
cat /opt/ragbot/.env
# Should contain: OPENAI_API_KEY=sk-...

# 3. Test API key directly
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"

# 4. Check API key validity
python3 -c "
import openai
openai.api_key = '$OPENAI_API_KEY'
try:
    openai.Model.list()
    print('API key is valid')
except Exception as e:
    print(f'API key error: {e}')
"

# 5. Check OpenAI usage and limits
# Visit: https://platform.openai.com/usage

# 6. Rotate API key if compromised
# Generate new key at: https://platform.openai.com/api-keys
# Update in Secrets Manager:
aws secretsmanager update-secret \
  --secret-id ragbot/openai-api-key \
  --secret-string '{"OPENAI_API_KEY":"sk-new-key"}'

# 7. Restart application to use new key
sudo systemctl restart ragbot
```

---

### Issue 8: Vector Store Loading Errors

**Symptoms:**
```
Error: Cannot load vector store
Error: FAISS index not found
Error: Vector store corruption
```

**Solutions:**

```bash
# 1. Check vector store files
ls -la /mnt/efs/vector_store/

# Should show:
# index.faiss
# index.pkl

# 2. Check file permissions
sudo chown -R ubuntu:ubuntu /mnt/efs/vector_store
sudo chmod -R 644 /mnt/efs/vector_store/*

# 3. Verify vector store integrity
python3 -c "
from langchain_community.vectorstores import FAISS
from langchain_community.embeddings import HuggingFaceEmbeddings

embeddings = HuggingFaceEmbeddings(model_name='sentence-transformers/all-MiniLM-L6-v2')
try:
    vector_store = FAISS.load_local('/mnt/efs/vector_store', embeddings, allow_dangerous_deserialization=True)
    print(f'Vector store loaded successfully. Documents: {vector_store.index.ntotal}')
except Exception as e:
    print(f'Error loading vector store: {e}')
"

# 4. Rebuild vector store if corrupted
# Backup corrupted store
sudo mv /mnt/efs/vector_store /mnt/efs/vector_store_backup_$(date +%Y%m%d)

# Reprocess PDFs
cd /opt/ragbot
source venv/bin/activate
python scripts/rebuild-vector-store.py

# 5. Restore from backup if available
aws s3 cp s3://ragbot-backups/vector_store/latest/ /mnt/efs/vector_store/ --recursive

# 6. Check disk space
df -h /mnt/efs
# EFS should have at least 1GB free
```

---

### Issue 9: Streamlit Application Crashes

**Symptoms:**
```
Error: Streamlit server crashed
Error: Port 8501 already in use
Error: Application timeout
```

**Solutions:**

```bash
# 1. Check if port is in use
sudo netstat -tlnp | grep 8501

# 2. Kill process using the port
sudo fuser -k 8501/tcp

# 3. Restart Streamlit service
sudo systemctl restart ragbot

# 4. Check Streamlit logs
sudo journalctl -u ragbot -f

# 5. Test Streamlit manually
cd /opt/ragbot
source venv/bin/activate
streamlit run app.py --server.port 8501 --server.address 0.0.0.0

# 6. Increase timeout settings
# Edit /etc/systemd/system/ragbot.service
sudo nano /etc/systemd/system/ragbot.service
# Add:
# TimeoutStartSec=300
# TimeoutStopSec=300

sudo systemctl daemon-reload
sudo systemctl restart ragbot

# 7. Check memory usage
free -h
# If memory is low, add swap
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

### Issue 10: PDF Processing Failures

**Symptoms:**
```
Error: Failed to process PDF
Error: PDF parsing error
Error: File too large
```

**Solutions:**

```bash
# 1. Check PDF file
file /path/to/document.pdf
# Should show: PDF document, version 1.x

# 2. Check PDF size
ls -lh /path/to/document.pdf
# Should be less than 10MB

# 3. Test PDF processing manually
cd /opt/ragbot
source venv/bin/activate
python3 -c "
from langchain_community.document_loaders import PyPDFLoader
try:
    loader = PyPDFLoader('/path/to/document.pdf')
    docs = loader.load()
    print(f'Loaded {len(docs)} pages')
except Exception as e:
    print(f'Error: {e}')
"

# 4. Install PDF repair tools
sudo apt install poppler-utils -y
pdfinfo /path/to/document.pdf

# 5. Fix corrupted PDFs
sudo apt install qpdf -y
qpdf --repair-file /path/to/corrupted.pdf /path/to/fixed.pdf

# 6. Increase file size limits
# Edit app.py
MAX_PDF_SIZE = 20 * 1024 * 1024  # 20MB

# 7. Process PDFs in smaller batches
# Use script to process one PDF at a time
python scripts/process-single-pdf.py /path/to/document.pdf
```

---

## ⚡ Performance Issues

### Issue 11: Slow Query Response Times

**Symptoms:**
- Queries take >10 seconds
- Application feels sluggish
- Timeout errors

**Solutions:**

```bash
# 1. Check system resources
top
# Look for:
# - CPU usage > 80%
# - Memory usage > 90%
# - High load average

# 2. Check vector store size
du -sh /mnt/efs/vector_store/
# Should be < 2GB for 500 PDFs

# 3. Optimize retrieval parameters
# Edit config/production.py
RETRIEVAL_TOP_K = 3  # Reduced from 4
CHUNK_SIZE = 800     # Reduced from 1000

# 4. Enable response caching
# Add to app.py
from functools import lru_cache

@lru_cache(maxsize=100)
def get_cached_answer(question):
    return qa_chain.invoke({"query": question})

# 5. Upgrade instance type if needed
# t2.micro → t3.small (2GB RAM)
aws ec2 modify-instance-attribute \
  --instance-id i-xxxxxxxx \
  --instance-type t3.small

# 6. Monitor OpenAI response times
# Add logging in app.py
import time
start = time.time()
response = qa_chain.invoke({"query": question})
duration = time.time() - start
logger.info(f"Query took {duration:.2f} seconds")
```

---

### Issue 12: High Memory Usage

**Symptoms:**
- System runs out of memory
- Application crashes with OOM
- Swap usage high

**Solutions:**

```bash
# 1. Check memory usage
free -h
vmstat 1 5

# 2. Identify memory hogs
ps aux --sort=-%mem | head -10

# 3. Reduce embedding model memory
# Edit app.py
embeddings = HuggingFaceEmbeddings(
    model_name="sentence-transformers/all-MiniLM-L6-v2",
    model_kwargs={
        'device': 'cpu',
        'cache_folder': '/tmp/models'  # Clear cache on reboot
    }
)

# 4. Limit concurrent users
# Add to Streamlit config
# ~/.streamlit/config.toml
[server]
maxUploadSize = 10
maxMessageSize = 10

# 5. Add swap space (emergency)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# 6. Restart services to free memory
sudo systemctl restart ragbot
sudo sync && sudo sysctl -w vm.drop_caches=3

# 7. Upgrade instance (recommended)
# t2.micro (1GB) → t3.small (2GB)
# Costs ~$15/month instead of $8.50
```

---

### Issue 13: EFS Performance Issues

**Symptoms:**
- Slow vector store loading
- High EFS latency
- Mount timeouts

**Solutions:**

```bash
# 1. Check EFS mount status
df -h | grep efs
mount | grep efs

# 2. Check EFS metrics in CloudWatch
# AWS Console → EFS → File systems → Monitoring

# 3. Optimize EFS performance
# Switch to General Purpose performance mode
# Already default for t2.micro setup

# 4. Check burst credits
# AWS Console → EFS → Burst credit balance
# If low, consider:
# - Using EFS Provisioned Throughput
# - Or upgrade to t3 instance (higher baseline)

# 5. Remount EFS with options
sudo umount /mnt/efs
sudo mount -t efs fs-xxxxxxxx:/ /mnt/efs -o tls,iam

# 6. Move vector store to EBS (alternative)
# If EFS is too slow, use instance storage
# But you'll lose data on termination
sudo mv /mnt/efs/vector_store /opt/ragbot/data/
# Update VECTOR_STORE_PATH in config
```

---

### Issue 14: Network Latency

**Symptoms:**
- Slow page loads
- Connection timeouts
- High latency from certain regions

**Solutions:**

```bash
# 1. Check network connectivity
ping YOUR_EC2_IP
traceroute YOUR_EC2_IP

# 2. Test from different locations
# Use online tools like:
# - https://www.dotcom-tools.com/ping-test
# - https://www.keycdn.com/ping

# 3. Enable CloudFront CDN
# AWS Console → CloudFront → Create distribution
# Origin: YOUR_EC2_IP:8501
# This adds ~$0.10/GB but improves global performance

# 4. Choose optimal region
# For users in:
# - Americas: us-east-1 (Virginia)
# - Europe: eu-west-1 (Ireland)
# - Asia: ap-southeast-1 (Singapore)

# 5. Use AWS Global Accelerator
# For production deployments with global users
# Adds ~$20/month but provides static IPs

# 6. Optimize Streamlit settings
# In app.py or config
st.set_page_config(
    page_title="RAG PDF Chatbot",
    layout="wide",
    initial_sidebar_state="collapsed"  # Faster load
)
```

---

## 💰 Cost Issues

### Issue 15: Unexpected AWS Charges

**Symptoms:**
- Bill higher than expected
- Free Tier exceeded
- Unknown charges

**Solutions:**

```bash
# 1. Check current month costs
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost

# 2. Identify cost drivers
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --group-by Type=DIMENSION,Key=SERVICE \
  --metrics BlendedCost

# 3. Check Free Tier usage
# AWS Console → Billing → Free Tier

# 4. Set up billing alerts
aws cloudwatch put-metric-alarm \
  --alarm-name ragbot-billing-alert \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --threshold 20 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:YOUR_ACCOUNT:ragbot-alerts

# 5. Common cost surprises:
# - Elastic IP not attached to running instance: $0.005/hr
# - EBS snapshots: $0.05/GB-month
# - Data transfer out: $0.09/GB after Free Tier
# - CloudWatch logs: $0.50/GB after Free Tier

# 6. Immediate cost reduction:
# - Stop unused instances
aws ec2 stop-instances --instance-ids i-xxxxxxxx

# - Delete unused EBS volumes
aws ec2 describe-volumes --filters Name=status,Values=available
aws ec2 delete-volume --volume-id vol-xxxxxxxx

# - Delete old CloudWatch logs
aws logs delete-log-group --log-group-name ragbot-application
```

---

### Issue 16: High OpenAI Costs

**Symptoms:**
- OpenAI bill higher than expected
- API usage spikes
- Unexpected token consumption

**Solutions:**

```bash
# 1. Check OpenAI usage dashboard
# Visit: https://platform.openai.com/usage

# 2. Set OpenAI usage limits
# Platform → Limits → Set soft/hard limits
# Recommended: $10 soft, $15 hard limit

# 3. Implement query logging
# Add to app.py
import logging
logger = logging.getLogger(__name__)

def log_query(question, tokens_used):
    logger.info(f"Query: {question[:50]}... | Tokens: {tokens_used}")

# 4. Add rate limiting
# Add to app.py
from functools import wraps
import time

def rate_limit(max_per_hour=20):
    def decorator(f):
        calls = {}
        @wraps(f)
        def wrapper(*args, **kwargs):
            # Simple IP-based rate limiting
            return f(*args, **kwargs)
        return wrapper
    return decorator

# 5. Cache common questions
# Add to app.py
from functools import lru_cache

@lru_cache(maxsize=100)
def get_cached_answer(question):
    return qa_chain.invoke({"query": question})

# 6. Optimize prompts to reduce tokens
# Use shorter, more direct prompts
# Remove unnecessary context

# 7. Switch to cheaper model for simple queries
# Use GPT-3.5-turbo instead of GPT-4
# Already default in our setup

# 8. Monitor per-user usage
# Add user tracking
# Set daily limits per IP address
```

---

### Issue 17: Free Tier Exhaustion

**Symptoms:**
- AWS charges appearing
- Free Tier usage at 100%
- Services stopped working

**Solutions:**

```bash
# 1. Check Free Tier usage
# AWS Console → Billing → Free Tier

# 2. Common Free Tier limits:
# - EC2: 750 hours/month (t2.micro only)
# - S3: 5GB storage + 20,000 GET requests
# - EFS: 5GB storage
# - Data Transfer: 15GB out

# 3. If EC2 hours exceeded:
# - Stop instance when not needed
aws ec2 stop-instances --instance-ids i-xxxxxxxx

# - Use spot instances (70% cheaper)
aws ec2 request-spot-instances \
  --spot-price "0.005" \
  --instance-count 1 \
  --type "one-time" \
  --launch-specification file://spot-spec.json

# 4. If S3 storage exceeded:
# - Clean up old PDFs
aws s3 ls s3://ragbot-pdfs/
aws s3 rm s3://ragbot-pdfs/old-files/

# - Enable lifecycle policy
aws s3api put-bucket-lifecycle-configuration \
  --bucket ragbot-pdfs \
  --lifecycle-configuration file://lifecycle.json

# 5. If EFS storage exceeded:
# - Clean up vector store
# - Compress or archive old data
# - Move to S3 (cheaper for infrequent access)

# 6. Create new AWS account for additional Free Tier
# (Only if current account is >12 months old)

# 7. Budget for post-Free Tier costs
# Typical costs after Free Tier:
# - EC2 t2.micro: $8.50/month
# - EBS 20GB: $2/month
# - EFS 1GB: $3/month
# - Total: ~$14/month + OpenAI
```

---

## 🔒 Security Issues

### Issue 18: SSH Access Denied

**Symptoms:**
```
Error: Permission denied (publickey)
Error: Connection timed out
```

**Solutions:**

```bash
# 1. Check key file permissions
chmod 400 ~/.ssh/your-key.pem

# 2. Verify correct username
# Ubuntu AMI: ubuntu@YOUR_IP
# Amazon Linux: ec2-user@YOUR_IP

# 3. Check Security Group
aws ec2 describe-security-groups \
  --group-ids sg-xxxxxxxx \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'

# 4. Get instance system logs
aws ec2 get-console-output --instance-id i-xxxxxxxx

# 5. Use EC2 Instance Connect (alternative)
aws ec2-instance-connect ssh \
  --instance-id i-xxxxxxxx \
  --os-user ubuntu

# 6. Check key pair
aws ec2 describe-key-pairs --key-names your-key-pair

# 7. If key is lost:
# - Stop instance
aws ec2 stop-instances --instance-ids i-xxxxxxxx

# - Create new AMI
# - Launch new instance with new key pair
# - Or mount root volume to another instance to recover data
```

---

### Issue 19: OpenAI API Key Exposure

**Symptoms:**
- API key found in logs
- Key committed to Git
- Unauthorized API usage

**Solutions:**

```bash
# 1. Immediately rotate compromised key
# Go to: https://platform.openai.com/api-keys
# Delete old key, create new one

# 2. Update Secrets Manager
aws secretsmanager update-secret \
  --secret-id ragbot/openai-api-key \
  --secret-string '{"OPENAI_API_KEY":"sk-new-key"}'

# 3. Restart application
sudo systemctl restart ragbot

# 4. Check for key in logs
grep -r "sk-" /var/log/
grep -r "OPENAI_API_KEY" /var/log/

# 5. Clean git history if key was committed
# Install git-filter-repo
pip install git-filter-repo

# Remove key from history
git filter-repo --replace-text <(echo "sk-old-key==>sk-REDACTED")

# Force push (be careful!)
git push origin --force --all

# 6. Enable AWS Secrets Manager rotation
aws secretsmanager rotate-secret \
  --secret-id ragbot/openai-api-key \
  --lambda-arn arn:aws:lambda:us-east-1:YOUR_ACCOUNT:function:secrets-rotation

# 7. Audit API usage
# Check OpenAI dashboard for unusual patterns
# Look for:
# - Requests from unexpected IPs
# - Unusual time patterns
# - High token usage
```

---

### Issue 20: Unauthorized Access Attempts

**Symptoms:**
- SSH login attempts in logs
- Unusual traffic patterns
- Security group alerts

**Solutions:**

```bash
# 1. Check SSH logs
sudo grep "Failed password" /var/log/auth.log
sudo grep "Accepted password" /var/log/auth.log

# 2. Check for brute force attacks
sudo grep "Failed" /var/log/auth.log | wc -l
# If > 100 attempts, likely under attack

# 3. Install fail2ban
sudo apt install fail2ban -y

# Configure for SSH
sudo nano /etc/fail2ban/jail.local
# Add:
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# 4. Restrict Security Group further
# Instead of 0.0.0.0/0 for port 8501, use specific IPs
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp \
  --port 8501 \
  --cidr "203.0.113.0/24"  # Your office IP range

# 5. Enable AWS GuardDuty
aws guardduty create-detector --enable

# 6. Review CloudTrail logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AuthorizeSecurityGroupIngress

# 7. Implement WAF (Web Application Firewall)
# For production deployments
aws wafv2 create-web-acl \
  --name ragbot-waf \
  --scope CLOUDFRONT \
  --default-action Allow={}
```

---

## 📊 Data Issues

### Issue 21: Vector Store Corruption

**Symptoms:**
- Error loading FAISS index
- Search returns no results
- Application crashes on query

**Solutions:**

```bash
# 1. Check vector store files
ls -la /mnt/efs/vector_store/
# Should show:
# - index.faiss (large file, ~500MB)
# - index.pkl (small file, few KB)

# 2. Check file integrity
file /mnt/efs/vector_store/index.faiss
# Should show: data

# 3. Test loading vector store
python3 -c "
from langchain_community.vectorstores import FAISS
from langchain_community.embeddings import HuggingFaceEmbeddings

try:
    embeddings = HuggingFaceEmbeddings(model_name='sentence-transformers/all-MiniLM-L6-v2')
    vector_store = FAISS.load_local('/mnt/efs/vector_store', embeddings, allow_dangerous_deserialization=True)
    print(f'Success! Documents: {vector_store.index.ntotal}')
except Exception as e:
    print(f'Error: {e}')
"

# 4. Restore from backup
# Find latest backup
LATEST_BACKUP=$(aws s3 ls s3://ragbot-backups/vector_store/ | sort | tail -1 | awk '{print $2}')

# Restore
aws s3 cp s3://ragbot-backups/vector_store/${LATEST_BACKUP} /mnt/efs/vector_store/ --recursive

# 5. If no backup, rebuild from PDFs
cd /opt/ragbot
source venv/bin/activate

# Clear corrupted store
rm -rf /mnt/efs/vector_store/*

# Reprocess all PDFs
python scripts/rebuild-vector-store.py

# 6. Prevent future corruption
# Add to backup script
0 2 * * * aws s3 sync /mnt/efs/vector_store/ s3://ragbot-backups/vector_store/$(date +\%Y\%m\%d)/

# 7. Monitor EFS health
# AWS Console → EFS → File systems → Monitoring
# Look for:
# - Client connections
# - Data read/write metrics
# - Burst credit balance
```

---

### Issue 22: PDF Upload Failures

**Symptoms:**
- PDFs won't upload
- Upload timeout
- Processing stuck at 0%

**Solutions:**

```bash
# 1. Check file permissions
ls -la /opt/ragbot/data/pdfs/
sudo chown -R ubuntu:ubuntu /opt/ragbot/data/pdfs/
sudo chmod -R 755 /opt/ragbot/data/pdfs/

# 2. Check disk space
df -h /opt/ragbot/
# Should have at least 1GB free

# 3. Check Streamlit upload limits
# In ~/.streamlit/config.toml
[server]
maxUploadSize = 10  # MB

# 4. Test PDF manually
python3 -c "
from langchain_community.document_loaders import PyPDFLoader
try:
    loader = PyPDFLoader('/path/to/test.pdf')
    docs = loader.load()
    print(f'Successfully loaded {len(docs)} pages')
except Exception as e:
    print(f'Error: {e}')
"

# 5. Check for corrupted PDFs
sudo apt install poppler-utils -y
pdfinfo /path/to/document.pdf
# Should show page count and metadata

# 6. Fix corrupted PDFs
sudo apt install qpdf -y
qpdf --repair-file /path/to/corrupted.pdf /path/to/fixed.pdf

# 7. Increase timeout
# In app.py
import streamlit as st
st.set_option('server.maxUploadTimeout', 300)  # 5 minutes

# 8. Check nginx/proxy timeout (if using ALB)
# Increase proxy_read_timeout and proxy_connect_timeout
```

---

### Issue 23: Missing PDFs After Restart

**Symptoms:**
- PDFs disappear after EC2 restart
- Vector store exists but PDFs missing
- Broken source links

**Solutions:**

```bash
# 1. Check PDF storage location
ls -la /opt/ragbot/data/pdfs/

# 2. If using instance storage (problematic):
# Move PDFs to persistent storage
sudo mkdir -p /mnt/efs/pdfs
sudo mv /opt/ragbot/data/pdfs/* /mnt/efs/pdfs/

# Create symlink
sudo ln -s /mnt/efs/pdfs /opt/ragbot/data/pdfs

# 3. Or store PDFs in S3 (recommended)
# Upload PDFs to S3
aws s3 sync /opt/ragbot/data/pdfs/ s3://ragbot-pdfs/pdfs/

# Update app to read from S3
# Modify PDF_STORAGE_DIR in config

# 4. Update backup script to include PDFs
cat > /opt/ragbot/scripts/backup.sh <<'EOF'
#!/bin/bash
# Backup vector store
aws s3 sync /mnt/efs/vector_store/ s3://ragbot-backups/vector_store/$(date +%Y%m%d)/
# Backup PDFs
aws s3 sync /opt/ragbot/data/pdfs/ s3://ragbot-backups/pdfs/
EOF

# 5. Test persistence
sudo reboot
# After restart, check:
ls /opt/ragbot/data/pdfs/
ls /mnt/efs/vector_store/
```

---

## ⚡ Quick Fixes

### Quick Fix 1: Complete Application Restart

```bash
# SSH into instance
ssh -i ~/.ssh/your-key.pem ubuntu@YOUR_IP

# Full restart sequence
sudo systemctl stop ragbot
sudo fuser -k 8501/tcp 2>/dev/null
sleep 5
sudo systemctl start ragbot
sudo systemctl status ragbot

# Check logs
sudo journalctl -u ragbot -f
```

---

### Quick Fix 2: Clear Cache and Temporary Files

```bash
# Clear Streamlit cache
rm -rf ~/.cache/streamlit/*

# Clear Python cache
find /opt/ragbot -type d -name __pycache__ -exec rm -rf {} +

# Clear temporary files
sudo rm -rf /tmp/*

# Clear system cache
sudo sync && sudo sysctl -w vm.drop_caches=3

# Restart application
sudo systemctl restart ragbot
```

---

### Quick Fix 3: Emergency Backup and Restore

```bash
# Quick backup
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
sudo tar -czf /tmp/ragbot_backup_${BACKUP_DATE}.tar.gz /opt/ragbot /mnt/efs/vector_store
aws s3 cp /tmp/ragbot_backup_${BACKUP_DATE}.tar.gz s3://ragbot-emergency-backups/

# Quick restore (if needed)
aws s3 cp s3://ragbot-emergency-backups/ragbot_backup_${BACKUP_DATE}.tar.gz /tmp/
sudo tar -xzf /tmp/ragbot_backup_${BACKUP_DATE}.tar.gz -C /
sudo systemctl restart ragbot
```

---

### Quick Fix 4: Security Group Reset

```bash
# Remove all rules
aws ec2 revoke-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol -1 \
  --port all \
  --source 0.0.0.0/0

# Add back essential rules
CURRENT_IP=$(curl -s https://checkip.amazonaws.com)

# SSH
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr "${CURRENT_IP}/32"

# Streamlit
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp \
  --port 8501 \
  --cidr "0.0.0.0/0"
```

---

### Quick Fix 5: Log Analysis Commands

```bash
# Application errors
sudo journalctl -u ragbot --since "1 hour ago" | grep -i error

# System errors
sudo dmesg | grep -i error

# SSH login attempts
sudo grep "Failed password" /var/log/auth.log | tail -20

# Recent system changes
sudo tail -100 /var/log/syslog

# Disk space issues
sudo df -h | grep -E "Use%|9[0-9]%|100%"

# Memory issues
sudo grep -i "out of memory" /var/log/syslog
```

---

## 📞 Getting Help

### Before Asking for Help

1. **Gather information:**
   ```bash
   # Create diagnostic report
   ./scripts/diagnostic-report.sh > diagnostic.txt
   ```

2. **Check logs:**
   ```bash
   # Package logs
   tar -czf logs.tar.gz /var/log/ragbot/ /var/log/syslog /var/log/auth.log
   ```

3. **Document the issue:**
   - What were you trying to do?
   - What happened vs. what you expected?
   - Error messages (exact text)
   - Steps to reproduce

### Where to Get Help

1. **GitHub Issues:** Create issue with diagnostic report
2. **AWS Support:** Free for billing questions, paid for technical
3. **Community Forums:** Stack Overflow, Reddit r/aws
4. **Documentation:** Check this guide and AWS docs first

---

**Remember:** Most issues can be resolved by:
1. Checking logs (`sudo journalctl -u ragbot -f`)
2. Verifying configuration (`.env`, security groups)
3. Restarting services (`sudo systemctl restart ragbot`)
4. Checking AWS Console for service health

For issues not covered here, please create a GitHub issue with detailed diagnostic information.