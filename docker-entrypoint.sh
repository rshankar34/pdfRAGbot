#!/bin/bash

# Production-ready entrypoint script for RAG PDF Chatbot
# Handles graceful shutdowns, logging, and environment validation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Environment validation
validate_environment() {
    log "Validating environment..."
    
    # Check if OpenAI API key is set
    if [ -z "$OPENAI_API_KEY" ]; then
        error "OPENAI_API_KEY environment variable is not set!"
        error "Please set it in your .env file or environment variables."
        exit 1
    fi
    
    # Check if API key has valid format
    if [[ ! "$OPENAI_API_KEY" =~ ^sk-[a-zA-Z0-9]{20,}$ ]]; then
        warn "OPENAI_API_KEY format appears invalid. Should start with 'sk-'"
    fi
    
    # Create necessary directories
    mkdir -p data/pdfs data/vector_store
    
    log "Environment validation passed"
}

# Health check function
health_check() {
    log "Performing health check..."
    
    # Check if required Python packages are installed
    python -c "import streamlit, langchain, openai, faiss" 2>/dev/null || {
        error "Required Python packages are missing!"
        exit 1
    }
    
    # Check disk space (require at least 1GB free)
    AVAILABLE_SPACE=$(df /app | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 1048576 ]; then
        warn "Low disk space available: $(($AVAILABLE_SPACE/1024))MB"
    fi
    
    log "Health check passed"
}

# Signal handling for graceful shutdown
shutdown_handler() {
    log "Received shutdown signal. Gracefully shutting down..."
    # Add any cleanup tasks here if needed
    exit 0
}

trap shutdown_handler SIGTERM SIGINT

# Main execution
main() {
    log "Starting RAG PDF Chatbot..."
    log "Configuration:"
    log "  - Model: ${LLM_MODEL:-gpt-3.5-turbo}"
    log "  - Temperature: ${TEMPERATURE:-0.3}"
    log "  - Max Tokens: ${MAX_TOKENS:-500}"
    log "  - Chunk Size: ${CHUNK_SIZE:-1000}"
    log "  - Vector Store: ${VECTOR_STORE_PATH:-./data/vector_store}"
    
    # Validate environment
    validate_environment
    
    # Perform health check
    health_check
    
    log "Starting Streamlit application..."
    
    # Start the application
    exec streamlit run app.py \
        --server.port=${STREAMLIT_SERVER_PORT:-8501} \
        --server.address=${STREAMLIT_SERVER_ADDRESS:-0.0.0.0} \
        --server.headless=${STREAMLIT_SERVER_HEADLESS:-true} \
        --browser.gatherUsageStats=${STREAMLIT_BROWSER_GATHER_USAGE_STATS:-false}
}

# Run main function
main "$@"