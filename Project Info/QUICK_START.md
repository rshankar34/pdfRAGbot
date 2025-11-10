# 🚀 Quick Start Guide

Get your RAG PDF Chatbot running in 5 minutes!

## Step 1: Setup (2 minutes)

```bash
# Clone and enter directory
cd v3_RAGBOT

# Create virtual environment
python -m venv venv

# Activate it
source venv/bin/activate  # Mac/Linux
# OR
venv\Scripts\activate     # Windows

# Install dependencies (takes 5-10 mins first time)
pip install -r requirements.txt
```

## Step 2: Configure (30 seconds)

```bash
# Copy environment template
cp .env.example .env

# Edit and add your OpenAI API key
nano .env  # Mac/Linux
# OR
notepad .env  # Windows
```

Add:
```
OPENAI_API_KEY=sk-your-actual-key-here
```

Get your key from: https://platform.openai.com/api-keys

## Step 3: Run (10 seconds)

```bash
streamlit run app.py
```

Browser opens automatically at http://localhost:8501

## Step 4: Use It! (1 minute)

1. **Upload PDFs**: Click "Browse files" in sidebar
2. **Process**: Click "Process Uploaded PDFs" button
3. **Ask**: Type a question in the chat box
4. **Done**: Get answers with source citations!

## 🎯 Example Questions to Try

After uploading PDFs, try asking:
- "What is this document about?"
- "Summarize the main points"
- "What does it say about [specific topic]?"
- "Compare the information from different documents"

## 💡 Tips

- First query takes longer (loading models)
- Processing 10 PDFs takes ~1-2 minutes
- Check sources to verify answers
- Use "Clear Chat History" to start fresh

## 🐛 Issues?

**App won't start?**
```bash
# Make sure you're in venv
source venv/bin/activate

# Reinstall
pip install -r requirements.txt --upgrade
```

**No API key error?**
```bash
# Check .env file
cat .env

# Make sure it has:
OPENAI_API_KEY=sk-...
```

**Need help?** See full [README.md](README.md)

## 📱 Share Your App

Want others to use it? See:
- [FREE_TIER_DEPLOYMENT_GUIDE.md](FREE_TIER_DEPLOYMENT_GUIDE.md) - Deploy to AWS for $5-12/month
- [AWS_DEPLOYMENT.md](AWS_DEPLOYMENT.md) - Complete deployment guide with troubleshooting
- [AWS_TROUBLESHOOTING.md](AWS_TROUBLESHOOTING.md) - Common issues and solutions

### Quick AWS Deployment

```bash
# Set your OpenAI API key
export OPENAI_API_KEY="sk-..."

# Run automated deployment
./deploy/quick-deploy.sh
```

**Deployment time**: ~30 minutes
**Monthly cost**: $5-12 (Free Tier + OpenAI)

---

**That's it! You're ready to chat with your PDFs! 🎉**

**That's it! You're ready to chat with your PDFs! 🎉**