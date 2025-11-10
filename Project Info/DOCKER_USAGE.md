# 🐳 Docker Containerization Guide

This guide covers how to build, run, and deploy the RAG PDF Chatbot using Docker containers.

## 📋 Prerequisites

- Docker Desktop installed and running
- Docker Compose installed
- OpenAI API key

## 🚀 Quick Start

### 1. Start Docker Desktop

First, ensure Docker Desktop is running:

**macOS:**
```bash
# Open Docker Desktop from Applications folder
# Or use Spotlight: Cmd + Space, type "Docker"
```

**Windows:**
```bash
# Open Docker Desktop from Start Menu
```

**Linux:**
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

### 2. Configure Environment

Create your `.env` file if you haven't already:

```bash
cp .env.example .env
```

Edit `.env` and add your OpenAI API key:
```env
OPENAI_API_KEY=sk-your-actual-api-key-here
```

### 3. Build and Run with Docker Compose

```bash
# Build and start the container
docker-compose up --build

# Run in detached mode (background)
docker-compose up -d --build

# View logs
docker-compose logs -f
```

The application will be available at: **http://localhost:8501**

## 🔧 Docker Commands

### Build Image
```bash
# Build the Docker image
docker build -t rag-pdf-chatbot:latest .

# Build with specific tag
docker build -t rag-pdf-chatbot:v1.0.0 .
```

### Run Container
```bash
# Run container with environment variables
docker run -d \
  --name rag-chatbot \
  -p 8501:8501 \
  -e OPENAI_API_KEY=your_api_key \
  -v $(pwd)/data/pdfs:/app/data/pdfs \
  -v $(pwd)/data/vector_store:/app/data/vector_store \
  rag-pdf-chatbot:latest

# Run with custom configuration
docker run -d \
  --name rag-chatbot \
  -p 8501:8501 \
  -e OPENAI_API_KEY=your_api_key \
  -e LLM_MODEL=gpt-4 \
  -e TEMPERATURE=0.5 \
  -v $(pwd)/data:/app/data \
  rag-pdf-chatbot:latest
```

### Manage Container
```bash
# Stop container
docker stop rag-chatbot

# Start container
docker start rag-chatbot

# Restart container
docker restart rag-chatbot

# View logs
docker logs rag-chatbot
docker logs -f rag-chatbot  # Follow logs

# Execute commands in running container
docker exec -it rag-chatbot bash

# Check container status
docker ps
docker stats rag-chatbot
```

### Clean Up
```bash
# Stop and remove container
docker stop rag-chatbot && docker rm rag-chatbot

# Remove image
docker rmi rag-pdf-chatbot:latest

# Clean up unused resources
docker system prune -a

# Remove volumes (⚠️ This will delete all data!)
docker volume prune
```

## 📁 Volume Management

### Persistent Data
The following directories are persisted using Docker volumes:

- `./data/pdfs` - Uploaded PDF files
- `./data/vector_store` - Vector database (FAISS)

### Backup Data
```bash
# Backup PDFs
tar -czf pdfs-backup.tar.gz data/pdfs/

# Backup vector store
tar -czf vector-store-backup.tar.gz data/vector_store/

# Restore data
tar -xzf pdfs-backup.tar.gz
tar -xzf vector-store-backup.tar.gz
```

### Migrate Data Between Containers
```bash
# Copy data from running container
docker cp rag-chatbot:/app/data/pdfs ./backup_pdfs/
docker cp rag-chatbot:/app/data/vector_store ./backup_vector_store/
```

## 🔧 Configuration

### Environment Variables

Configure the application using environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENAI_API_KEY` | - | **Required** OpenAI API key |
| `LLM_MODEL` | `gpt-3.5-turbo` | OpenAI model to use |
| `TEMPERATURE` | `0.3` | Response creativity (0-1) |
| `MAX_TOKENS` | `500` | Max response length |
| `CHUNK_SIZE` | `1000` | Text chunk size for processing |
| `CHUNK_OVERLAP` | `200` | Chunk overlap for context |
| `RETRIEVAL_TOP_K` | `4` | Number of chunks to retrieve |
| `VECTOR_STORE_PATH` | `./data/vector_store` | Vector database location |

### Docker Compose Override

Create `docker-compose.override.yml` for local customizations:

```yaml
version: '3.8'
services:
  rag-chatbot:
    environment:
      - LLM_MODEL=gpt-4
      - TEMPERATURE=0.5
      - MAX_TOKENS=1000
    ports:
      - "8501:8501"  # Change port if needed
