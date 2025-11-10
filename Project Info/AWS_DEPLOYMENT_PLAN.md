# AWS Deployment Plan for Cost-Optimized RAG Chatbot

## ✅ YES, You Can Host It on AWS!

The cost-optimized version (local embeddings) is **IDEAL** for public hosting because:

1. **Pre-process PDFs locally** (one-time, FREE)
2. **Upload vector database to AWS** (one-time)
3. **Users only trigger OpenAI costs** when they ask questions
4. **No per-user embedding costs** - the expensive part is already done!

## 💰 AWS Hosting Cost Estimate

### Option 1: EC2 (Simplest) - **Recommended for Demo**

**Monthly Costs:**
- EC2 t3.medium (4GB RAM): **$30/month** (or $0.0416/hour)
- EBS Storage (20GB): **$2/month**
- OpenAI API (100 queries/day): **$12/month**
- **Total: ~$44/month**

**Free Tier Eligible:**
- t2.micro (1GB RAM): **$0/month for 12 months**
- Limited to light usage (5-10 concurrent users)

### Option 2: ECS Fargate (More Scalable)

**Monthly Costs:**
- Fargate (0.5 vCPU, 2GB): **$25/month**
- EFS Storage (for ChromaDB): **$3/month**
- Application Load Balancer: **$16/month**
- OpenAI API: **$12/month**
- **Total: ~$56/month**

### Option 3: Budget Demo (Free Tier)

**Monthly Costs:**
- EC2 t2.micro (Free Tier): **$0/month** (first year)
- EBS Storage (30GB Free): **$0/month**
- OpenAI API: **$5-12/month**
- **Total: ~$5-12/month**

## 🏗️ AWS Architecture for Public Demo

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
         │  EC2 Instance or     │  ← Streamlit App
         │  ECS Container       │     Running 24/7
         └──────────┬───────────┘
                    │
         ┌──────────┴──────────┐
         │                     │
         ▼                     ▼
┌─────────────────┐   ┌──────────────────┐
│  EBS Volume or  │   │   OpenAI API     │
│  EFS (ChromaDB) │   │  (Pay per query) │
└─────────────────┘   └──────────────────┘
         │
         │ Optional
         ▼
┌─────────────────┐
│   S3 Bucket     │  ← Store original PDFs
│  (Read-only)    │     (for reference)
└─────────────────┘
```

## 🚀 Deployment Strategy

### Phase 1: Local Preparation (One-Time)

**Step 1: Process PDFs Locally**
```bash
# On your local machine
python app.py
# Upload all 500 PDFs through UI
# Wait for processing (50-100 mins)
# All embeddings stored in data/chroma_db/
```

**Step 2: Package for Upload**
```bash
# Create deployment package
tar -czf deployment.tar.gz \
    app.py \
    requirements.txt \
    .env \
    data/chroma_db/  # Pre-built vector database
```

### Phase 2: AWS Setup

**Step 1: Launch EC2 Instance**
```bash
# Choose: Ubuntu 22.04 LTS
# Instance Type: t3.medium (or t2.micro for Free Tier)
# Storage: 20GB EBS (30GB for Free Tier)
# Security Group: Allow ports 22 (SSH), 8501 (Streamlit)
```

**Step 2: Install Dependencies**
```bash
# SSH into EC2
sudo apt update
sudo apt install python3.10 python3-pip -y

# Upload deployment package
scp deployment.tar.gz ubuntu@<EC2-IP>:~/

# Extract and setup
cd ~
tar -xzf deployment.tar.gz
pip install -r requirements.txt
```

**Step 3: Run Application**
```bash
# Run Streamlit
streamlit run app.py --server.port 8501 --server.address 0.0.0.0
```

**Step 4: Keep Running (Background)**
```bash
# Install screen or tmux
sudo apt install screen -y

# Run in background
screen -S ragbot
streamlit run app.py --server.port 8501 --server.address 0.0.0.0
# Press Ctrl+A, then D to detach

# Or use systemd service (production)
```

### Phase 3: Make It Public

**Option A: Direct EC2 Access**
- Access via: `http://<EC2-Public-IP>:8501`
- Free, but IP changes on restart

**Option B: Elastic IP + Domain**
- Allocate Elastic IP: **$0/month** (while attached)
- Point domain from Route 53
- Access via: `http://yourapp.yourdomain.com:8501`

**Option C: Add Load Balancer + SSL**
- Application Load Balancer
- SSL Certificate (AWS Certificate Manager - FREE)
- Access via: `https://yourapp.yourdomain.com`
- Cost: **+$16/month**

## 🎯 Recommended Deployment for Demo

### Best Choice: EC2 t3.medium

**Why:**
- Simple to setup (30 minutes)
- Easy to debug
- Predictable costs
- Good for 10-50 concurrent users
- Can upgrade later

**Setup:**
```yaml
Instance: t3.medium
RAM: 4GB
CPU: 2 vCPU
Storage: 20GB EBS
Cost: ~$30/month
Region: us-east-1 (cheapest)
```

**Access:**
```
http://<EC2-IP>:8501
```

## 📊 Scaling Considerations

### Current Setup (500 PDFs)
- **ChromaDB Size**: ~500MB
- **RAM Usage**: 2-3GB
- **Concurrent Users**: 10-20
- **Query Latency**: 3-5 seconds

### If You Need More Scale

**For 50-100 Concurrent Users:**
- Use **t3.large** (8GB RAM): **$60/month**
- Add **Application Load Balancer**
- Multiple Streamlit instances

