#!/usr/bin/env python3
"""
Backup Script: Backup vector store and important data to S3
This script creates automated backups of the vector store and configuration
"""

import os
import sys
import json
import logging
import argparse
import shutil
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Any
import boto3
from botocore.exceptions import ClientError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class BackupManager:
    """Manages backups of RAG PDF Chatbot data to S3"""
    
    def __init__(self, bucket_name: str, region: str = 'us-east-1', profile: str = 'default'):
        """
        Initialize backup manager
        
        Args:
            bucket_name: S3 bucket name for backups
            region: AWS region
            profile: AWS profile name
        """
        self.bucket_name = bucket_name
        self.region = region
        self.profile = profile
        
        # Initialize AWS session
        session = boto3.session.Session(profile_name=profile)
        self.s3_client = session.client('s3', region_name=region)
        
        logger.info(f"Initialized backup manager for bucket: {bucket_name}")
    
    def create_backup(self, source_dir: str, backup_name: str, 
                     retention_days: int = 7) -> Optional[str]:
        """
        Create a backup of a directory to S3
        
        Args:
            source_dir: Local directory to backup
            backup_name: Name of the backup
            retention_days: Number of days to keep the backup
            
        Returns:
            str: Backup S3 prefix or None if failed
        """
        source_path = Path(source_dir)
        
        if not source_path.exists():
            logger.error(f"Source directory does not exist: {source_dir}")
            return None
        
        if not source_path.is_dir():
            logger.error(f"Source path is not a directory: {source_dir}")
            return None
        
        # Create timestamped backup prefix
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_prefix = f"backups/{backup_name}/{timestamp}"
        
        logger.info(f"Creating backup: {backup_name} -> s3://{self.bucket_name}/{backup_prefix}")
        
        successful = 0
        total = 0
        
        # Upload all files in the directory
        for file_path in source_path.rglob('*'):
            if not file_path.is_file():
                continue
            
            total += 1
            
            # Calculate relative path and S3 key
            relative_path = file_path.relative_to(source_path)
            s3_key = f"{backup_prefix}/{relative_path}"
            
            # Upload file
            try:
                extra_args = {}
                if file_path.suffix == '.pdf':
                    extra_args['ContentType'] = 'application/pdf'
                
                self.s3_client.upload_file(
                    str(file_path),
                    self.bucket_name,
                    s3_key,
                    ExtraArgs=extra_args
                )
                
                successful += 1
                logger.debug(f"Backed up: {file_path.name}")
                
            except ClientError as e:
                logger.error(f"Error backing up {file_path}: {e}")
            except Exception as e:
                logger.error(f"Unexpected error backing up {file_path}: {e}")
        
        logger.info(f"Backup completed: {successful}/{total} files")
        
        if successful == 0 and total > 0:
            logger.error("Backup failed: no files were uploaded")
            return None
        
        # Create backup metadata
        self._create_backup_metadata(backup_name, timestamp, successful, total, retention_days)
        
        return backup_prefix
    
    def _create_backup_metadata(self, backup_name: str, timestamp: str, 
                               file_count: int, total_files: int, retention_days: int):
        """Create backup metadata file"""
        metadata = {
            'backup_name': backup_name,
            'timestamp': timestamp,
            'created_at': datetime.now().isoformat(),
            'file_count': file_count,
            'total_files': total_files,
            'retention_days': retention_days,
            'status': 'completed' if file_count == total_files else 'partial'
        }
        
        metadata_key = f"backups/{backup_name}/{timestamp}/_backup_metadata.json"
        
        try:
            self.s3_client.put_object(
                Bucket=self.bucket_name,
                Key=metadata_key,
                Body=json.dumps(metadata, indent=2),
                ContentType='application/json'
            )
            logger.info(f"Backup metadata created: {metadata_key}")
        except Exception as e:
            logger.error(f"Error creating backup metadata: {e}")
    
    def backup_vector_store(self, vector_store_dir: str = './data/vector_store',
                          retention_days: int = 7) -> Optional[str]:
        """
        Backup vector store to S3
        
        Args:
            vector_store_dir: Local vector store directory
            retention_days: Number of days to keep the backup
            
        Returns:
            str: Backup S3 prefix or None if failed
        """
        logger.info("Starting vector store backup")
        return self.create_backup(vector_store_dir, 'vector_store', retention_days)
    
    def backup_pdfs(self, pdf_dir: str = './data/pdfs',
                   retention_days: int = 7) -> Optional[str]:
        """
        Backup PDFs to S3
        
        Args:
            pdf_dir: Local PDF directory
            retention_days: Number of days to keep the backup
            
        Returns:
            str: Backup S3 prefix or None if failed
        """
        logger.info("Starting PDFs backup")
        return self.create_backup(pdf_dir, 'pdfs', retention_days)
    
    def backup_config(self, config_dir: str = './config',
                     retention_days: int = 30) -> Optional[str]:
        """
        Backup configuration files to S3
        
        Args:
            config_dir: Local config directory
            retention_days: Number of days to keep the backup
            
        Returns:
            str: Backup S3 prefix or None if failed
        """
        logger.info("Starting config backup")
        return self.create_backup(config_dir, 'config', retention_days)
    
    def create_full_backup(self, base_dir: str = '.',
                          retention_days: int = 7) -> Dict[str, Optional[str]]:
        """
        Create a full backup of all important data
        
        Args:
            base_dir: Base directory of the application
            retention_days: Number of days to keep the backup
            
        Returns:
            dict: Dictionary with backup results for each component
        """
        logger.info("Starting full backup")
        
        base_path = Path(base_dir)
        results = {}
        
        # Backup vector store
        vector_store_dir = base_path / 'data' / 'vector_store'
        if vector_store_dir.exists():
            results['vector_store'] = self.backup_vector_store(
                str(vector_store_dir), retention_days
            )
        else:
            logger.warning(f"Vector store directory not found: {vector_store_dir}")
            results['vector_store'] = None
        
        # Backup PDFs
        pdf_dir = base_path / 'data' / 'pdfs'
        if pdf_dir.exists():
            results['pdfs'] = self.backup_pdfs(str(pdf_dir), retention_days)
        else:
            logger.warning(f"PDFs directory not found: {pdf_dir}")
            results['pdfs'] = None
        
        # Backup config
        config_dir = base_path / 'config'
        if config_dir.exists():
            results['config'] = self.backup_config(str(config_dir), retention_days * 4)
        else:
            logger.warning(f"Config directory not found: {config_dir}")
            results['config'] = None
        
        # Backup important files
        important_files = ['.env', 'requirements.txt', 'app.py']
        for file_name in important_files:
            file_path = base_path / file_name
            if file_path.exists():
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                s3_key = f"backups/full/{timestamp}/{file_name}"
                
                try:
                    self.s3_client.upload_file(
                        str(file_path),
                        self.bucket_name,
                        s3_key
                    )
                    logger.info(f"Backed up: {file_name}")
                except Exception as e:
                    logger.error(f"Error backing up {file_name}: {e}")
        
        logger.info("Full backup completed")
        return results
    
    def list_backups(self, backup_name: str = None) -> list:
        """
        List available backups
        
        Args:
            backup_name: Optional backup name filter
            
        Returns:
            list: List of backup information
        """
        prefix = f"backups/{backup_name}" if backup_name else "backups/"
        
        backups = []
        paginator = self.s3_client.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=self.bucket_name, Prefix=prefix, Delimiter='/'):
            if 'CommonPrefixes' in page:
                for prefix_info in page['CommonPrefixes']:
                    backup_prefix = prefix_info['Prefix']
                    
                    # Extract backup name and timestamp from prefix
                    parts = backup_prefix.strip('/').split('/')
                    if len(parts) >= 3:
                        name = parts[1]
                        timestamp = parts[2]
                        
                        # Try to get metadata
                        metadata_key = f"{backup_prefix}_backup_metadata.json"
                        try:
                            response = self.s3_client.get_object(
                                Bucket=self.bucket_name,
                                Key=metadata_key
                            )
                            metadata = json.loads(response['Body'].read())
                        except:
                            metadata = {'status': 'unknown'}
                        
                        backups.append({
                            'name': name,
                            'timestamp': timestamp,
                            'prefix': backup_prefix,
                            'metadata': metadata
                        })
        
        # Sort by timestamp (newest first)
        backups.sort(key=lambda x: x['timestamp'], reverse=True)
        
        return backups
    
    def restore_backup(self, backup_prefix: str, restore_dir: str) -> bool:
        """
        Restore a backup from S3 to local directory
        
        Args:
            backup_prefix: S3 prefix of the backup to restore
            restore_dir: Local directory to restore to
            
        Returns:
            bool: True if successful, False otherwise
        """
        logger.info(f"Restoring backup: s3://{self.bucket_name}/{backup_prefix} -> {restore_dir}")
        
        restore_path = Path(restore_dir)
        restore_path.mkdir(parents=True, exist_ok=True)
        
        successful = 0
        total = 0
        
        # List all objects in the backup
        paginator = self.s3_client.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=self.bucket_name, Prefix=backup_prefix):
            if 'Contents' in page:
                for obj in page['Contents']:
                    s3_key = obj['Key']
                    
                    # Skip metadata file
                    if s3_key.endswith('_backup_metadata.json'):
                        continue
                    
                    total += 1
                    
                    # Calculate local path
                    relative_path = s3_key[len(backup_prefix):].lstrip('/')
                    local_path = restore_path / relative_path
                    
                    # Create directory if needed
                    local_path.parent.mkdir(parents=True, exist_ok=True)
                    
                    # Download file
                    try:
                        self.s3_client.download_file(
                            self.bucket_name,
                            s3_key,
                            str(local_path)
                        )
                        successful += 1
                        logger.debug(f"Restored: {relative_path}")
                    except Exception as e:
                        logger.error(f"Error restoring {s3_key}: {e}")
        
        logger.info(f"Restore completed: {successful}/{total} files")
        return successful > 0
    
    def cleanup_old_backups(self, backup_name: str, retention_days: int = 7):
        """
        Clean up old backups based on retention policy
        
        Args:
            backup_name: Name of the backup
            retention_days: Number of days to keep backups
        """
        logger.info(f"Cleaning up old backups for {backup_name} (retention: {retention_days} days)")
        
        cutoff_date = datetime.now().timestamp() - (retention_days * 24 * 60 * 60)
        
        backups = self.list_backups(backup_name)
        deleted_count = 0
        
        for backup in backups:
            # Parse timestamp
            try:
                timestamp = datetime.strptime(backup['timestamp'], '%Y%m%d_%H%M%S')
                if timestamp.timestamp() < cutoff_date:
                    # Delete old backup
                    prefix = backup['prefix']
                    
                    # List all objects to delete
                    paginator = self.s3_client.get_paginator('list_objects_v2')
                    objects_to_delete = []
                    
                    for page in paginator.paginate(Bucket=self.bucket_name, Prefix=prefix):
                        if 'Contents' in page:
                            objects_to_delete.extend([
                                {'Key': obj['Key']} for obj in page['Contents']
                            ])
                    
                    # Delete objects
                    if objects_to_delete:
                        self.s3_client.delete_objects(
                            Bucket=self.bucket_name,
                            Delete={'Objects': objects_to_delete}
                        )
                    
                    deleted_count += 1
                    logger.info(f"Deleted old backup: {backup['timestamp']}")
                    
            except Exception as e:
                logger.error(f"Error processing backup {backup['timestamp']}: {e}")
        
        logger.info(f"Cleanup completed: {deleted_count} old backups deleted")

