#!/usr/bin/env python3
"""
Migration Script: Upload existing PDFs and vector store to S3
This script migrates local data to AWS S3 for production deployment
"""

import os
import sys
import json
import logging
from pathlib import Path
from typing import List, Tuple
import argparse
import boto3
from botocore.exceptions import ClientError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class S3MigrationTool:
    """Tool for migrating local data to S3"""
    
    def __init__(self, bucket_name: str, region: str = 'us-east-1', profile: str = 'default'):
        """
        Initialize S3 migration tool
        
        Args:
            bucket_name: S3 bucket name
            region: AWS region
            profile: AWS profile name
        """
        self.bucket_name = bucket_name
        self.region = region
        self.profile = profile
        
        # Initialize AWS session
        session = boto3.session.Session(profile_name=profile)
        self.s3_client = session.client('s3', region_name=region)
        
        logger.info(f"Initialized S3 migration tool for bucket: {bucket_name}")
    
    def upload_file(self, local_path: str, s3_key: str, extra_args: dict = None) -> bool:
        """
        Upload a single file to S3
        
        Args:
            local_path: Local file path
            s3_key: S3 key (path in bucket)
            extra_args: Additional arguments for upload
            
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            if extra_args is None:
                extra_args = {}
            
            # Add default content type for PDFs
            if local_path.endswith('.pdf') and 'ContentType' not in extra_args:
                extra_args['ContentType'] = 'application/pdf'
            
            self.s3_client.upload_file(
                local_path,
                self.bucket_name,
                s3_key,
                ExtraArgs=extra_args
            )
            
            logger.info(f"Uploaded: {local_path} -> s3://{self.bucket_name}/{s3_key}")
            return True
            
        except ClientError as e:
            logger.error(f"Error uploading {local_path}: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error uploading {local_path}: {e}")
            return False
    
    def upload_directory(self, local_dir: str, s3_prefix: str, 
                        file_filter: callable = None) -> Tuple[int, int]:
        """
        Upload all files from a local directory to S3
        
        Args:
            local_dir: Local directory path
            s3_prefix: S3 prefix (folder path)
            file_filter: Optional filter function for files
            
        Returns:
            Tuple[int, int]: (successful_uploads, total_files)
        """
        local_path = Path(local_dir)
        
        if not local_path.exists():
            logger.warning(f"Directory does not exist: {local_dir}")
            return 0, 0
        
        if not local_path.is_dir():
            logger.error(f"Path is not a directory: {local_dir}")
            return 0, 0
        
        successful = 0
        total = 0
        
        # Walk through directory and upload files
        for file_path in local_path.rglob('*'):
            if not file_path.is_file():
                continue
            
            # Apply file filter if provided
            if file_filter and not file_filter(file_path):
                continue
            
            total += 1
            
            # Calculate relative path and S3 key
            relative_path = file_path.relative_to(local_path)
            s3_key = f"{s3_prefix}/{relative_path}"
            
            # Upload file
            if self.upload_file(str(file_path), s3_key):
                successful += 1
        
        logger.info(f"Uploaded {successful}/{total} files from {local_dir}")
        return successful, total
    
    def migrate_pdfs(self, pdf_dir: str = './data/pdfs') -> Tuple[int, int]:
        """
        Migrate PDF files to S3
        
        Args:
            pdf_dir: Local PDF directory path
            
        Returns:
            Tuple[int, int]: (successful_uploads, total_files)
        """
        logger.info(f"Starting PDF migration from {pdf_dir}")
        
        def is_pdf(file_path: Path) -> bool:
            return file_path.suffix.lower() == '.pdf'
        
        return self.upload_directory(pdf_dir, 'pdfs', is_pdf)
    
    def migrate_vector_store(self, vector_store_dir: str = './data/vector_store') -> Tuple[int, int]:
        """
        Migrate vector store files to S3
        
        Args:
            vector_store_dir: Local vector store directory path
            
        Returns:
            Tuple[int, int]: (successful_uploads, total_files)
        """
        logger.info(f"Starting vector store migration from {vector_store_dir}")
        
        def is_vector_store_file(file_path: Path) -> bool:
            return file_path.name in ['index.faiss', 'index.pkl']
        
        return self.upload_directory(vector_store_dir, 'vector_store', is_vector_store_file)
    
    def migrate_config_files(self, config_dir: str = './config') -> Tuple[int, int]:
        """
        Migrate configuration files to S3
        
        Args:
            config_dir: Local config directory path
            
        Returns:
            Tuple[int, int]: (successful_uploads, total_files)
        """
        logger.info(f"Starting config files migration from {config_dir}")
        
        def is_config_file(file_path: Path) -> bool:
            return file_path.suffix in ['.py', '.json', '.yaml', '.yml']
        
        return self.upload_directory(config_dir, 'config', is_config_file)
    
    def verify_migration(self, local_dir: str, s3_prefix: str) -> bool:
        """
        Verify that all files were migrated successfully
        
        Args:
            local_dir: Local directory path
            s3_prefix: S3 prefix to check
            
        Returns:
            bool: True if migration is verified, False otherwise
        """
        logger.info(f"Verifying migration: {local_dir} -> s3://{self.bucket_name}/{s3_prefix}")
        
        local_path = Path(local_dir)
        if not local_path.exists():
            logger.warning(f"Local directory does not exist: {local_dir}")
            return True
        
        # Get list of local files
        local_files = set()
        for file_path in local_path.rglob('*'):
            if file_path.is_file():
                local_files.add(str(file_path.relative_to(local_path)))
        
        # Get list of S3 objects
        s3_files = set()
        paginator = self.s3_client.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=self.bucket_name, Prefix=s3_prefix):
            if 'Contents' in page:
                for obj in page['Contents']:
                    # Remove prefix from S3 key
                    s3_key = obj['Key']
                    if s3_key.startswith(s3_prefix + '/'):
                        s3_key = s3_key[len(s3_prefix + '/'):]
                    s3_files.add(s3_key)
        
        # Compare files
        missing_files = local_files - s3_files
        extra_files = s3_files - local_files
        
        if missing_files:
            logger.error(f"Missing files in S3: {missing_files}")
            return False
        
        if extra_files:
            logger.warning(f"Extra files in S3: {extra_files}")
        
        logger.info(f"Migration verified: {len(local_files)} files in both locations")
        return True
    
    def generate_migration_report(self, results: dict) -> str:
        """
        Generate a migration report
        
        Args:
            results: Dictionary with migration results
            
        Returns:
            str: Migration report
        """
        report = []
        report.append("=" * 60)
        report.append("RAG PDF Chatbot - S3 Migration Report")
        report.append("=" * 60)
        report.append(f"Timestamp: {datetime.now().isoformat()}")
        report.append(f"Bucket: {self.bucket_name}")
        report.append(f"Region: {self.region}")
        report.append("")
        
        total_successful = 0
        total_files = 0
        
        for category, (successful, total) in results.items():
            total_successful += successful
            total_files += total
            status = "✅" if successful == total else "⚠️"
            report.append(f"{status} {category}: {successful}/{total} files")
        
        report.append("")
        report.append(f"Total: {total_successful}/{total_files} files migrated")
        
        if total_successful == total_files:
            report.append("🎉 Migration completed successfully!")
        else:
            report.append("❌ Some files failed to migrate. Check logs for details.")
        
        return "\n".join(report)

def main():
    """Main migration function"""
    parser = argparse.ArgumentParser(
        description='Migrate RAG PDF Chatbot data to S3',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Migrate all data
  python scripts/migrate-to-s3.py --bucket my-ragbot-bucket
  
  # Migrate only PDFs
  python scripts/migrate-to-s3.py --bucket my-ragbot-bucket --pdfs-only
  
  # Migrate with custom profile
  python scripts/migrate-to-s3.py --bucket my-ragbot-bucket --profile production
  
  # Verify migration without uploading
  python scripts/migrate-to-s3.py --bucket my-ragbot-bucket --verify-only
        """
    )
    
    parser.add_argument(
        '--bucket',
        required=True,
        help='S3 bucket name'
    )
    
    parser.add_argument(
        '--region',
        default='us-east-1',
        help='AWS region (default: us-east-1)'
    )
    
    parser.add_argument(
        '--profile',
        default='default',
        help='AWS profile name (default: default)'
    )
    
    parser.add_argument(
        '--pdfs-only',
        action='store_true',
        help='Migrate only PDF files'
    )
    
    parser.add_argument(
        '--vector-store-only',
        action='store_true',
        help='Migrate only vector store files'
    )
    
    parser.add_argument(
        '--verify-only',
        action='store_true',
        help='Verify migration without uploading'
    )
    
    parser.add_argument(
        '--pdf-dir',
        default='./data/pdfs',
        help='Local PDF directory (default: ./data/pdfs)'
    )
    
    parser.add_argument(
        '--vector-store-dir',
        default='./data/vector_store',
        help='Local vector store directory (default: ./data/vector_store)'
    )
    
    args = parser.parse_args()
    
    # Initialize migration tool
    try:
        migrator = S3MigrationTool(
            bucket_name=args.bucket,
            region=args.region,
            profile=args.profile
        )
    except Exception as e:
        logger.error(f"Failed to initialize S3 migration tool: {e}")
        sys.exit(1)
    
    results = {}
    
    # Verify mode
    if args.verify_only:
        logger.info("Running in verify-only mode")
        
        if not args.vector_store_only:
            pdf_ok = migrator.verify_migration(args.pdf_dir, 'pdfs')
            results['pdfs'] = ('verify', pdf_ok)
        
        if not args.pdfs_only:
            vector_ok = migrator.verify_migration(args.vector_store_dir, 'vector_store')
            results['vector_store'] = ('verify', vector_ok)
        
        # Print verification results
        print("\nVerification Results:")
        print("=" * 40)
        for category, (operation, success) in results.items():
            status = "✅ PASS" if success else "❌ FAIL"
            print(f"{status} {category}")
        
        sys.exit(0 if all(success for _, success in results.values()) else 1)
    
    # Migrate PDFs
    if not args.vector_store_only:
        logger.info("Migrating PDF files...")
        successful, total = migrator.migrate_pdfs(args.pdf_dir)
        results['pdfs'] = (successful, total)
    
    # Migrate vector store
    if not args.pdfs_only:
        logger.info("Migrating vector store files...")
        successful, total = migrator.migrate_vector_store(args.vector_store_dir)
        results['vector_store'] = (successful, total)
    
    # Generate and print report
    report = migrator.generate_migration_report(results)
    print("\n" + report)
    
    # Verify migration
    logger.info("Verifying migration...")
    verification_ok = True
    
    if not args.vector_store_only:
        verification_ok &= migrator.verify_migration(args.pdf_dir, 'pdfs')
    
    if not args.pdfs_only:
        verification_ok &= migrator.verify_migration(args.vector_store_dir, 'vector_store')
    
    if verification_ok:
        logger.info("✅ Migration verified successfully!")
        sys.exit(0)
    else:
        logger.error("❌ Migration verification failed!")
        sys.exit(1)

if __name__ == '__main__':
    from datetime import datetime
    main()