**For High Traffic (100+ users):**
- Use **ECS Fargate** with auto-scaling
- Separate **ChromaDB to RDS** or managed service
- **API Gateway + Lambda** for queries
- Cost: **$100-200/month**

## 🔒 Security for Public Demo

### Must-Have Security

1. **Restrict PDF Upload**
```python
# In app.py, disable upload for public demo
ALLOW_PDF_UPLOAD = False  # Read-only mode

# Users can only query pre-loaded 500 PDFs
```

2. **Rate Limiting**
```python
# Limit queries per user/IP
MAX_QUERIES_PER_HOUR = 10
```

3. **API Key Protection**
```python
# Store in AWS Secrets Manager
# Or use environment variables
# NEVER expose in code
```

4. **Limit Response Length**
```python
# Reduce OpenAI costs
max_tokens = 300  # Shorter responses
```

### Security Group Rules
```
Inbound:
- Port 22 (SSH): Your IP only
- Port 8501 (Streamlit): 0.0.0.0/0 (public)

Outbound:
- All traffic allowed (for API calls)
```

## 💡 Cost Optimization for Public Demo

### Strategy 1: Read-Only Demo
- Disable PDF upload in public version
- Users can only query pre-loaded 500 PDFs
- **Saves**: No embedding costs, controlled OpenAI usage

### Strategy 2: Query Limits
```python
# Implement per-user limits
MAX_DAILY_QUERIES = 20  # Per IP address
```

### Strategy 3: Response Caching
```python
# Cache common questions
# Reduces OpenAI API calls
from functools import lru_cache

@lru_cache(maxsize=100)
def get_cached_answer(question):
    # Return cached if exists
    # Otherwise query RAG
```

### Strategy 4: Use Spot Instances
- EC2 Spot: **50-70% cheaper**
- Good for non-critical demos
- May be interrupted (rare)

## 📝 Deployment Checklist

### Pre-Deployment
- [ ] Process all 500 PDFs locally
- [ ] Test app thoroughly on local machine
- [ ] Package chromadb folder
- [ ] Set environment variables
- [ ] Write deployment documentation

### AWS Setup
- [ ] Create AWS account (Free Tier eligible)
- [ ] Launch EC2 instance
- [ ] Configure Security Group
- [ ] Allocate Elastic IP (optional)
- [ ] Setup domain (optional)

### Application Deployment
- [ ] Upload code and chromadb to EC2
- [ ] Install dependencies
- [ ] Configure environment
- [ ] Test locally on EC2
- [ ] Run in background (screen/tmux)
- [ ] Test public access

### Post-Deployment
- [ ] Monitor costs in AWS Console
- [ ] Setup CloudWatch alarms
- [ ] Test from different locations
- [ ] Share link with users
- [ ] Monitor OpenAI usage

## 🎓 Sample Deployment Commands

### Complete Setup Script
```bash
#!/bin/bash

# Update system
sudo apt update && sudo apt upgrade -y

# Install Python and pip
sudo apt install python3.10 python3-pip -y

# Install dependencies
pip install -r requirements.txt

# Download sentence-transformers model (if not included)
python3 -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# Create systemd service
sudo cat > /etc/systemd/system/ragbot.service << EOF
[Unit]
Description=RAG Chatbot
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/v3_RAGBOT
ExecStart=/usr/local/bin/streamlit run app.py --server.port 8501 --server.address 0.0.0.0
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Start service
sudo systemctl enable ragbot
sudo systemctl start ragbot
```

## 🌐 Accessing Your Demo

### After Deployment

**Public URL:**
```
http://<EC2-PUBLIC-IP>:8501
```

**With Domain:**
```
http://rag-demo.yourdomain.com:8501
```

**With SSL (Optional):**
```
https://rag-demo.yourdomain.com
```

## 💰 Total Cost Breakdown (12 Months)

### Budget Option (Free Tier)
- EC2 t2.micro: **$0** (12 months)
- OpenAI API (light use): **$5-10/month** × 12 = **$60-120**
- **Total Year 1: $60-120**

### Recommended Option
- EC2 t3.medium: **$30/month** × 12 = **$360**
- OpenAI API (moderate): **$12/month** × 12 = **$144**
- **Total Year 1: $504**

### Production Option
- ECS + ALB: **$56/month** × 12 = **$672**
- OpenAI API (heavy): **$30/month** × 12 = **$360**
- **Total Year 1: $1,032**

## ✅ Advantages of Cost-Optimized Version for AWS

1. **Pre-built Vectors** ✅
   - Upload once, use forever
   - No embedding costs from users

2. **Simple Architecture** ✅
   - One application file
   - Easy to deploy
   - Easy to debug

3. **Predictable Costs** ✅
   - EC2: Fixed monthly
   - OpenAI: Only for queries
   - No surprise embedding bills

4. **Easy Scaling** ✅
   - Start small (t2.micro)
   - Upgrade as needed
   - Can handle 500 PDFs easily

## 🎯 Recommendation

**For Public Demo (Testing with Users):**

1. **Start with EC2 t2.micro** (Free Tier)
   - Cost: ~$5-10/month (OpenAI only)
   - Good for 5-10 users
   - Learn and test

2. **Upgrade to t3.medium** if needed
   - Cost: ~$42/month
   - Good for 20-50 users
   - Professional demo

3. **Add features incrementally**
   - Domain name
   - SSL certificate
   - Load balancer
   - Auto-scaling

**Yes, this cost-optimized version is PERFECT for AWS hosting!**

Want me to proceed with building it now?