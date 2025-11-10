"""
RAG-based PDF Chatbot
A cost-optimized chatbot using local embeddings and OpenAI for chat responses.
"""

import os
import logging
import streamlit as st
from pathlib import Path
from typing import List
from dotenv import load_dotenv

# LangChain imports
from langchain_community.document_loaders import PyPDFLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_community.vectorstores import FAISS
from langchain_openai import ChatOpenAI
from langchain.chains import RetrievalQA
from langchain.prompts import PromptTemplate

# Load environment variables
load_dotenv()

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
#LLM_MODEL = os.getenv("LLM_MODEL", "gpt-3.5-turbo")
LLM_MODEL = os.getenv("LLM_MODEL", "gpt-4o-mini")
TEMPERATURE = float(os.getenv("TEMPERATURE", "0.3"))
MAX_TOKENS = int(os.getenv("MAX_TOKENS", "500"))
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "1000"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "200"))
RETRIEVAL_TOP_K = int(os.getenv("RETRIEVAL_TOP_K", "4"))
VECTOR_STORE_PATH = os.getenv("VECTOR_STORE_PATH", "./data/vector_store")
PDF_STORAGE_DIR = "./data/pdfs"

# Page configuration
st.set_page_config(
    page_title="RAG PDF Chatbot",
    page_icon="📚",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS
st.markdown("""
    <style>
    .main-header {
        font-size: 2.5rem;
        font-weight: 700;
        color: #1E88E5;
        text-align: center;
        margin-bottom: 1rem;
    }
    .sub-header {
        font-size: 1.2rem;
        color: #666;
        text-align: center;
        margin-bottom: 2rem;
    }
    .info-box {
        background-color: #E3F2FD;
        padding: 1rem;
        border-radius: 0.5rem;
        margin: 1rem 0;
    }
    .success-box {
        background-color: #E8F5E9;
        padding: 1rem;
        border-radius: 0.5rem;
        margin: 1rem 0;
    }
    .source-box {
        background-color: #F5F5F5;
        padding: 1rem;
        border-radius: 0.5rem;
        margin-top: 1rem;
        border-left: 4px solid #1E88E5;
    }
    </style>
""", unsafe_allow_html=True)


def initialize_embeddings():
    """Initialize local embeddings model (cost-free)."""
    try:
        embeddings = HuggingFaceEmbeddings(
            model_name="sentence-transformers/all-MiniLM-L6-v2",
            model_kwargs={'device': 'cpu'},
            encode_kwargs={'normalize_embeddings': True}
        )
        return embeddings
    except Exception as e:
        st.error(f"Error initializing embeddings: {str(e)}")
        return None


def initialize_vector_store(embeddings):
    """Initialize or load existing FAISS vector store."""
    try:
        # Create directory if it doesn't exist
        Path(VECTOR_STORE_PATH).mkdir(parents=True, exist_ok=True)
        
        # Try to load existing vector store
        index_path = Path(VECTOR_STORE_PATH) / "index.faiss"
        if index_path.exists():
            vector_store = FAISS.load_local(
                VECTOR_STORE_PATH,
                embeddings,
                allow_dangerous_deserialization=True
            )
        else:
            # Create new empty vector store
            vector_store = None
        
        return vector_store
    except Exception as e:
        st.error(f"Error initializing vector store: {str(e)}")
        return None


def process_pdf_from_file(pdf_path, vector_store):
    """Process a PDF file from disk path and add to vector store."""
    try:
        # Load PDF
        loader = PyPDFLoader(pdf_path)
        documents = loader.load()
        
        # Split text into chunks
        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=CHUNK_SIZE,
            chunk_overlap=CHUNK_OVERLAP,
            separators=["\n\n", "\n", ".", " ", ""]
        )
        chunks = text_splitter.split_documents(documents)
        
        # Add metadata
        pdf_name = os.path.basename(pdf_path)
        for i, chunk in enumerate(chunks):
            chunk.metadata["source"] = pdf_name
            chunk.metadata["chunk_id"] = i
            chunk.metadata["full_path"] = pdf_path
        
        # Add to vector store or create new one
        if vector_store is None:
            vector_store = FAISS.from_documents(chunks, st.session_state.embeddings)
        else:
            vector_store.add_documents(chunks)
        
        # Save to disk
        vector_store.save_local(VECTOR_STORE_PATH)
        
        return True, vector_store
    except Exception as e:
        pdf_name = os.path.basename(pdf_path)
        st.error(f"Error processing {pdf_name}: {str(e)}")
        return False, vector_store


