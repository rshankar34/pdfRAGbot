# RAG Chatbot Architecture Plan

## Project Overview

A production-ready RAG (Retrieval-Augmented Generation) chatbot system designed to efficiently process and query large volumes of PDF documents (100+ PDFs, 1GB+ total size). Built with LangChain, ChromaDB, OpenAI, and Streamlit.

## System Architecture

### High-Level Architecture

```
┌─────────────────┐
│   Streamlit UI  │
│  (Frontend)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  RAG Engine     │
│  (LangChain)    │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌─────────┐ ┌──────────┐
│ ChromaDB│ │ OpenAI   │
│(Vectors)│ │ API      │
└─────────┘ └──────────┘
```

### Component Breakdown

#### 1. Frontend Layer (Streamlit)
- **Purpose**: User interface for document upload and chat interaction
- **Features**:
  - PDF upload interface (single or batch)
  - Document ingestion status tracker
  - Chat interface for queries
  - Response display with source citations
  - Optional: Document statistics dashboard

#### 2. Document Processing Layer
- **Purpose**: Efficient PDF ingestion and chunking
- **Components**:
  - PDF loader (PyPDF or LangChain PDF loaders)
  - Text splitter (RecursiveCharacterTextSplitter)
  - Batch processor for handling 100+ documents
- **Key Decisions**:
  - Chunk size: 1000 characters with 200 overlap
  - Parallel processing for faster ingestion
  - Progress tracking for large batches

#### 3. Vector Store Layer (ChromaDB)
- **Purpose**: Persistent storage of document embeddings
- **Features**:
  - Local persistent storage
  - Efficient similarity search
  - Metadata filtering capabilities
  - Easy migration path to cloud storage
- **Configuration**:
  - Persistent directory for vector database
  - Collection management for organized storage

#### 4. Embeddings Layer (OpenAI)
- **Purpose**: Convert text chunks to vector embeddings
- **Model**: text-embedding-ada-002
- **Optimization**: Batch embedding requests to reduce API calls

#### 5. RAG Chain Layer (LangChain)
- **Purpose**: Orchestrate retrieval and generation
- **Components**:
  - RetrievalQA chain (simple Q&A without memory)
  - Custom prompts for better responses
  - Source document tracking
- **Configuration**:
  - Top-k retrieval: 4-5 most relevant chunks
  - LLM: GPT-3.5-turbo or GPT-4
  - Temperature: 0.3 for more factual responses

## Data Flow

### Document Ingestion Flow
```
PDF Upload → PDF Parsing → Text Extraction → 
Text Chunking → Generate Embeddings → 
Store in ChromaDB → Confirmation
```

### Query Flow
```
User Query → Generate Query Embedding → 
Search ChromaDB → Retrieve Top-K Chunks → 
Build Context → LLM Generation → 
Display Answer + Sources
```

## Project Structure

```
v3_RAGBOT/
├── app.py                      # Main Streamlit application
├── requirements.txt            # Python dependencies
├── .env.example               # Environment variables template
├── .gitignore                 # Git ignore file
├── README.md                  # Project documentation
├── config/
│   └── settings.py            # Configuration management
├── src/
│   ├── __init__.py
│   ├── document_processor.py  # PDF processing and chunking
│   ├── vector_store.py        # ChromaDB operations
│   ├── rag_chain.py           # LangChain RAG setup
│   └── utils.py               # Utility functions
├── data/
│   ├── pdfs/                  # Local PDF storage (for testing)
│   └── chroma_db/             # ChromaDB persistent storage
└── tests/
    └── sample_pdfs/           # Test documents
```

## Technical Implementation Details

### 1. PDF Processing Strategy

**For Handling Large Volumes:**
- Implement batch processing with progress bars
- Use multiprocessing for parallel PDF parsing
- Implement error handling for corrupted PDFs
- Track processed documents to avoid duplicates

**Code Structure:**
```python
class PDFProcessor:
    def process_pdfs(pdf_paths, batch_size=10)
    def extract_text(pdf_path)
    def chunk_text(text, chunk_size, overlap)
    def get_processed_status()
```

### 2. Vector Store Management

**ChromaDB Configuration:**
- Persistent storage in `data/chroma_db/`
- Collection naming strategy for organization
- Metadata storage: filename, page number, upload date
- Index optimization for fast retrieval

**Code Structure:**
```python
class VectorStoreManager:
    def initialize_store(persist_directory)
    def add_documents(chunks, metadata)
    def search_similar(query, k=5)
    def get_collection_stats()
```

