#!/bin/bash

# RAG PDF Chatbot - Quick Setup Script
# This script automates the initial setup process

set -e  # Exit on error

echo "🚀 RAG PDF Chatbot - Setup Script"
echo "=================================="
echo ""

# Check Python version
echo "📋 Checking Python version..."
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
REQUIRED_VERSION="3.10"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$PYTHON_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    echo "❌ Error: Python 3.10 or higher required. Found: $PYTHON_VERSION"
    exit 1
fi
echo "✅ Python $PYTHON_VERSION found"
echo ""

# Create virtual environment
echo "🔨 Creating virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "✅ Virtual environment created"
else
    echo "ℹ️  Virtual environment already exists"
fi
echo ""

# Activate virtual environment
echo "⚡ Activating virtual environment..."
source venv/bin/activate
echo "✅ Virtual environment activated"
echo ""

# Upgrade pip
echo "📦 Upgrading pip..."
pip install --upgrade pip > /dev/null 2>&1
echo "✅ Pip upgraded"
echo ""

# Install dependencies
echo "📚 Installing dependencies (this may take 5-10 minutes)..."
echo "   Downloading packages..."
pip install -r requirements.txt
echo "✅ All dependencies installed"
echo ""

# Create .env file if it doesn't exist
if [ ! -f ".env" ]; then
    echo "⚙️  Creating .env file..."
    cp .env.example .env
    echo "✅ .env file created"
    echo ""
    echo "⚠️  IMPORTANT: Edit .env file and add your OpenAI API key!"
    echo "   Run: nano .env"
    echo "   Add: OPENAI_API_KEY=sk-your-actual-key-here"
    echo ""
else
    echo "ℹ️  .env file already exists"
    echo ""
fi

# Create data directories
echo "📁 Creating data directories..."
mkdir -p data/pdfs data/chroma_db sample_pdfs
echo "✅ Directories created"
echo ""

# Success message
echo "✅ Setup complete!"
echo ""
echo "📝 Next Steps:"
echo "   1. Edit .env file and add your OpenAI API key:"
echo "      nano .env"
echo ""
echo "   2. Run the application:"
echo "      streamlit run app.py"
echo ""
echo "   3. Upload PDF files and start chatting!"
echo ""
echo "📖 For more help, see:"
echo "   - QUICK_START.md for quick setup guide"
echo "   - README.md for detailed documentation"
echo ""
echo "🎉 Happy chatting!"