def process_pdf(pdf_file, vector_store):
    """Process an uploaded PDF file. Returns (success, updated_vector_store)."""
    try:
        # Create PDF storage directory if it doesn't exist
        Path(PDF_STORAGE_DIR).mkdir(parents=True, exist_ok=True)
        
        # Save uploaded file temporarily
        pdf_path = os.path.join(PDF_STORAGE_DIR, pdf_file.name)
        with open(pdf_path, "wb") as f:
            f.write(pdf_file.getbuffer())
        
        # Process the saved file
        return process_pdf_from_file(pdf_path, vector_store)
    except Exception as e:
        st.error(f"Error processing {pdf_file.name}: {str(e)}")
        return False, vector_store


def scan_and_process_local_pdfs(vector_store):
    """Scan nested folders in PDF directory and process all PDFs."""
    processed_count = 0
    pdf_dir = Path(PDF_STORAGE_DIR)
    
    if not pdf_dir.exists():
        return 0, vector_store
    
    # Find all PDF files recursively (supports nested folders!)
    pdf_files = list(pdf_dir.rglob("*.pdf"))
    
    for pdf_path in pdf_files:
        pdf_name = pdf_path.name
        if pdf_name not in st.session_state.processed_files:
            success, vector_store = process_pdf_from_file(str(pdf_path), vector_store)
            if success:
                st.session_state.processed_files.append(pdf_name)
                processed_count += 1
    
    return processed_count, vector_store


def initialize_qa_chain(vector_store):
    """Initialize the RAG QA chain with OpenAI."""
    try:
        # Initialize OpenAI LLM
        llm = ChatOpenAI(
            model_name=LLM_MODEL,
            temperature=TEMPERATURE,
            max_tokens=MAX_TOKENS,
            openai_api_key=OPENAI_API_KEY
        )
        
        # Create custom prompt template
        template = """You are a helpful assistant that answers questions based on the provided context from PDF documents.
Use the following pieces of context to answer the question at the end. 
If you don't know the answer or if the context doesn't contain relevant information, just say that you don't know, don't try to make up an answer.
Always cite the source document in your answer.

Context:
{context}

Question: {question}

Answer: """
        
        prompt = PromptTemplate(
            template=template,
            input_variables=["context", "question"]
        )
        
        # Create retrieval QA chain
        qa_chain = RetrievalQA.from_chain_type(
            llm=llm,
            chain_type="stuff",
            retriever=vector_store.as_retriever(
                search_kwargs={"k": RETRIEVAL_TOP_K}
            ),
            return_source_documents=True,
            chain_type_kwargs={"prompt": prompt}
        )
        
        return qa_chain
    except Exception as e:
        st.error(f"Error initializing QA chain: {str(e)}")
        return None


def get_answer(qa_chain, question: str):
    """Get answer from the QA chain."""
    try:
        response = qa_chain.invoke({"query": question})
        return response
    except Exception as e:
        st.error(f"Error getting answer: {str(e)}")
        return None


