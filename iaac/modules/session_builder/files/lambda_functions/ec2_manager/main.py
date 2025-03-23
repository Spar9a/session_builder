import json
from typing import Dict, Any

import boto3
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables

def start_ec2(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Start EC2 instances for Spark processing
    """
    logger.info("Starting Spark instances")
    MASTER_INSTANCE_ID = os.environ['MASTER_INSTANCE_ID']
    WORKER_INSTANCE_IDS = json.loads(os.environ['WORKER_INSTANCE_IDS'])
    
    try:
        # Initialize EC2 client
        ec2 = boto3.client('ec2')
        
        # Collect all instance IDs
        instance_ids = [MASTER_INSTANCE_ID] + WORKER_INSTANCE_IDS
        
        # Check instance statuses
        response = ec2.describe_instances(
            InstanceIds=instance_ids
        )
        
        # Filter instances that are not running
        instances_to_start = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                if instance['State']['Name'] != 'running':
                    instances_to_start.append(instance['InstanceId'])
        
        if instances_to_start:
            # Start instances
            logger.info(f"Starting instances: {instances_to_start}")
            ec2.start_instances(
                InstanceIds=instances_to_start
            )
        else:
            logger.info("All instances are already running")
        
        # Return result
        return {
            'instancesStarted': len(instances_to_start),
            'instanceIds': instances_to_start,
            'timestamp': context.invoked_function_arn
        }
        
    except Exception as e:
        logger.error(f"Error starting EC2 instances: {str(e)}")
        raise e

def check_status(event, context) -> Dict[str, Any]:
    """
    Check if data processing is complete
    """
    DATA_LAKE_BUCKET = os.environ['DATA_LAKE_BUCKET']
    PROCESSED_FOLDER = os.environ['PROCESSED_FOLDER']
    
    logger.info(f"Checking processing status in {DATA_LAKE_BUCKET}")
    
    try:
        # Initialize S3 client
        s3 = boto3.client('s3')
        
        # Get the timestamp from the event
        timestamp = event.get('timestamp', '')
        
        # Check for completion marker in the processed bucket
        marker_key = f"{PROCESSED_FOLDER}/complete_{timestamp.split(':')[-1]}.json"
        
        try:
            # Check if the completion marker exists
            s3.head_object(
                Bucket=DATA_LAKE_BUCKET,
                Key=marker_key
            )
            processing_complete = True
            logger.info(f"Processing complete marker found: {marker_key}")
        except s3.exceptions.ClientError as e:
            # If the object doesn't exist, processing is not complete
            if e.response['Error']['Code'] == '404':
                processing_complete = False
                logger.info(f"Processing not complete, marker not found: {marker_key}")
            else:
                raise
        
        # Return result
        return {
            'processingComplete': processing_complete,
            'timestamp': context.invoked_function_arn
        }
        
    except Exception as e:
        logger.error(f"Error checking processing status: {str(e)}")
        raise e

def stop_ec2(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Stop EC2 instances after Spark processing is complete
    """
    logger.info("Stopping Spark instances")
    MASTER_INSTANCE_ID = os.environ['MASTER_INSTANCE_ID']
    WORKER_INSTANCE_IDS = json.loads(os.environ['WORKER_INSTANCE_IDS'])
    
    try:
        # Initialize EC2 client
        ec2 = boto3.client('ec2')
        
        # Collect all instance IDs
        instance_ids = [MASTER_INSTANCE_ID] + WORKER_INSTANCE_IDS
        
        # Check instance statuses
        response = ec2.describe_instances(
            InstanceIds=instance_ids
        )
        
        # Filter instances that are running
        instances_to_stop = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                if instance['State']['Name'] == 'running':
                    instances_to_stop.append(instance['InstanceId'])
        
        if instances_to_stop:
            # Stop instances
            logger.info(f"Stopping instances: {instances_to_stop}")
            ec2.stop_instances(
                InstanceIds=instances_to_stop
            )
        else:
            logger.info("No instances are running")
        
        # Return result
        return {
            'instancesStopped': len(instances_to_stop),
            'instanceIds': instances_to_stop,
            'timestamp': context.invoked_function_arn
        }
        
    except Exception as e:
        logger.error(f"Error stopping EC2 instances: {str(e)}")
        raise e