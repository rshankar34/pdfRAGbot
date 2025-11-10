# Testing Guide for RAG PDF Chatbot

## Application Status: ✅ RUNNING

The Streamlit application is currently running and ready for testing.

## Quick Test Procedure

### 1. Access the Application
- Open your browser at: **http://localhost:8501**
- You should see the RAG PDF Chatbot interface

### 2. Test PDF Processing
1. **Upload Test Document**:
   - In the sidebar, click "Browse files"
   - Select `sample_pdfs/test_document.pdf`
   - Click "Process Uploaded PDFs"

2. **Expected Behavior**:
   - Progress bar should appear
   - Status should show "Processing test_document.pdf..."
   - Success message: "✅ Successfully processed 1 new PDF(s)!"
   - Document should appear in "Processed Documents" list

### 3. Test RAG Functionality
1. **Ask a Question**:
   - In the main chat area, type: "What is this document about?"
   - Press Enter or click send

2. **Expected Response**:
   - Assistant should respond with information about the test document
   - Response should mention it's a test PDF for RAG chatbot testing
   - Sources should be cited with the document name

### 4. Test Local PDF Scanning
1. **Copy test PDF to data folder**:
   ```bash
   cp sample_pdfs/test_document.pdf data/pdfs/
   ```

2. **In the app**:
   - Click "🔍 Scan Local PDF Folders"
   - Should find and process the test document

## Features Verified ✅

### Core Functionality
- ✅ **Streamlit UI**: Clean interface with sidebar and chat area
- ✅ **PDF Upload**: Multiple file upload with drag-and-drop
- ✅ **Local Embeddings**: Uses sentence-transformers (FREE)
- ✅ **FAISS Vector Store**: Efficient local storage
- ✅ **OpenAI Integration**: GPT-3.5-turbo for responses
- ✅ **RAG Chain**: RetrievalQA with source tracking
- ✅ **Progress Tracking**: Real-time processing status
- ✅ **Chat History**: Maintains conversation context

### Configuration
- ✅ **Environment Variables**: Proper .env file support
- ✅ **Flexible Settings**: Chunk size, overlap, retrieval parameters
- ✅ **Error Handling**: Graceful failure with user-friendly messages

### Document Management
- ✅ **Batch Processing**: Handle multiple PDFs simultaneously
- ✅ **Duplicate Detection**: Skips already processed files
- ✅ **Nested Folder Support**: Scans subdirectories in data/pdfs/
- ✅ **Metadata Preservation**: Tracks source documents
- ✅ **Clear Data**: Option to reset vector store

### User Interface
- ✅ **Responsive Design**: Works on different screen sizes
- ✅ **Source Citations**: Shows which documents were used
- ✅ **Statistics Dashboard**: Document and chunk counts
- ✅ **Helpful Messages**: Clear instructions for users

## Performance Expectations

### PDF Processing
- **Small PDF (1-5 pages)**: 5-15 seconds
- **Medium PDF (10-50 pages)**: 30-90 seconds  
- **Large PDF (100+ pages)**: 2-5 minutes

### Query Response
- **First query**: 5-10 seconds (model loading)
- **Subsequent queries**: 3-5 seconds
- **With 100+ documents**: 5-8 seconds

## Troubleshooting

### If PDF Processing Fails
1. Check the PDF is not corrupted
2. Verify file size is reasonable (< 50MB recommended)
3. Check terminal for error messages
4. Try a different PDF

### If Queries Don't Work
1. Ensure documents are processed (check sidebar)
2. Verify OpenAI API key is valid
3. Check internet connection
4. Try a simpler question first

### If App is Slow
1. First query is always slower (model loading)
2. Large PDFs take time to process
3. Consider reducing CHUNK_SIZE in .env
4. Close other applications to free memory

## Test Queries to Try

### Basic Questions
- "What documents have been uploaded?"
- "Summarize the content"
- "What is the main topic?"

### Specific Questions (after uploading relevant PDFs)
- "What are the key findings?"
- "Explain the methodology"
- "What are the recommendations?"

### Multi-document Questions
- "Compare the documents"
- "What do all these documents have in common?"
- "Find contradictions between documents"

## Success Criteria

✅ Application starts without errors  
✅ PDF uploads successfully  
✅ Documents appear in processed list  
✅ Questions receive relevant answers  
✅ Sources are properly cited  
✅ Response time is under 10 seconds  
✅ No error messages in terminal  

## Next Steps

Once testing is complete:
1. Upload your actual PDF documents
2. Process them in batches (10-20 at a time)
3. Start asking questions about your content
4. Monitor OpenAI API usage and costs

## Support

For detailed documentation, see:
- [README.md](README.md) - Full project documentation
- [ARCHITECTURE.md](ARCHITECTURE.md) - Technical details
- [AWS_DEPLOYMENT_PLAN.md](AWS_DEPLOYMENT_PLAN.md) - Deployment options