def main():
    """Main application function."""
    
    # Header
    st.markdown('<h1 class="main-header">📚 RAG PDF Chatbot</h1>', unsafe_allow_html=True)
    st.markdown(
        '<p class="sub-header">Upload PDFs and ask questions - Powered by Local Embeddings & OpenAI</p>',
        unsafe_allow_html=True
    )
    
    # Check for API key
    if not OPENAI_API_KEY:
        st.error("⚠️ OpenAI API key not found! Please set it in the .env file.")
        st.info("Create a .env file with: OPENAI_API_KEY=your_key_here")
        st.stop()
    
    # Initialize session state
    if 'embeddings' not in st.session_state:
        with st.spinner("🔄 Initializing embeddings model (first time may take a minute)..."):
            st.session_state.embeddings = initialize_embeddings()
    
    if 'vector_store' not in st.session_state:
        with st.spinner("🔄 Initializing vector database..."):
            st.session_state.vector_store = initialize_vector_store(st.session_state.embeddings)
    
    if 'qa_chain' not in st.session_state:
        if st.session_state.vector_store:
            st.session_state.qa_chain = initialize_qa_chain(st.session_state.vector_store)
    
    if 'processed_files' not in st.session_state:
        st.session_state.processed_files = []
    
    if 'chat_history' not in st.session_state:
        st.session_state.chat_history = []
    
    # Sidebar
    with st.sidebar:
        st.header("📄 Document Management")
        
        # PDF Upload
        uploaded_files = st.file_uploader(
            "Upload PDF Documents",
            type=['pdf'],
            accept_multiple_files=True,
            help="Upload one or more PDF documents to add to the knowledge base"
        )
        
        if uploaded_files:
            if st.button("📤 Process Uploaded PDFs", type="primary"):
                progress_bar = st.progress(0)
                status_text = st.empty()
                
                success_count = 0
                total_files = len(uploaded_files)
                
                for idx, pdf_file in enumerate(uploaded_files):
                    if pdf_file.name not in st.session_state.processed_files:
                        status_text.text(f"Processing {pdf_file.name}...")
                        
                        result = process_pdf(pdf_file, st.session_state.vector_store)
                        if result and len(result) == 2:
                            success, updated_store = result
                            if success:
                                st.session_state.vector_store = updated_store
                                st.session_state.processed_files.append(pdf_file.name)
                                success_count += 1
                        
                        progress_bar.progress((idx + 1) / total_files)
                    else:
                        status_text.text(f"Skipping {pdf_file.name} (already processed)")
                        progress_bar.progress((idx + 1) / total_files)
                
                status_text.empty()
                progress_bar.empty()
                
                if success_count > 0:
                    st.success(f"✅ Successfully processed {success_count} new PDF(s)!")
                    # Reinitialize QA chain with updated vector store
                    st.session_state.qa_chain = initialize_qa_chain(st.session_state.vector_store)
                    st.rerun()
        
        # Scan local PDF folders button
        st.divider()
        if st.button("🔍 Scan Local PDF Folders", help="Scan data/pdfs/ for PDFs in nested folders"):
            with st.spinner("Scanning for PDFs..."):
                count, st.session_state.vector_store = scan_and_process_local_pdfs(st.session_state.vector_store)
                if count > 0:
                    st.success(f"✅ Found and processed {count} new PDF(s) from local folders!")
                    st.session_state.qa_chain = initialize_qa_chain(st.session_state.vector_store)
                    st.rerun()
                else:
                    st.info("No new PDFs found in data/pdfs/ directory")
        
        # Display processed files
        st.divider()
        st.subheader("📚 Processed Documents")
        if st.session_state.processed_files:
            st.markdown(f"**Total:** {len(st.session_state.processed_files)} document(s)")
            with st.expander("View all documents"):
                for file in st.session_state.processed_files:
                    st.text(f"• {file}")
        else:
            st.info("No documents processed yet. Upload PDFs to get started!")
        
        # Statistics
        st.divider()
        st.subheader("📊 Statistics")
        if st.session_state.vector_store:
            try:
                doc_count = st.session_state.vector_store.index.ntotal
                st.metric("Total Chunks", doc_count)
            except:
                st.metric("Total Chunks", len(st.session_state.processed_files))
        else:
            st.metric("Total Documents", len(st.session_state.processed_files))
        
        # Clear database option
        st.divider()
        if st.button("🗑️ Clear All Data", type="secondary"):
            if st.session_state.get('confirm_clear', False):
                # Clear vector store
                try:
                    import shutil
                    if Path(VECTOR_STORE_PATH).exists():
                        shutil.rmtree(VECTOR_STORE_PATH)
                    st.session_state.vector_store = None
                    st.session_state.qa_chain = None
                    st.session_state.processed_files = []
                    st.session_state.chat_history = []
                    st.session_state.confirm_clear = False
                    st.success("✅ All data cleared!")
                    st.rerun()
                except Exception as e:
                    st.error(f"Error clearing data: {str(e)}")
            else:
                st.session_state.confirm_clear = True
                st.warning("⚠️ Click again to confirm deletion of all data")
    
    # Main content area
    if not st.session_state.processed_files:
        # Welcome message
        st.markdown("""
        <div class="info-box">
        <h3>👋 Welcome to RAG PDF Chatbot!</h3>
        <p><strong>Get started:</strong></p>
        <ol>
            <li>Upload PDF documents using the sidebar</li>
            <li>Click "Process Uploaded PDFs"</li>
            <li>Ask questions about your documents!</li>
        </ol>
        <p><strong>Features:</strong></p>
        <ul>
            <li>💰 Cost-optimized with local embeddings (FREE)</li>
            <li>⚡ Fast retrieval with ChromaDB</li>
            <li>🤖 Powered by OpenAI for accurate answers</li>
            <li>📝 Source citations for transparency</li>
        </ul>
        </div>
        """, unsafe_allow_html=True)
    else:
        # Chat interface
        st.subheader("💬 Ask Questions")
        
        # Display chat history
        for chat in st.session_state.chat_history:
            with st.chat_message("user"):
                st.write(chat["question"])
            with st.chat_message("assistant"):
                st.write(chat["answer"])
                if chat.get("sources"):
                    with st.expander("📄 View Sources"):
                        for i, source in enumerate(chat["sources"], 1):
                            st.markdown(f"""
                            <div class="source-box">
                            <strong>Source {i}:</strong> {source['source']}<br>
                            <strong>Content:</strong> {source['content'][:300]}...
                            </div>
                            """, unsafe_allow_html=True)
        
        # Question input
        question = st.chat_input("Ask a question about your documents...")
        
        if question:
            # Add user message to chat
            with st.chat_message("user"):
                st.write(question)
            
            # Get answer
            with st.chat_message("assistant"):
                with st.spinner("🤔 Thinking..."):
                    if st.session_state.qa_chain:
                        response = get_answer(st.session_state.qa_chain, question)
                        
                        if response:
                            answer = response['result']
                            sources = response.get('source_documents', [])
                            
                            st.write(answer)
                            
                            # Display sources
                            if sources:
                                with st.expander("📄 View Sources"):
                                    for i, doc in enumerate(sources, 1):
                                        st.markdown(f"""
                                        <div class="source-box">
                                        <strong>Source {i}:</strong> {doc.metadata.get('source', 'Unknown')}<br>
                                        <strong>Page:</strong> {doc.metadata.get('page', 'N/A')}<br>
                                        <strong>Content:</strong> {doc.page_content[:300]}...
                                        </div>
                                        """, unsafe_allow_html=True)
                            
                            # Save to chat history
                            st.session_state.chat_history.append({
                                "question": question,
                                "answer": answer,
                                "sources": [
                                    {
                                        "source": doc.metadata.get('source', 'Unknown'),
                                        "content": doc.page_content
                                    }
                                    for doc in sources
                                ]
                            })
                    else:
                        st.error("QA chain not initialized. Please check your configuration.")
        
        # Clear chat history button
        if st.session_state.chat_history:
            if st.button("🗑️ Clear Chat History"):
                st.session_state.chat_history = []
                st.rerun()


if __name__ == "__main__":
    main()