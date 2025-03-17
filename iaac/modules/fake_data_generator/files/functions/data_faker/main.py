from faker import Faker
import random
import polars as pl
import uuid
import os
from datetime import datetime, timedelta
import hashlib

# Initialize Faker
fake = Faker()

# Set up constants
NUM_USERS = int(os.environ.get('NUM_USERS', '100'))
ROWS_PER_FILE = int(os.environ.get('ROWS_PER_FILE', '1000'))  # Number of rows in each file
NUM_FILES_PER_DAY = int(os.environ.get('NUM_FILES_PER_DAY', '3'))  # Number of files to generate per API day
NUM_API_DAYS = int(os.environ.get('NUM_API_DAYS', '10'))  # Number of API days to generate
MAX_DAYS_BACKWARD = int(os.environ.get('MAX_DAYS_BACKWARD', '5'))  # Maximum number of days backward for data in a file
S3_BUCKET_NAME= os.environ.get('S3_BUCKET_NAME', 'user-events')
S3_FOLDER_NAME= os.environ.get('S3_INPUT_FOLDER', 'raw-data')

PRODUCTS = ['VS', 'PY', 'IJ', 'WS', 'PH', 'AN', 'CL']  # Example IDE codes
USER_EVENTS = ['a', 'b', 'c']  # User action event IDs
SYSTEM_EVENTS = ['d', 'e', 'f', 'g', 'h']  # System event IDs

# Generate user IDs
user_ids = [str(uuid.uuid4()) for _ in range(NUM_USERS)]

# Function to generate a random timestamp between two dates
def random_timestamp(start_date, end_date):
    time_difference = end_date - start_date
    random_days = random.random() * time_difference.days
    random_seconds = random.randint(0, 24 * 60 * 60 - 1)
    return start_date + timedelta(days=random_days, seconds=random_seconds)

# Function to generate a unique hash
def generate_hash(seed):
    return hashlib.md5(str(seed).encode()).hexdigest()[:8]

# Function to upload a file to S3
def upload_to_s3(df, file_name):
    try:

        df.write_parquet(f"s3://{S3_BUCKET_NAME}/{S3_FOLDER_NAME}/{file_name}.parquet")
    
        return True
    except Exception as e:
        print(f"Error uploading {file_name} to S3: {str(e)}")
        return False


# Function to generate one parquet file and upload to s3
def generate_parquet_file(api_date, file_index) -> str:
    oldest_date = api_date - timedelta(days=MAX_DAYS_BACKWARD)
    
    # Generate file name
    file_hash = generate_hash(f"{api_date}_{file_index}")
    file_name = f"{api_date.strftime('%Y-%m-%d')}_{file_hash}"
    
    # Generate data for this file
    data = []
    for _ in range(ROWS_PER_FILE):
        user_id = random.choice(user_ids)
        
        # Determine if it's a user action or system event
        if random.random() < 0.7:  # 70% chance of user action
            event_id = random.choice(USER_EVENTS)
        else:
            event_id = random.choice(SYSTEM_EVENTS)
        
        # Generate timestamp between oldest_date and api_date
        timestamp = random_timestamp(oldest_date, api_date)
        product_code = random.choice(PRODUCTS)
        
        data.append({
            'user_id': user_id,
            'event_id': event_id,
            'timestamp': timestamp,
            'product_code': product_code
        })
    
    # Create DataFrame and save as parquet
    success = upload_to_s3(pl.DataFrame(data), file_name)
    return file_name if success else None
    

# Main function to generate all files
def generate_all_data():
    # Start date for the last API day
    last_api_date = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    
    files_generated = []
    
    # Generate files for each API day
    for day_offset in range(NUM_API_DAYS):
        api_date = last_api_date - timedelta(days=day_offset)
        
        for file_idx in range(NUM_FILES_PER_DAY):
            file_name = generate_parquet_file(api_date, file_idx)
            if file_name:
                files_generated.append(file_name)
    
    print(f"Generated {len(files_generated)} parquet files.")
    print("Files generated:")
    for file in files_generated[:5]:
        print(f"  - {file}")

    if len(files_generated) > 5:
        print(f"  ... and {len(files_generated) - 5} more files")


def lambda_handler(event, context):
    try:
        # Generate the data
        generate_all_data()
        
        return {
            'statusCode': 200,
            'body': 'Data generation completed successfully'
        }
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': f'Error generating data: {str(e)}'
        }

if __name__ == "__main__":
    generate_all_data()