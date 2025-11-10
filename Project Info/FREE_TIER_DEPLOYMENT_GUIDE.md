# AWS Free Tier Deployment Guide - Complete Step-by-Step

## 🎁 What You Get FREE for 12 Months

AWS Free Tier includes:
- ✅ **750 hours/month** of t2.micro EC2 (enough for 24/7 operation)
- ✅ **30GB** of EBS storage
- ✅ **15GB** of bandwidth/month
- ✅ **100 deployment hours/month** for Lambda
- ✅ **5GB** S3 storage (if needed)

**Perfect for your RAG chatbot demo!**

## 💰 Expected Costs (Free Tier)

| Component | Free Tier | Cost After Free Tier |
|-----------|-----------|---------------------|
| EC2 t2.micro | **$0/month** | ~$8.50/month |
| Storage (20GB) | **$0/month** | ~$2/month |
| Bandwidth (10GB) | **$0/month** | ~$1/month |
| OpenAI API | **~$5-12/month** | Same |
| **Total** | **$5-12/month** | **~$20/month** |

## 📋 Prerequisites

### 1. AWS Account (Required)
- New AWS account gets 12 months Free Tier
- Credit card required (won't be charged for Free Tier usage)
- Sign up: https://aws.amazon.com/free/

### 2. Your Local Computer (For Setup)
- SSH client (built-in on Mac/Linux, PuTTY on Windows)
- Terminal access
- Your RAG chatbot code (we'll build this)

### 3. OpenAI Account
- Get API key from: https://platform.openai.com/api-keys
- Initial $5 credit for new accounts
- Pay-as-you-go after that

## 🚀 Step-by-Step Deployment

### Phase 1: Prepare Locally (Before AWS)

#### Step 1.1: Build and Test Chatbot Locally
```bash
# We'll create this in the next step
# For now, just understand the flow:
# 1. Download code
# 2. Install dependencies
# 3. Process 500 PDFs locally (saves embedding costs!)
# 4. Test app on your computer
# 5. Package for deployment
```

#### Step 1.2: Create Deployment Package
```bash
# After testing locally, create package
cd v3_RAGBOT

# Package everything
tar -czf ragbot-deployment.tar.gz \
    app.py \
    requirements.txt \
    .env \
    data/chroma_db/  # Your pre-built vector database
    
# This file will be uploaded to AWS
```

### Phase 2: AWS Account Setup

#### Step 2.1: Create AWS Account
1. Go to: https://aws.amazon.com/free/
2. Click "Create a Free Account"
3. Fill in details:
   - Email address
   - Password
   - AWS account name
4. Provide contact information
5. Add payment method (credit card)
   - **Don't worry**: Won't be charged for Free Tier services
   - Used for identity verification
6. Verify phone number
7. Choose "Basic Support - Free"
8. Complete sign-up

#### Step 2.2: Initial AWS Console Setup
1. Sign in to AWS Console: https://console.aws.amazon.com/
2. Set your region (top-right corner)
   - **Recommended**: us-east-1 (N. Virginia) - cheapest
   - Alternative: us-west-2 (Oregon)
3. Enable MFA (Multi-Factor Authentication) - Security!

#### Step 2.3: Create Billing Alert (Important!)
```
1. Go to: CloudWatch → Alarms → Billing
2. Click "Create alarm"
3. Set threshold: $10 (or your limit)
4. Add your email
5. Confirm subscription email
```

This will alert you if costs exceed your limit!

### Phase 3: Launch EC2 Instance (Free Tier)

#### Step 3.1: Navigate to EC2
1. AWS Console → Services → EC2
2. Click "Launch Instance"

#### Step 3.2: Configure Instance (Free Tier Eligible)

**Step-by-step form:**

1. **Name your instance**
   - Name: `ragbot-demo` or `pdf-chatbot`

2. **Application and OS Images (AMI)**
   - Click "Ubuntu"
   - Select: **Ubuntu Server 22.04 LTS**
   - Architecture: 64-bit (x86)
   - ✅ Make sure it says "Free tier eligible"

3. **Instance type**
   - Select: **t2.micro**
   - ✅ Says "Free tier eligible"
   - Specs: 1 vCPU, 1 GB RAM
   - Note: Enough for light demo (5-10 concurrent users)

4. **Key pair (login)**
   - Click "Create new key pair"
   - Name: `ragbot-key`
   - Type: RSA
   - Format: 
     - `.pem` for Mac/Linux
     - `.ppk` for Windows (PuTTY)
   - Click "Create key pair"
   - **SAVE THIS FILE** - you can't download it again!
   - Move to safe location:
     ```bash
     mv ~/Downloads/ragbot-key.pem ~/.ssh/
     chmod 400 ~/.ssh/ragbot-key.pem
     ```

5. **Network settings**
   - Click "Edit"
   - VPC: Default (leave as is)
   - Subnet: No preference (leave as is)
   - Auto-assign public IP: **Enable**
   - Firewall (Security groups): **Create security group**
     - Name: `ragbot-sg`
     - Description: `Security group for RAG chatbot`
     - Rules to add:
       
       **Rule 1: SSH**
       - Type: SSH
       - Source: My IP (for security)
       
       **Rule 2: Custom TCP (Streamlit)**
       - Type: Custom TCP
       - Port: 8501
       - Source: Anywhere (0.0.0.0/0) - for public access
       - Description: Streamlit web app

6. **Configure storage**
   - Size: **20 GB** (Free Tier provides 30 GB)
   - Volume Type: gp3 (General Purpose SSD)
   - ✅ "Free tier eligible"
   - Encryption: Not required for demo

7. **Advanced details**
   - Leave all as default
   - No changes needed

8. **Review and launch**
   - Check "Number of instances": 1
   - Review all settings
   - Click "Launch instance"

#### Step 3.3: Wait for Instance to Start
- Status: "Pending" → "Running" (30-60 seconds)
- Note down your **Public IPv4 address** (e.g., 54.123.45.67)

### Phase 4: Connect to Your Instance

#### Option A: Mac/Linux Users

```bash
# 1. Set correct permissions on key
chmod 400 ~/.ssh/ragbot-key.pem

# 2. Connect via SSH (replace with YOUR IP)
ssh -i ~/.ssh/ragbot-key.pem ubuntu@54.123.45.67

# You should see:
# Welcome to Ubuntu 22.04.3 LTS...
```

#### Option B: Windows Users (PuTTY)

1. Download PuTTY: https://www.putty.org/
2. Open PuTTY
3. Configuration:
   - Host Name: `ubuntu@54.123.45.67` (your IP)
   - Port: 22
   - Connection type: SSH
4. SSH → Auth → Credentials:
   - Browse to your `.ppk` key file
5. Click "Open"
6. Accept security alert (first time only)

#### Option C: AWS Console (Easiest)

1. Go to EC2 Dashboard
2. Select your instance
3. Click "Connect" button
4. Choose "EC2 Instance Connect"
5. Click "Connect"
6. Opens terminal in browser!

### Phase 5: Setup Application on EC2

#### Step 5.1: Update System
```bash
# Once connected to EC2, run:
sudo apt update
sudo apt upgrade -y
```

#### Step 5.2: Install Python and Dependencies
```bash
# Install Python 3.10
sudo apt install python3.10 python3-pip python3-venv -y

# Verify installation
python3 --version  # Should show Python 3.10.x
pip3 --version
```

#### Step 5.3: Install Git (to clone your repo)
```bash
sudo apt install git -y
```

#### Step 5.4: Upload Your Application

**Option A: Using SCP (from your computer)**
```bash
# On your LOCAL computer (not EC2)
scp -i ~/.ssh/ragbot-key.pem ragbot-deployment.tar.gz ubuntu@54.123.45.67:~/

# This uploads your package to EC2
```

**Option B: Clone from GitHub (recommended)**
```bash
# On EC2 instance
git clone https://github.com/yourusername/v3_RAGBOT.git
cd v3_RAGBOT
```

**Option C: Manual file creation**
```bash
# If you uploaded tar.gz
cd ~
tar -xzf ragbot-deployment.tar.gz
cd v3_RAGBOT
```

#### Step 5.5: Create Virtual Environment
```bash
# Create venv
python3 -m venv venv

# Activate it
source venv/bin/activate

# Your prompt should change to: (venv) ubuntu@...
```

#### Step 5.6: Install Python Dependencies
```bash
# Install from requirements.txt
pip install -r requirements.txt

# This will take 5-10 minutes
# Downloads sentence-transformers model (~300MB)
```

#### Step 5.7: Configure Environment Variables
```bash
# Create .env file
nano .env

# Add this content:
OPENAI_API_KEY=your_actual_api_key_here

# Save: Ctrl+O, Enter, Ctrl+X
```

#### Step 5.8: Test the Application
```bash
# Quick test
streamlit run app.py --server.port 8501 --server.address 0.0.0.0

# You should see:
# You can now view your Streamlit app in your browser.
# Network URL: http://172.31.x.x:8501
# External URL: http://54.123.45.67:8501
```

#### Step 5.9: Access Your App
Open browser and go to:
```
http://54.123.45.67:8501
```
(Replace with YOUR EC2 Public IP)

**If it works:** 🎉 Success! You're running on AWS!

**If it doesn't work:**
- Check Security Group allows port 8501
- Check firewall: `sudo ufw status` (should be inactive)
- Check app is running: Are there errors in terminal?

### Phase 6: Keep App Running 24/7

When you close terminal, app stops. Let's fix that:

#### Option A: Using Screen (Simple)
```bash
# Install screen
sudo apt install screen -y

# Start a named screen session
screen -S ragbot

# Run your app
source venv/bin/activate
streamlit run app.py --server.port 8501 --server.address 0.0.0.0

# Detach from screen: Press Ctrl+A, then D
# App keeps running!

# To reattach later:
screen -r ragbot

# To list all screens:
screen -ls
```

#### Option B: Using Systemd (Professional)
```bash
# Create service file
sudo nano /etc/systemd/system/ragbot.service
```

Add this content:
```ini
[Unit]
Description=RAG Chatbot Application
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/v3_RAGBOT
Environment="PATH=/home/ubuntu/v3_RAGBOT/venv/bin"
ExecStart=/home/ubuntu/v3_RAGBOT/venv/bin/streamlit run app.py --server.port 8501 --server.address 0.0.0.0
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Save and enable:
```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service (start on boot)
sudo systemctl enable ragbot

# Start service
sudo systemctl start ragbot

# Check status
sudo systemctl status ragbot

# View logs
sudo journalctl -u ragbot -f
```

Control commands:
```bash
sudo systemctl stop ragbot    # Stop
sudo systemctl start ragbot   # Start
sudo systemctl restart ragbot # Restart
```

### Phase 7: Monitor Costs

#### Enable Cost Monitoring
```bash
# In AWS Console:
1. Go to: Billing Dashboard
2. Click "Budgets"
3. Create budget:
   - Type: Cost budget
   - Name: "RAG Chatbot Monthly"
   - Period: Monthly
   - Amount: $20 (or your limit)
   - Alert: 80% and 100%
   - Email: your email
```

#### Track OpenAI Costs
```bash
# Check at: https://platform.openai.com/usage
# Set monthly limits:
1. Go to Settings → Limits
2. Set soft limit: $10
3. Set hard limit: $15
```

#### Check Current Month Usage
```python
# Add to app.py (optional)
import os
from openai import OpenAI

client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))

