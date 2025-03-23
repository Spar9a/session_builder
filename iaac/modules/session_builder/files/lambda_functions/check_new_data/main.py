import json
from typing import Dict, Any

import boto3
import os

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    # Get environment variables
    data_lake_bucket = os.environ.get('DATA_LAKE_BUCKET')
    raw_data_path = os.environ.get('PROCESSED_FOLDER', 'raw-zone')
    
    # Initialize S3 client
    s3 = boto3.client('s3')
    
    # List objects in the date partition
    response = s3.list_objects_v2(
        Bucket=data_lake_bucket,
        Prefix=raw_data_path,
        MaxKeys=1
    )
    
    has_new_data = False
    # If objects exist, add date to list
    if response.get('KeyCount', 0) > 0:
        has_new_data = True
    # Return data in format expected by Step Functions workflow
    return {
        'hasNewData': has_new_data
    }