### 3. RAG Chain Implementation

**LangChain Setup:**
- Use RetrievalQA chain for simplicity
- Custom prompt template for better context
- Return source documents for transparency
- Configurable retrieval parameters

**Code Structure:**
```python
class RAGChain:
    def initialize_chain(vector_store, llm)
    def query(question)
    def format_response(answer, sources)
```

### 4. Streamlit Frontend

**UI Components:**
- Sidebar: Document upload and management
- Main area: Chat interface
- Footer: Statistics and settings
- Session state management for conversation

**Features:**
- Multi-file upload with drag-and-drop
- Real-time ingestion progress
- Query history display
- Source document highlighting

## Configuration Management

### Environment Variables
```env
OPENAI_API_KEY=your_api_key_here
CHUNK_SIZE=1000
CHUNK_OVERLAP=200
RETRIEVAL_TOP_K=4
LLM_MODEL=gpt-3.5-turbo
TEMPERATURE=0.3
CHROMA_PERSIST_DIR=./data/chroma_db
```

### Settings Module
- Centralized configuration
- Validation of required variables
- Default values for optional parameters
- Easy modification for production deployment

## Optimization Strategies

### For Large Document Volumes

1. **Ingestion Optimization:**
   - Batch processing (10-20 PDFs at a time)
   - Parallel text extraction
   - Cached embeddings to avoid re-processing
   - Incremental updates (only new documents)

2. **Retrieval Optimization:**
   - Efficient top-k search
   - Metadata filtering for faster queries
   - Hybrid search (optional: keyword + semantic)
   - Response caching for common queries

3. **Cost Optimization:**
   - Batch embedding API calls
   - Use cheaper embedding model for development
   - Implement rate limiting
   - Monitor API usage

## AWS Migration Readiness

### Current Local Setup → Future AWS Setup

| Component | Local | AWS Equivalent |
|-----------|-------|----------------|
| PDF Storage | `data/pdfs/` | S3 Bucket |
| Vector DB | Local ChromaDB | RDS or persistent EFS |
| Frontend | Local Streamlit | EC2 or ECS with Streamlit |
| API Keys | `.env` file | AWS Secrets Manager |
| Processing | Local CPU | Lambda for batch processing |

### Migration Considerations:
- ChromaDB supports cloud deployment
- S3 integration for PDF storage
- Environment variables from AWS Secrets Manager
- Docker containerization for easy deployment
- API Gateway for REST endpoints (if needed)

## Security Considerations

1. **API Key Management:**
   - Never commit `.env` file
   - Use environment variables
   - Implement key rotation strategy

2. **File Upload Security:**
   - Validate file types (PDF only)
   - File size limits
   - Scan for malicious content

3. **Data Privacy:**
   - Local processing (no third-party exposure)
   - Option to clear conversation history
   - Secure storage of vector embeddings

## Performance Metrics

### Expected Performance:
- **Ingestion**: 5-10 PDFs per minute (depending on size)
- **Query Response**: 3-5 seconds per query
- **Retrieval Accuracy**: 80-90% relevance (with proper chunking)
- **Concurrent Users**: 10-20 (Streamlit limitation)

### Monitoring Points:
- Document processing time
- Query response time
- Retrieval quality (manual evaluation)
- API usage and costs
- Vector store size

## Development Phases

### Phase 1: Core Implementation
1. Set up project structure
2. Implement PDF processing
3. Configure ChromaDB
4. Build basic RAG chain
5. Create simple Streamlit UI

### Phase 2: Optimization
1. Add batch processing
2. Implement progress tracking
3. Optimize chunking strategy
4. Add error handling
5. Improve UI/UX

### Phase 3: Testing & Documentation
1. Test with sample PDFs
2. Performance benchmarking
3. Write comprehensive README
4. Create user guide
5. Document API usage

## Key Dependencies

```
langchain >= 0.1.0
langchain-openai >= 0.0.5
chromadb >= 0.4.22
streamlit >= 1.29.0
openai >= 1.7.0
pypdf >= 3.17.0
python-dotenv >= 1.0.0
tiktoken >= 0.5.2
```

## Success Criteria

✅ Successfully ingest 100+ PDFs  
✅ Query response time < 5 seconds  
✅ Accurate and relevant answers  
✅ Source citation in responses  
✅ Intuitive user interface  
✅ Proper error handling  
✅ Comprehensive documentation  
✅ Easy AWS migration path  

## Next Steps

Once this plan is approved, we'll switch to **Code mode** to implement the solution following this architecture.