# This will show usage in OpenAI dashboard
# No code needed, just check dashboard regularly
```

## 🔒 Security Best Practices

### 1. Secure Your SSH Key
```bash
# On your local computer
chmod 400 ~/.ssh/ragbot-key.pem

# Never share this file!
# Never commit to Git!
```

### 2. Limit SSH Access
```bash
# Edit Security Group to allow SSH only from your IP
# In AWS Console:
# EC2 → Security Groups → ragbot-sg → Edit inbound rules
# SSH rule → Source → My IP
```

### 3. Keep System Updated
```bash
# Run weekly
sudo apt update && sudo apt upgrade -y
```

### 4. Use Strong OpenAI Limits
```bash
# In OpenAI Platform:
# Set monthly budget limit: $15
# Set usage alerts: 80%, 100%
# Enable rate limiting
```

### 5. Implement Rate Limiting in App
```python
# We'll add this to app.py
# Limits queries per user/IP
```

## 🚨 Troubleshooting Guide

### Problem: Can't connect to EC2
**Solution:**
```bash
# 1. Check instance is running
# In EC2 Console: Instance state should be "Running"

# 2. Check Security Group
# Port 22 should be open from your IP

# 3. Verify key file permissions
chmod 400 ~/.ssh/ragbot-key.pem