def main():
    """Main backup function"""
    parser = argparse.ArgumentParser(
        description='Backup RAG PDF Chatbot data to S3',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create full backup
  python scripts/backup-vector-store.py --bucket my-ragbot-bucket --full
  
  # Backup only vector store
  python scripts/backup-vector-store.py --bucket my-ragbot-bucket --vector-store
  
  # Backup with custom retention
  python scripts/backup-vector-store.py --bucket my-ragbot-bucket --full --retention-days 14
  
  # List available backups
  python scripts/backup-vector-store.py --bucket my-ragbot-bucket --list
  
  # Restore a backup
  python scripts/backup-vector-store.py --bucket my-ragbot-bucket --restore 20231109_143022 --restore-dir ./restore
  
  # Cleanup old backups
  python scripts/backup-vector-store.py --bucket my-ragbot-bucket --cleanup --retention-days 7
        """
    )
    
    parser.add_argument(
        '--bucket',
        required=True,
        help='S3 bucket name for backups'
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
        '--full',
        action='store_true',
        help='Create full backup of all data'
    )
    
    parser.add_argument(
        '--vector-store',
        action='store_true',
        help='Backup vector store only'
    )
    
    parser.add_argument(
        '--pdfs',
        action='store_true',
        help='Backup PDFs only'
    )
    
    parser.add_argument(
        '--config',
        action='store_true',
        help='Backup config only'
    )
    
    parser.add_argument(
        '--list',
        action='store_true',
        help='List available backups'
    )
    
    parser.add_argument(
        '--restore',
        help='Restore backup with specified timestamp'
    )
    
    parser.add_argument(
        '--restore-dir',
        default='./restore',
        help='Directory to restore to (default: ./restore)'
    )
    
    parser.add_argument(
        '--cleanup',
        action='store_true',
        help='Clean up old backups'
    )
    
    parser.add_argument(
        '--retention-days',
        type=int,
        default=7,
        help='Retention days for backups (default: 7)'
    )
    
    parser.add_argument(
        '--vector-store-dir',
        default='./data/vector_store',
        help='Local vector store directory (default: ./data/vector_store)'
    )
    
    parser.add_argument(
        '--pdf-dir',
        default='./data/pdfs',
        help='Local PDF directory (default: ./data/pdfs)'
    )
    
    args = parser.parse_args()
    
    # Initialize backup manager
    try:
        backup_manager = BackupManager(
            bucket_name=args.bucket,
            region=args.region,
            profile=args.profile
        )
    except Exception as e:
        logger.error(f"Failed to initialize backup manager: {e}")
        sys.exit(1)
    
    # List backups
    if args.list:
        backups = backup_manager.list_backups()
        
        print("\nAvailable Backups:")
        print("=" * 80)
        
        if not backups:
            print("No backups found")
        else:
            current_backup = None
            for backup in backups:
                if current_backup != backup['name']:
                    current_backup = backup['name']
                    print(f"\n{backup['name']}:")
                
                metadata = backup['metadata']
                status = metadata.get('status', 'unknown')
                file_count = metadata.get('file_count', 0)
                total_files = metadata.get('total_files', 0)
                
                print(f"  {backup['timestamp']} - {status} - {file_count}/{total_files} files")
        
        sys.exit(0)
    
    # Restore backup
    if args.restore:
        # Find the backup
        backups = backup_manager.list_backups()
        backup_prefix = None
        
        for backup in backups:
            if backup['timestamp'] == args.restore:
                backup_prefix = backup['prefix']
                break
        
        if not backup_prefix:
            logger.error(f"Backup not found: {args.restore}")
            sys.exit(1)
        
        # Restore the backup
        if backup_manager.restore_backup(backup_prefix, args.restore_dir):
            logger.info(f"✅ Backup restored successfully to {args.restore_dir}")
            sys.exit(0)
        else:
            logger.error("❌ Backup restore failed")
            sys.exit(1)
    
    # Cleanup old backups
    if args.cleanup:
        backup_manager.cleanup_old_backups('vector_store', args.retention_days)
        backup_manager.cleanup_old_backups('pdfs', args.retention_days)
        backup_manager.cleanup_old_backups('config', args.retention_days * 4)
        sys.exit(0)
    
    # Create backups
    if args.full:
        # Full backup
        results = backup_manager.create_full_backup('.', args.retention_days)
        
        # Print results
        print("\nBackup Results:")
        print("=" * 40)
        for component, prefix in results.items():
            if prefix:
                print(f"✅ {component}: {prefix}")
            else:
                print(f"❌ {component}: failed")
        
        sys.exit(0 if any(results.values()) else 1)
    
    # Individual backups
    if args.vector_store:
        prefix = backup_manager.backup_vector_store(args.vector_store_dir, args.retention_days)
        if prefix:
            logger.info(f"✅ Vector store backup completed: {prefix}")
            sys.exit(0)
        else:
            logger.error("❌ Vector store backup failed")
            sys.exit(1)
    
    if args.pdfs:
        prefix = backup_manager.backup_pdfs(args.pdf_dir, args.retention_days)
        if prefix:
            logger.info(f"✅ PDFs backup completed: {prefix}")
            sys.exit(0)
        else:
            logger.error("❌ PDFs backup failed")
            sys.exit(1)
    
    if args.config:
        prefix = backup_manager.backup_config('./config', args.retention_days * 4)
        if prefix:
            logger.info(f"✅ Config backup completed: {prefix}")
            sys.exit(0)
        else:
            logger.error("❌ Config backup failed")
            sys.exit(1)
    
    # If no specific option provided, show help
    parser.print_help()
    sys.exit(1)

if __name__ == '__main__':
    main()