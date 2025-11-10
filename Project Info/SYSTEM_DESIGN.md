# RAG Chatbot System Design

## System Architecture Diagram

```mermaid
graph TB
    subgraph "User Interface Layer"
        UI[Streamlit Web App]
        Upload[PDF Upload Component]
        Chat[Chat Interface]
        Display[Response Display]
    end

    subgraph "Application Layer"
        App[app.py - Main Application]
        Config[Configuration Manager]
        Utils[Utility Functions]
    end

    subgraph "Processing Layer"
        PDFProc[PDF Processor]
        TextSplit[Text Chunker]
        Batch[Batch Processor]
    end

    subgraph "RAG Engine"
        Embed[OpenAI Embeddings]
        VectorStore[ChromaDB Vector Store]
        Retriever[Document Retriever]
        LLM[OpenAI LLM]
        Chain[LangChain RAG Chain]
    end

    subgraph "Storage Layer"
        LocalPDF[Local PDF Storage]
        ChromaDB[ChromaDB Persistent Storage]
        S3[Future: S3 Bucket]
    end

    subgraph "External Services"
        OpenAI[OpenAI API]
    end

    UI --> Upload
    UI --> Chat
    UI --> Display
    
    Upload --> App
    Chat --> App
    App --> Config
    App --> PDFProc
    App --> Chain
    
    PDFProc --> TextSplit
    TextSplit --> Batch
    Batch --> Embed
    
    Embed --> OpenAI
    Embed --> VectorStore
    VectorStore --> ChromaDB
    
    Chat --> Chain
    Chain --> Retriever
    Retriever --> VectorStore
    Chain --> LLM
    LLM --> OpenAI
    Chain --> Display
    
    PDFProc --> LocalPDF
    LocalPDF -.Future.-> S3
```

## Document Ingestion Flow

```mermaid
sequenceDiagram
    participant User
    participant UI as Streamlit UI
    participant Proc as PDF Processor
    participant Split as Text Splitter
    participant Embed as OpenAI Embeddings
    participant DB as ChromaDB

    User->>UI: Upload PDF files
    UI->>Proc: Process PDFs
    
    loop For each PDF
        Proc->>Proc: Extract text
        Proc->>Split: Split into chunks
        Split->>Split: Create chunks with metadata
        Split->>Embed: Generate embeddings
        Embed->>Embed: Batch process
        Embed->>DB: Store vectors + metadata
    end
    
    DB->>UI: Ingestion complete
    UI->>User: Show success message
```

## Query-Answer Flow

```mermaid
sequenceDiagram
    participant User
    participant UI as Streamlit UI
    participant Chain as RAG Chain
    participant Embed as OpenAI Embeddings
    participant DB as ChromaDB
    participant LLM as OpenAI LLM

    User->>UI: Enter question
    UI->>Chain: Process query
    Chain->>Embed: Generate query embedding
    Embed->>DB: Search similar vectors
    DB->>Chain: Return top-k chunks
    Chain->>Chain: Build context from chunks
    Chain->>LLM: Generate answer with context
    LLM->>Chain: Return answer
    Chain->>UI: Format response + sources
    UI->>User: Display answer and sources
```

## Component Interaction Matrix

| Component | Interacts With | Purpose |
|-----------|---------------|---------|
| Streamlit UI | App, PDF Processor, RAG Chain | User interaction and display |
| PDF Processor | OpenAI Embeddings, ChromaDB | Document ingestion |
| ChromaDB | RAG Chain, PDF Processor | Vector storage and retrieval |
| RAG Chain | ChromaDB, OpenAI LLM | Query processing and answer generation |
| OpenAI API | Embeddings, LLM | AI capabilities |
| Config Manager | All components | Settings and API keys |

## Data Models

### Document Chunk
```python
{
    "content": str,              # Text content of chunk
    "metadata": {
        "source": str,           # PDF filename
        "page": int,             # Page number
        "chunk_id": str,         # Unique chunk identifier
        "upload_date": datetime, # When document was uploaded
        "total_pages": int       # Total pages in source PDF
    }
}
```

### Query Request
```python
{
    "question": str,             # User's question
    "top_k": int,                # Number of chunks to retrieve
    "filters": dict              # Optional metadata filters
}
```

### Query Response
```python
{
    "answer": str,               # Generated answer
    "sources": [                 # List of source documents
        {
            "content": str,      # Chunk content
            "source": str,       # PDF filename
            "page": int          # Page number
        }
    ],
    "confidence": float          # Optional: confidence score
}
```

## State Management

### Streamlit Session State
```python
session_state = {
    "vector_store": ChromaDB,     # Initialized vector store
    "rag_chain": RAGChain,        # Initialized RAG chain
    "processed_files": list,      # List of processed PDF names
    "query_history": list,        # Previous queries and answers
    "current_documents": int      # Count of documents in store
}
```

