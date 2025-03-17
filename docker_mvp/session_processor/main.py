import os
import time
import spark_session_builder as spark_builder

# Environment variables
CONTINUOUS_MODE = os.environ.get('CONTINUOUS_MODE', 'False') == 'True'

# Create necessary directories
os.makedirs(f"{spark_builder.DATA_LAKE_BUCKET}/{spark_builder.PROCESSED_DATA_FOLDER}", exist_ok=True)
os.makedirs(f"{spark_builder.DATA_LAKE_BUCKET}/{spark_builder.DELTALAKE_TABLE_FOLDER}", exist_ok=True)

def main():
    """Main entry point"""
    if CONTINUOUS_MODE:
        print("Running in continuous mode")
        while True:
            spark_builder.main()
            print(f"Sleeping for 60 seconds...")
            time.sleep(60)
    else:
        spark_builder.main()

if __name__ == "__main__":
    main()