# 4. Use correct username
ssh -i ~/.ssh/ragbot-key.pem ubuntu@YOUR_IP
# For Ubuntu AMI, username is "ubuntu"
```

### Problem: Can't access Streamlit (port 8501)
**Solution:**
```bash
# 1. Check Security Group
# EC2 → Security Groups → Inbound rules
# Custom TCP port 8501 should be 0.0.0.0/0

# 2. Check app is running
sudo systemctl status ragbot
# OR
ps aux | grep streamlit

# 3. Check firewall
sudo ufw status
# Should be "inactive" or allow 8501

# 4. Check from EC2 itself
curl http://localhost:8501
# Should return HTML
```

### Problem: App crashes or errors
**Solution:**
```bash
# 1. Check logs
sudo journalctl -u ragbot -f

# 2. Run manually to see errors
cd /home/ubuntu/v3_RAGBOT
source venv/bin/activate
streamlit run app.py

# 3. Check dependencies
pip list | grep -E "streamlit|langchain|chromadb"

# 4. Check .env file
cat .env
# Make sure OPENAI_API_KEY is set
```

### Problem: High costs
**Solution:**
```bash
# 1. Check AWS usage
# Billing Dashboard → Cost Explorer

# 2. Free Tier usage
# Billing → Free Tier

# 3. Stop instance when not needed
# EC2 → Actions → Instance State → Stop
# (You can start later, IP will change)