## Error Handling Strategy

```mermaid
graph LR
    A[Operation] --> B{Success?}
    B -->|Yes| C[Continue]
    B -->|No| D{Error Type}
    D -->|API Error| E[Retry with backoff]
    D -->|File Error| F[Skip and log]
    D -->|Config Error| G[Alert user]
    E --> H{Retry Success?}
    H -->|Yes| C
    H -->|No| I[Log and continue]
    F --> I
    G --> J[Stop process]
```

## Configuration Flow

```mermaid
graph TD
    Start[Application Start] --> Load[Load .env file]
    Load --> Validate[Validate API keys]
    Validate --> Check{Keys Valid?}
    Check -->|Yes| Init[Initialize components]
    Check -->|No| Error[Show error message]
    Init --> Ready[Application Ready]
    Error --> Stop[Stop application]
```

## Scaling Considerations

### Current Architecture
- Single machine deployment
- Local ChromaDB storage
- Streamlit single-threaded

### Future Scalability Path

```mermaid
graph TB
    subgraph "Current"
        C1[Single Streamlit Instance]
        C2[Local ChromaDB]
        C3[Local PDF Storage]
    end

    subgraph "Phase 2: Containerized"
        P2_1[Docker Container]
        P2_2[Persistent Volume]
        P2_3[Environment Configs]
    end

    subgraph "Phase 3: Cloud Native"
        P3_1[Load Balancer]
        P3_2[Multiple App Instances]
        P3_3[Managed Vector DB]
        P3_4[S3 Storage]
        P3_5[API Gateway]
    end

    C1 --> P2_1
    C2 --> P2_2
    C3 --> P2_2
    
    P2_1 --> P3_2
    P2_2 --> P3_3
    P2_2 --> P3_4
```

## Performance Optimization Points

### 1. Embedding Generation
- Batch multiple documents together
- Implement caching for previously embedded content
- Use async processing where possible

### 2. Vector Search
- Optimize top-k parameter (fewer = faster)
- Use metadata filtering to reduce search space
- Consider approximate nearest neighbor (ANN) for very large datasets

### 3. LLM Calls
- Set appropriate max_tokens limit
- Use streaming for better UX
- Implement response caching for common queries

### 4. Document Processing
- Process PDFs in parallel
- Use incremental indexing (only new documents)
- Implement checkpointing for large batches

## Security Architecture

```mermaid
graph TB
    subgraph "Security Layers"
        L1[Input Validation]
        L2[File Type Verification]
        L3[API Key Protection]
        L4[Data Encryption]
        L5[Access Control]
    end

    User[User Input] --> L1
    L1 --> L2
    L2 --> Process[Processing Pipeline]
    
    L3 --> Process
    L4 --> Storage[Data Storage]
    Process --> Storage
    
    L5 --> UI[User Interface]
```

## Monitoring and Logging

### Key Metrics to Track
1. **Ingestion Metrics**
   - PDFs processed per session
   - Average processing time per PDF
   - Failed ingestions and reasons

2. **Query Metrics**
   - Queries per session
   - Average response time
   - Retrieval quality scores

3. **System Metrics**
   - Vector store size
   - API usage and costs
   - Error rates

4. **User Metrics**
   - Session duration
   - Documents uploaded
   - Query patterns

## Development Workflow

```mermaid
graph LR
    Dev[Development] --> Test[Local Testing]
    Test --> Review[Code Review]
    Review --> Deploy[Deployment]
    Deploy --> Monitor[Monitoring]
    Monitor --> Improve[Improvements]
    Improve --> Dev
```

## Technology Stack Summary

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Frontend | Streamlit | Web UI |
| Backend | Python 3.10+ | Application logic |
| Framework | LangChain | RAG orchestration |
| Vector DB | ChromaDB | Embedding storage |
| Embeddings | OpenAI Ada-002 | Text vectorization |
| LLM | GPT-3.5/4 | Answer generation |
| PDF Processing | PyPDF/LangChain | Document parsing |
| Config | python-dotenv | Environment management |

## Implementation Priority

### Must Have (MVP)
1. PDF upload and processing
2. ChromaDB integration
3. Basic RAG chain
4. Simple Streamlit UI
5. Query and response display

### Should Have
1. Batch processing
2. Progress tracking
3. Source citations
4. Error handling
5. Configuration management

### Nice to Have
1. Query history
2. Document statistics
3. Advanced filtering
4. Response caching
5. Performance metrics

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| API costs | High | Implement rate limiting, use caching |
| Large file processing | Medium | Batch processing, progress tracking |
| Poor retrieval quality | High | Optimize chunking, tune top-k |
| Slow response time | Medium | Optimize retrieval, use faster models |
| Storage limits | Low | Monitor size, implement cleanup |

This system design provides a comprehensive blueprint for building the RAG chatbot while maintaining flexibility for future enhancements and AWS migration.