```

## 🏥 Health Checks

The container includes built-in health checks:

```bash
# Check container health
docker inspect rag-chatbot --format='{{.State.Health.Status}}'

# View health check details
docker inspect rag-chatbot --format='{{json .State.Health}}'
```

## 🐛 Troubleshooting

### Docker Daemon Not Running
```bash
# macOS/Windows: Start Docker Desktop
# Linux: sudo systemctl start docker
```

### Port Already in Use
```bash
# Change port in docker-compose.yml or use different port
docker-compose up -d --build
# Then access at http://localhost:YOUR_PORT
```

### Permission Issues
```bash
# Fix permissions on data directories
sudo chown -R $USER:$USER data/
```

### Low Disk Space
```bash
# Clean up Docker resources
docker system prune -a
docker volume prune
```

### Container Won't Start
```bash
# Check logs for errors
docker logs rag-chatbot

# Check if OpenAI API key is set
docker exec rag-chatbot env | grep OPENAI_API_KEY
```

### Slow Performance
```bash
# Check resource usage
docker stats rag-chatbot

# Increase memory limit (Docker Desktop > Settings > Resources)
```

## ☁️ AWS Deployment

### Build for AWS
```bash
# Build image
docker build -t rag-pdf-chatbot:aws .

# Tag for ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
docker tag rag-pdf-chatbot:aws YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/rag-pdf-chatbot:latest
docker push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/rag-pdf-chatbot:latest
```

### ECS Task Definition
```json
{
  "family": "rag-chatbot",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "containerDefinitions": [
    {
      "name": "rag-chatbot",
      "image": "YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/rag-pdf-chatbot:latest",
      "portMappings": [
        {
          "containerPort": 8501,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "OPENAI_API_KEY",
          "value": "your_api_key"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/rag-chatbot",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

## 📊 Monitoring

### Container Metrics
```bash
# Real-time stats
docker stats rag-chatbot

# Container info
docker inspect rag-chatbot

# Resource usage history
docker system df
```

### Application Logs
```bash
# View all logs
docker logs rag-chatbot

# Follow logs in real-time
docker logs -f rag-chatbot

# Show last 100 lines
docker logs --tail 100 rag-chatbot

# Show logs since timestamp
docker logs --since 2024-01-01T00:00:00 rag-chatbot
```

## 🔒 Security Best Practices

1. **Never commit `.env` file** - Already in `.dockerignore`
2. **Use non-root user** - Configured in Dockerfile
3. **Keep images updated** - Regularly rebuild with latest base image
4. **Scan for vulnerabilities**:
   ```bash
   docker scan rag-pdf-chatbot:latest
   ```
5. **Use secrets management** in production (AWS Secrets Manager, etc.)

## 📦 Image Optimization

### Current Image Size
- Base: `python:3.11-slim` (~50MB)
- Final image: ~1.5-2GB (includes ML models)

### Optimization Tips
- Use multi-stage builds (already implemented)
- Minimize layers
- Use `.dockerignore` effectively
- Pin dependency versions

## 🔄 CI/CD Integration

### GitHub Actions Example
```yaml
name: Build and Deploy

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build Docker image
        run: docker build -t rag-pdf-chatbot:${{ github.sha }} .
      
      - name: Run tests
        run: |
          docker run --rm rag-pdf-chatbot:${{ github.sha }} python -c "import streamlit; print('OK')"
```

## 🤝 Support

For issues or questions:
1. Check container logs: `docker logs rag-chatbot`
2. Verify OpenAI API key is set correctly
3. Ensure sufficient disk space and memory
4. Check Docker daemon is running

---

**Happy containerizing!** 🎉