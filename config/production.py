"""
Production Settings for RAG PDF Chatbot
Simplified AWS configuration for production deployment
"""

import os
import logging
from pathlib import Path

# Base directory
BASE_DIR = Path(__file__).resolve().parent.parent

# Application Settings
APP_NAME = "RAG PDF Chatbot"
ENVIRONMENT = "production"

# OpenAI Configuration
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
LLM_MODEL = os.getenv("LLM_MODEL", "gpt-3.5-turbo")
TEMPERATURE = float(os.getenv("TEMPERATURE", "0.3"))
MAX_TOKENS = int(os.getenv("MAX_TOKENS", "500"))

# Vector Store Configuration
VECTOR_STORE_PATH = os.getenv("VECTOR_STORE_PATH", "./data/vector_store")
PDF_STORAGE_DIR = os.getenv("PDF_STORAGE_DIR", "./data/pdfs")

# Retrieval Configuration
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "1000"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "200"))
RETRIEVAL_TOP_K = int(os.getenv("RETRIEVAL_TOP_K", "4"))

# Security Settings
MAX_FILE_SIZE = int(os.getenv("MAX_FILE_SIZE", "52428800"))  # 50MB
ALLOWED_EXTENSIONS = {'.pdf'}

# Logging Configuration
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

def setup_logging():
    """Setup basic application logging"""
    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )