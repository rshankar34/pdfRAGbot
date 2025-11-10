"""
AWS Configuration Module for RAG PDF Chatbot
This module provides AWS-specific configuration and utilities
"""

import os
import json
import logging
from typing import Optional, Dict, Any
from pathlib import Path

import boto3
from botocore.exceptions import ClientError, BotoCoreError

# Configure logging
logger = logging.getLogger(__name__)

class AWSConfig:
    """AWS Configuration Manager for RAG PDF Chatbot"""
    
    def __init__(self):
        """Initialize AWS configuration"""
        self.region = os.getenv('AWS_REGION', 'us-east-1')
        self.profile = os.getenv('AWS_PROFILE', 'default')
        self.s3_bucket = os.getenv('S3_BUCKET', '')
        self.efs_mount_point = os.getenv('EFS_MOUNT_POINT', '/mnt/efs')
        self.secret_name = os.getenv('SECRET_NAME', 'ragbot/openai-api-key')
        
        # Initialize AWS clients
        self._s3_client = None
        self._secrets_client = None
        self._ssm_client = None
        
        # Configuration cache
        self._config_cache = {}
        
    @property
    def s3_client(self) -> boto3.client:
        """Get S3 client"""
        if self._s3_client is None:
            session = boto3.session.Session()
            self._s3_client = session.client(
                service_name='s3',
                region_name=self.region
            )
        return self._s3_client
    
    @property
    def secrets_client(self) -> boto3.client:
        """Get Secrets Manager client"""
        if self._secrets_client is None:
            session = boto3.session.Session()
            self._secrets_client = session.client(
                service_name='secretsmanager',
                region_name=self.region
            )
        return self._secrets_client
    
    @property
    def ssm_client(self) -> boto3.client:
        """Get Systems Manager client"""
        if self._ssm_client is None:
            session = boto3.session.Session()
            self._ssm_client = session.client(
                service_name='ssm',
                region_name=self.region
            )
        return self._ssm_client
    
    def get_openai_api_key(self) -> Optional[str]:
        """
        Retrieve OpenAI API key from AWS Secrets Manager
        
        Returns:
            str: OpenAI API key or None if not found
        """
        try:
            response = self.secrets_client.get_secret_value(
                SecretId=self.secret_name
            )
            
            if 'SecretString' in response:
                secret = json.loads(response['SecretString'])
                return secret.get('OPENAI_API_KEY')
            else:
                logger.error("Secret is not in string format")
                return None
                
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'ResourceNotFoundException':
                logger.error(f"Secret {self.secret_name} not found")
            elif error_code == 'InvalidRequestException':
                logger.error(f"Invalid request for secret {self.secret_name}")
            elif error_code == 'InvalidParameterException':
                logger.error(f"Invalid parameter for secret {self.secret_name}")
            else:
                logger.error(f"Error retrieving secret: {e}")
            return None
        except Exception as e:
            logger.error(f"Unexpected error retrieving secret: {e}")
            return None
    
    def get_parameter(self, parameter_name: str, with_decryption: bool = False) -> Optional[str]:
        """
        Get parameter from AWS Systems Manager Parameter Store
        
        Args:
            parameter_name: Name of the parameter
            with_decryption: Whether to decrypt the parameter value
            
        Returns:
            str: Parameter value or None if not found
        """
        try:
            response = self.ssm_client.get_parameter(
                Name=parameter_name,
                WithDecryption=with_decryption
            )
            return response['Parameter']['Value']
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'ParameterNotFound':
                logger.warning(f"Parameter {parameter_name} not found")
            else:
                logger.error(f"Error retrieving parameter {parameter_name}: {e}")
            return None
        except Exception as e:
            logger.error(f"Unexpected error retrieving parameter {parameter_name}: {e}")
            return None
    
    def put_parameter(self, parameter_name: str, value: str, parameter_type: str = 'String', 
                     overwrite: bool = False) -> bool:
        """
        Put parameter in AWS Systems Manager Parameter Store
        
        Args:
            parameter_name: Name of the parameter
            value: Parameter value
            parameter_type: Type of parameter (String, StringList, SecureString)
            overwrite: Whether to overwrite existing parameter
            
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            self.ssm_client.put_parameter(
                Name=parameter_name,
                Value=value,
                Type=parameter_type,
                Overwrite=overwrite
            )
            logger.info(f"Parameter {parameter_name} stored successfully")
            return True
        except ClientError as e:
            logger.error(f"Error storing parameter {parameter_name}: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error storing parameter {parameter_name}: {e}")
            return False
    
    def upload_file_to_s3(self, local_path: str, s3_key: str, 
                         extra_args: Optional[Dict[str, Any]] = None) -> bool:
        """
        Upload file to S3
        
        Args:
            local_path: Local file path
            s3_key: S3 key (path in bucket)
            extra_args: Additional arguments for upload
            
        Returns:
            bool: True if successful, False otherwise
        """
        if not self.s3_bucket:
            logger.error("S3 bucket not configured")
            return False
        
        try:
            if extra_args is None:
                extra_args = {}
            
            self.s3_client.upload_file(
                local_path,
                self.s3_bucket,
                s3_key,
                ExtraArgs=extra_args
            )
            logger.info(f"File uploaded to s3://{self.s3_bucket}/{s3_key}")
            return True
        except ClientError as e:
            logger.error(f"Error uploading file to S3: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error uploading file to S3: {e}")
            return False
    
    def download_file_from_s3(self, s3_key: str, local_path: str) -> bool:
        """
        Download file from S3
        
        Args:
            s3_key: S3 key (path in bucket)
            local_path: Local file path
            
        Returns:
            bool: True if successful, False otherwise
        """
        if not self.s3_bucket:
            logger.error("S3 bucket not configured")
            return False
        
        try:
            # Create directory if it doesn't exist
            Path(local_path).parent.mkdir(parents=True, exist_ok=True)
            
            self.s3_client.download_file(
                self.s3_bucket,
                s3_key,
                local_path
            )
            logger.info(f"File downloaded from s3://{self.s3_bucket}/{s3_key}")
            return True
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == '404':
                logger.warning(f"File s3://{self.s3_bucket}/{s3_key} not found")
            else:
                logger.error(f"Error downloading file from S3: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error downloading file from S3: {e}")
            return False
    
    def list_s3_objects(self, prefix: str = '') -> list:
        """
        List objects in S3 bucket
        
        Args:
            prefix: Prefix to filter objects
            
        Returns:
            list: List of object keys
        """
        if not self.s3_bucket:
            logger.error("S3 bucket not configured")
            return []
        
        try:
            objects = []
            paginator = self.s3_client.get_paginator('list_objects_v2')
            
            for page in paginator.paginate(Bucket=self.s3_bucket, Prefix=prefix):
                if 'Contents' in page:
                    objects.extend([obj['Key'] for obj in page['Contents']])
            
            return objects
        except ClientError as e:
            logger.error(f"Error listing S3 objects: {e}")
            return []
        except Exception as e:
            logger.error(f"Unexpected error listing S3 objects: {e}")
            return []
    
    def sync_to_s3(self, local_dir: str, s3_prefix: str) -> bool:
        """
        Sync local directory to S3
        
        Args:
            local_dir: Local directory path
            s3_prefix: S3 prefix (folder path)
            
        Returns:
            bool: True if successful, False otherwise
        """
        if not self.s3_bucket:
            logger.error("S3 bucket not configured")
            return False
        
        try:
            import subprocess
            cmd = [
                'aws', 's3', 'sync',
                local_dir,
                f"s3://{self.s3_bucket}/{s3_prefix}",
                '--region', self.region
            ]
            
            if self.profile != 'default':
                cmd.extend(['--profile', self.profile])
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"Synced {local_dir} to s3://{self.s3_bucket}/{s3_prefix}")
                return True
            else:
                logger.error(f"Sync failed: {result.stderr}")
                return False
        except Exception as e:
            logger.error(f"Error syncing to S3: {e}")
            return False
    
    def sync_from_s3(self, s3_prefix: str, local_dir: str) -> bool:
        """
        Sync from S3 to local directory
        
        Args:
            s3_prefix: S3 prefix (folder path)
            local_dir: Local directory path
            
        Returns:
            bool: True if successful, False otherwise
        """
        if not self.s3_bucket:
            logger.error("S3 bucket not configured")
            return False
        
        try:
            import subprocess
            cmd = [
                'aws', 's3', 'sync',
                f"s3://{self.s3_bucket}/{s3_prefix}",
                local_dir,
                '--region', self.region
            ]
            
            if self.profile != 'default':
                cmd.extend(['--profile', self.profile])
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"Synced s3://{self.s3_bucket}/{s3_prefix} to {local_dir}")
                return True
            else:
                logger.error(f"Sync failed: {result.stderr}")
                return False
        except Exception as e:
            logger.error(f"Error syncing from S3: {e}")
            return False
    
    def test_aws_connectivity(self) -> bool:
        """
        Test AWS connectivity
        
        Returns:
            bool: True if connectivity is working, False otherwise
        """
        try:
            # Test S3 access
            if self.s3_bucket:
                self.s3_client.list_buckets()
            
            # Test Secrets Manager access
            self.secrets_client.list_secrets(MaxResults=1)
            
            logger.info("AWS connectivity test passed")
            return True
        except Exception as e:
            logger.error(f"AWS connectivity test failed: {e}")
            return False
    
    def get_cost_estimate(self) -> Dict[str, float]:
        """
        Get estimated monthly costs for AWS resources
        
        Returns:
            dict: Cost estimates for each service
        """
        # These are rough estimates based on typical usage
        estimates = {
            'ec2_t2_micro': 0.0,  # Free tier
            's3_storage': 0.0,    # Free tier (5GB)
            's3_requests': 0.0,   # Minimal for typical usage
            'efs_storage': 0.0,   # Free tier (5GB)
            'secrets_manager': 0.4,  # $0.40 per secret per month
            'data_transfer': 0.0, # Minimal for typical usage
            'cloudwatch': 0.0     # Free tier
        }
        
        return estimates

# Global instance
_aws_config = None

def get_aws_config() -> AWSConfig:
    """Get global AWS configuration instance"""
    global _aws_config
    if _aws_config is None:
        _aws_config = AWSConfig()
    return _aws_config

# Convenience functions
def get_openai_api_key() -> Optional[str]:
    """Convenience function to get OpenAI API key"""
    return get_aws_config().get_openai_api_key()

def upload_to_s3(local_path: str, s3_key: str, **kwargs) -> bool:
    """Convenience function to upload to S3"""
    return get_aws_config().upload_file_to_s3(local_path, s3_key, **kwargs)

def download_from_s3(s3_key: str, local_path: str) -> bool:
    """Convenience function to download from S3"""
    return get_aws_config().download_file_from_s3(s3_key, local_path)

def sync_to_s3(local_dir: str, s3_prefix: str) -> bool:
    """Convenience function to sync to S3"""
    return get_aws_config().sync_to_s3(local_dir, s3_prefix)

def sync_from_s3(s3_prefix: str, local_dir: str) -> bool:
    """Convenience function to sync from S3"""
    return get_aws_config().sync_from_s3(s3_prefix, local_dir)