# 4. Check OpenAI usage
# https://platform.openai.com/usage

# 5. Implement query limits in app
```

### Problem: Out of memory
**Solution:**
```bash
# t2.micro has only 1GB RAM
# If app crashes:

# 1. Check memory usage
free -h
df -h

# 2. Create swap file (emergency)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 3. Consider upgrading to t3.small ($15/month)
# More RAM = better performance
```

## 📊 Monitoring Your Deployment

### Check App Health
```bash
# Is app running?
sudo systemctl status ragbot

# CPU/Memory usage
top
# Press 'q' to quit

# Disk usage
df -h

# Last 100 log lines
sudo journalctl -u ragbot -n 100
```

### Check Costs Daily
```bash
# AWS Console:
# 1. Billing Dashboard
# 2. Cost Explorer
# 3. Free Tier usage tracker

# OpenAI Platform:
# 1. Usage page
# 2. Check daily spend
```

## 🎯 Next Steps After Deployment

### 1. Test Your App
- Upload a sample PDF
- Ask questions
- Verify responses
- Check source citations

### 2. Share with Users
- Share your URL: `http://YOUR_IP:8501`
- Get feedback
- Monitor usage

### 3. Optional Enhancements
- Add user authentication
- Implement query limits
- Add analytics
- Custom domain name
- SSL certificate

### 4. Scale If Needed
- Upgrade to t3.small ($15/month)
- Add load balancer
- Multiple instances
- Auto-scaling

## 💡 Cost Optimization Tips

### Minimize Costs
1. **Process PDFs locally** - Don't use EC2 for this
2. **Use Free Tier** - 750 hours/month = 24/7
3. **Stop when not needed** - For development
4. **Set billing alerts** - $5, $10, $15
5. **Limit OpenAI usage** - Set hard limits
6. **Cache responses** - For common questions

### When to Upgrade
- More than 10 concurrent users → t3.small
- More than 50 users → t3.medium
- Need high availability → Multiple instances
- Professional demo → Add SSL + domain

## 📝 Deployment Checklist

### Pre-Deployment
- [ ] Create AWS account
- [ ] Get OpenAI API key
- [ ] Build and test app locally
- [ ] Process all PDFs locally
- [ ] Create deployment package

### Deployment
- [ ] Launch EC2 instance (t2.micro)
- [ ] Configure Security Group
- [ ] Connect via SSH
- [ ] Install dependencies
- [ ] Upload application
- [ ] Configure .env
- [ ] Test app
- [ ] Setup systemd service

### Post-Deployment
- [ ] Set billing alerts
- [ ] Share URL with users
- [ ] Monitor costs daily
- [ ] Get user feedback
- [ ] Plan scaling if needed

## 🎉 Success Criteria

Your deployment is successful when:
- ✅ App runs 24/7 without intervention
- ✅ Users can access via `http://YOUR_IP:8501`
- ✅ Queries return accurate answers
- ✅ Costs stay under $15/month
- ✅ No downtime or crashes

## 📞 Getting Help

### AWS Support
- Free Tier: https://aws.amazon.com/free/
- Documentation: https://docs.aws.amazon.com/
- Forums: https://repost.aws/

### Community
- Stack Overflow: Tag with `aws-ec2`, `streamlit`
- Reddit: r/aws, r/learnprogramming
- Discord: Various AI/ML communities

---

**Ready to deploy? Once you have the app code, follow this guide step-by-step!**