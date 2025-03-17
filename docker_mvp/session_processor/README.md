# Spark Session Builder

## Overview

The `spark_session_builder.py` module is a core component of the session processor service that processes raw IDE usage data into structured user sessions using Apache Spark and Delta Lake. This module implements the complete data processing pipeline for identifying, reconciling, and persisting user sessions from raw event data.

## Features

- **Spark Session Configuration**: Creates and configures a Spark session with Delta Lake support
- **Session Identification**: Analyzes event timestamps and types to identify user sessions
- **Session Reconciliation**: Merges new sessions with existing ones to handle overlaps
- **Delta Lake Integration**: Efficiently stores and updates processed data using Delta Lake format
- **File Management**: Moves processed files from raw to processed folders

## Key Constants

| Constant | Default Value | Description |
|----------|---------------|-------------|
| `DATA_LAKE_BUCKET` | "data" | Base storage location |
| `RAW_DATA_FOLDER` | "raw-data" | Folder for incoming raw data |
| `PROCESSED_DATA_FOLDER` | "processed-data" | Folder for processed files |
| `DELTALAKE_TABLE_FOLDER` | "delta-table" | Folder for Delta Lake tables |
| `SESSION_TIMEOUT_SECS` | 300 (5 minutes) | Inactivity period that defines session boundaries |

## Main Functions

### `create_spark_session()`

Initializes and configures a Spark session with Delta Lake support and appropriate memory settings.

### `read_new_files(spark)`

Reads new Parquet files from the input directory and converts timestamps to the correct format.

### `identify_sessions(events_df)`

Identifies user sessions based on user activity and inactivity periods using the following rules:
- First user event for a user+product combination starts a new session
- User event after inactivity period > 5 minutes starts a new session
- User event after an IDE event (non-user event) starts a new session

### `get_session_boundaries(sessions_df, prefix)`

Calculates the minimum and maximum timestamps for each session to determine session boundaries.

### `read_existing_sessions(spark, new_sessions)`

Reads existing sessions from Delta Lake that might overlap with new sessions based on user, product, and date range.

### `reconcile_sessions(new_sessions, existing_sessions)`

Reconciles new sessions with existing ones to handle retroactive data and session overlaps using these rules:
- If a new session extends an existing session (within 5 minutes), they are merged
- If a new session precedes an existing session (within 5 minutes), they are merged
- If sessions directly overlap, the one with the earlier start time takes precedence

### `write_data_with_merge(spark, merged_data)`

Writes data to Delta table using merge operation to efficiently update existing records and insert new ones.

### `move_files(files)`

Moves processed files from the raw data folder to the processed folder to prevent reprocessing.

### `main()`

Orchestrates the complete session builder pipeline:
1. Reads new data files
2. Identifies sessions within the new data
3. Reads existing sessions that might need reconciliation
4. Reconciles with existing sessions
5. Writes data using merge operation
6. Logs statistics
7. Moves processed files

## Usage

The module can be used directly or imported by other modules:

```python
# Direct usage
python spark_session_builder.py

# Import usage
import spark_session_builder as spark_builder
spark_builder.main()
```

## Dependencies

- pyspark
- delta-spark

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATA_LAKE_BUCKET` | "data" | Base storage location |
| `RAW_DATA_FOLDER` | "raw-data" | Folder for incoming raw data |
| `PROCESSED_DATA_FOLDER` | "processed-data" | Folder for processed files |
| `DELTALAKE_TABLE_FOLDER` | "delta-table" | Folder for Delta Lake tables |

## Session Logic

The session identification logic uses a 5-minute inactivity timeout to determine session boundaries. Events are classified as either user events or IDE events, with only user events capable of starting new sessions. The module handles complex scenarios such as overlapping sessions, retroactive data, and session extensions.