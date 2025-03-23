from __future__ import annotations

import glob
import logging
import os
import shutil
from typing import TYPE_CHECKING, List

from delta.tables import DeltaTable
from pyspark.sql import SparkSession, Window
from pyspark.sql.functions import (col, collect_list, concat_ws, expr, lag,
                                   last, last_value, lit)
from pyspark.sql.functions import max as sql_max
from pyspark.sql.functions import min as sql_min
from pyspark.sql.functions import to_date, unix_timestamp, when

if TYPE_CHECKING:
    from pyspark.sql import DataFrame

DATA_LAKE_BUCKET = os.environ.get('DATA_LAKE_BUCKET', 'data')
RAW_DATA_FOLDER = os.environ.get('RAW_DATA_FOLDER', 'raw-data')
PROCESSED_DATA_FOLDER = os.environ.get('PROCESSED_DATA_FOLDER', 'processed-data')
DELTALAKE_TABLE_FOLDER = os.environ.get('DELTALAKE_TABLE_FOLDER', 'delta-table')

# Constants
USER_EVENT_IDS = ["a", "b", "c"]  # Event IDs that represent user actions
SESSION_TIMEOUT_SECS = 5 * 60  # Session timeout: 5 minutes in seconds

DELTA_TABLE_PATH = f"{DATA_LAKE_BUCKET}/{DELTALAKE_TABLE_FOLDER}"
RAW_DATA_FOLDER_PATH = f"{DATA_LAKE_BUCKET}/{RAW_DATA_FOLDER}"
PROCESSED_DATA_FOLDER_PATH = f"{DATA_LAKE_BUCKET}/{PROCESSED_DATA_FOLDER}"

logger = logging.getLogger()
logger.setLevel("INFO")

def create_spark_session() -> SparkSession:
    """Initialize and configure the Spark session with Delta Lake support."""
    return (
        SparkSession.builder
        .appName("IDE Session Builder")
        .config("spark.jars.packages", "io.delta:delta-spark_2.12:3.3.0")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config("spark.ui.enabled", "false")
        .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
        .config("spark.driver.memory", "4g")
        .getOrCreate()
    )


def read_new_files(spark: SparkSession) -> tuple[DataFrame, list[str]]:
    """Read new Parquet files from the input directory"""
    # List all parquet files in the raw data folder
    file_pattern = f"{RAW_DATA_FOLDER_PATH}/*.parquet"
    file_paths = glob.glob(file_pattern)

    if not file_paths:
        logger.warning("No new files found")
        return None

    # Read all parquet files using Spark
    raw_data = spark.read.parquet(*file_paths)

    # Ensure timestamp is in the correct format
    processed_data = raw_data.withColumn(
        "timestamp",
        unix_timestamp(col("timestamp")).cast("timestamp")
    )

    return processed_data, file_paths


def identify_sessions(events_df: DataFrame) -> DataFrame:
    """
    Identify user sessions based on user activity and inactivity periods.

    Args:
        events_df: DataFrame containing event data

    Returns:
        DataFrame: Original data with session identification columns
    """
    # Flag user events (vs IDE events)
    events_with_flags = events_df.withColumn(
        "is_user_event", col("event_id").isin(USER_EVENT_IDS)
    )

    events_with_flags = events_with_flags.withColumn(
        "user_event_flag",
        when(col("is_user_event"), col("timestamp")).otherwise(None)
    )


    # Window for looking back to find the most recent user event
    window_spec = Window.partitionBy("user_id", "product_code").orderBy("timestamp")

    events_with_diffs = events_with_flags.withColumn(
        "last_user_event_ts",
        last_value("user_event_flag", ignoreNulls=True).over(
            window_spec.rangeBetween(Window.unboundedPreceding, 0)
        )
    )

    # Now get the previous user event timestamp by using a lag on this column
    events_with_diffs = events_with_diffs.withColumn(
        "prev_user_ts",
        lag("last_user_event_ts", 1, None).over(window_spec)
    ).withColumn(
        "time_diff_seconds",
        when(col("prev_user_ts").isNotNull(),
             unix_timestamp(col("timestamp")) - unix_timestamp(col("prev_user_ts")))
        .otherwise(0)
    ).drop("user_event_flag", "last_user_event_ts")


    # Determine session boundaries based on rules:
    # 1. First event for user+product (if it's a user event)
    # 2. User event after inactivity period > 5 minutes
    sessions_df = events_with_diffs.withColumn(
        "is_new_session",
        ((col("prev_user_ts").isNull()) & col("is_user_event")) |  # First event must be user event
        ((col("time_diff_seconds") > SESSION_TIMEOUT_SECS) & col("is_user_event"))  # Timeout
    )

    # Window for assigning session start times across the session
    session_window = Window.partitionBy("user_id", "product_code") \
        .orderBy("timestamp") \
        .rowsBetween(Window.unboundedPreceding, 0)

    # Mark session start events
    sessions_with_starts = sessions_df.withColumn(
        "session_start_time",
        when(col("is_new_session"), col("timestamp")).otherwise(None)
    )

    # Propagate session start time to all events in the same session
    sessions_with_ids = sessions_with_starts.withColumn(
        "session_start",
        last(when(col("session_start_time").isNotNull(), col("session_start_time")).otherwise(None),
             ignorenulls=True).over(session_window)
    )

    # Create final session ID in format: user_id#product_code#timestamp
    final_sessions = sessions_with_ids.withColumn(
        "session_id",
        when(
            (col("session_start").isNotNull()) &
            ((col("is_new_session")) | (col("time_diff_seconds") < SESSION_TIMEOUT_SECS)),
             concat_ws("#", col("user_id"), col("product_code"),
                       unix_timestamp(col("session_start")).cast("string")))
        .otherwise(None)
    )

    # Add event date for partitioning
    final_sessions = final_sessions.withColumn(
        "event_date", col("timestamp").cast("date")
    )

    return final_sessions.select("user_id", "product_code", "event_id", "timestamp", "session_id", "event_date")


def get_session_boundaries(sessions_df: DataFrame, prefix: str) -> DataFrame:
    """
    Calculate the min and max timestamps for each session.

    Args:
        sessions_df: DataFrame with identified sessions

    Returns:
        DataFrame: Session boundaries with min/max timestamps
    """
    renamed_df = sessions_df.withColumnRenamed("session_id", f"{prefix}_session_id")


    return renamed_df.groupBy(
        "user_id", "product_code", f"{prefix}_session_id"
    ).agg(
        sql_min("timestamp").alias(f"{prefix}_session_min_time"),
        sql_max("timestamp").alias(f"{prefix}_session_max_time"),
        sql_min("event_date").alias(f"{prefix}_min_date"),
        sql_max("event_date").alias(f"{prefix}_max_date")
    )


def get_boundaries_by_product(new_user_sessions):
    """Get filter conditions based on product_code and date range with 1 day window back and forward"""
    # First, create a date column explicitly
    with_dates = new_user_sessions.withColumn("event_date", to_date(col("timestamp")))

    # Now use the explicitly created column
    dates_by_product = with_dates.select(
        "product_code",
        "event_date"
    ).distinct().groupBy("product_code").agg(
        collect_list("event_date").alias("dates")
    )

    expanded_dates = dates_by_product.withColumn(
        "expanded_dates",
        expr("""
            array_distinct(
                flatten(
                    transform(dates, date ->
                        array(date_sub(date, 1), date, date_add(date, 1))
                    )
                )
            )
        """)
    )

    filter_map = {row.product_code: row.expanded_dates for row in expanded_dates.collect()}

    filter_conditions = []
    for product_code, dates in filter_map.items():

        dates_str = ','.join([f'"{d}"' for d in dates])

        filter_conditions.append(f'((product_code == "{product_code}") and (event_date in ({dates_str})))')

    # Handle empty filter_conditions case to avoid errors
    if not filter_conditions:
        return lit(False)

    return " or ".join(filter_conditions)


def read_existing_sessions(spark: SparkSession, new_sessions: DataFrame) -> DataFrame:
    """
    Read existing sessions that might overlap with new sessions.

    Args:
        spark: Spark session
        processed_bucket: Bucket or path containing processed data
        new_sessions_boundaries: Boundaries of new sessions

    Returns:
        DataFrame: Existing sessions that might overlap with new ones
    """
    try:
        # Extract unique user+product pairs from new data for filtering
        user_product_pairs = new_sessions.select(
            "user_id", "product_code"
        ).distinct()

        # Check if delta table exists
        try:
            existing_data = DeltaTable.forPath(spark, f"{DELTA_TABLE_PATH}").toDF()
        except Exception:
            print("No existing processed data found")
            return spark.createDataFrame([], new_sessions.schema)


        product_filter = get_boundaries_by_product(new_sessions)

        # Filter to relevant date range
        date_filtered = existing_data.where(
            product_filter
        )

        # Join with user-product pairs to further filter
        filtered_existing = date_filtered.join(
            user_product_pairs,
            on=["user_id", "product_code"],
            how="inner"
        ).cache()

        # Count and return
        session_count = filtered_existing.select("session_id").distinct().count()
        logger.info(f"Found {session_count} existing sessions that might overlap")

        return filtered_existing

    except Exception as e:
        logger.error(f"Error reading existing sessions: {str(e)}")
        # If no data exists or other error, return empty DataFrame
        return spark.createDataFrame([], new_sessions.schema)


def reconcile_sessions(new_sessions: DataFrame, existing_sessions: DataFrame) -> DataFrame:
    """
    Reconcile new sessions with existing ones to handle retroactive data.
    Returns a single DataFrame ready for a merge operation.

    Args:
        new_sessions: New session data
        existing_sessions: Existing session data

    Returns:
        DataFrame: Combined DataFrame with all records ready for merge
    """
    # If no existing sessions, just return new sessions with merge metadata
    if existing_sessions.count() == 0:
        logger.info("No existing sessions to reconcile with")
        # Add a column to indicate these are all new records
        return new_sessions.withColumn("merge_action", lit("insert"))

    # Get session boundaries for existing data
    existing_bounds = get_session_boundaries(existing_sessions, 'existing')

    # Get session boundaries for new data
    new_bounds = get_session_boundaries(new_sessions, 'new')

    # Calculate time relationship between sessions
    comparison = new_bounds.alias("new").join(
        existing_bounds.alias("existing"),
        (col("new.user_id") == col("existing.user_id")) &
        (col("new.product_code") == col("existing.product_code")) &
        # Add time window condition to limit matches
        (
                (unix_timestamp(col("new_session_min_time")) - SESSION_TIMEOUT_SECS <=
                 unix_timestamp(col("existing_session_max_time"))) &
                (unix_timestamp(col("new_session_max_time")) + SESSION_TIMEOUT_SECS >=
                 unix_timestamp(col("existing_session_min_time")))
        ),
        how="left"
    )

    # Calculate time relationship between sessions
    comparison = comparison.withColumn(
        "time_to_existing_start",
        when(col("existing_session_min_time").isNotNull(),
             unix_timestamp(col("existing_session_min_time")) - unix_timestamp(col("new_session_max_time")))
        .otherwise(lit(float("inf")))
    ).withColumn(
        "time_from_existing_end",
        when(col("existing_session_max_time").isNotNull(),
             unix_timestamp(col("new_session_min_time")) - unix_timestamp(col("existing_session_max_time")))
        .otherwise(lit(float("inf")))
    )

    # Apply reconciliation rules
    reconciled = comparison.withColumn(
        # Extension case: new data is within 5 minutes after the end of existing session
        "extends_existing_session",
        (col("time_from_existing_end") >= 0) &
        (col("time_from_existing_end") <= SESSION_TIMEOUT_SECS)
    ).withColumn(
        # Precedence case: existing session is within 5 minutes after the end of new data
        "precedes_existing_session",
        (col("time_to_existing_start") >= 0) &
        (col("time_to_existing_start") <= SESSION_TIMEOUT_SECS)
    ).withColumn(
        # Direct overlap case
        "overlaps_existing_session",
        (col("new_session_min_time") <= col("new_session_max_time")) &
        (col("new_session_max_time") >= col("new_session_min_time"))
    ).withColumn(
        # Flag if new data starts earlier than existing session
        "is_earlier_start",
        (col("new_session_min_time") < col("existing_session_min_time"))
    )

    # Determine final session ID based on reconciliation rules
    reconciled = reconciled.withColumn(
        "final_session_id",
        when((col("overlaps_existing_session") | col("precedes_existing_session")) & col("is_earlier_start"),
             col("new_session_id"))
        .when((col("overlaps_existing_session") & ~col("is_earlier_start")) | col("extends_existing_session"),
              col("existing_session_id"))
        .otherwise(
            col("new_session_id"))
    )

    # Extract session ID mappings for new data to be updated
    new_mapping = reconciled.select(
        col("new.user_id").alias("user_id"),
        col("new.product_code").alias("product_code"),
        col("new_session_id").alias("original_session_id"),
        col("existing_session_min_time").alias("existing_session_min_time"),
        col("new_session_max_time").alias("new_session_max_time"),
        col("final_session_id")
    ).filter(col("new_session_id") != col("final_session_id"))

    # Extract all affected existing sessions that need updating
    affected_existing_sessions = reconciled.filter(
        (col("existing_session_id") != col("final_session_id"))
    ).select(
        col("existing.user_id").alias("user_id"),
        col("existing.product_code").alias("product_code"),
        col("existing_session_id").alias("original_session_id"),
        col("final_session_id")
    ).cache()

    # Join new mappings back to the new data to update session IDs
    updated_new_data = new_sessions.join(
        new_mapping,
        (new_sessions["user_id"] == new_mapping["user_id"]) &
        (new_sessions["product_code"] == new_mapping["product_code"]) &
        ((new_sessions["session_id"] == new_mapping["original_session_id"]) |
         (
                 new_sessions["session_id"].isNull() &
                 (new_sessions['timestamp'] >= new_mapping["existing_session_min_time"]) &
                 (new_sessions['timestamp'] <= new_mapping["new_session_max_time"])
         )
         ),
        how="left"
    ).withColumn(
        "session_id",
        when(col("final_session_id").isNotNull(), col("final_session_id"))
        .otherwise(col("session_id"))
    ).drop(
        new_mapping["user_id"], new_mapping["product_code"], new_mapping["existing_session_min_time"],
        new_mapping["new_session_max_time"],
        "original_session_id", "final_session_id"
    )

    # Add merge_action column to indicate these are inserts
    updated_new_data = updated_new_data.withColumn("merge_action", lit("insert"))

    # If we have existing sessions to update, prepare these records
    if affected_existing_sessions.count() > 0:
        # Get all the existing records that need to be updated
        existing_to_update = existing_sessions.join(
            affected_existing_sessions,
            (existing_sessions["user_id"] == affected_existing_sessions["user_id"]) &
            (existing_sessions["product_code"] == affected_existing_sessions["product_code"]) &
            (existing_sessions["session_id"] == affected_existing_sessions["original_session_id"]),
            how="inner"
        )

        # Update their session IDs
        updated_existing = existing_to_update.withColumn(
            "session_id",
            when(col("final_session_id").isNotNull(), col("final_session_id"))
            .otherwise(col("session_id"))
        ).drop(
            affected_existing_sessions["user_id"], affected_existing_sessions["product_code"],
            "original_session_id", "final_session_id"
        )

        # Add merge_action column to indicate these are updates
        updated_existing = updated_existing.withColumn("merge_action", lit("update"))

        # Create a unique key for each record to deduplicate later
        updated_new_data = updated_new_data.withColumn(
            "merge_key",
            concat_ws("#", col("user_id"), col("product_code"), col("event_id"), col("timestamp"))
        )
        updated_existing = updated_existing.withColumn(
            "merge_key",
            concat_ws("#", col("user_id"), col("product_code"), col("event_id"), col("timestamp"))
        )

        # Combine new and updated existing data
        all_data = updated_new_data.unionByName(updated_existing, allowMissingColumns=True)

        # Deduplicate in case of overlap
        deduplicated = all_data.dropDuplicates(["merge_key"])

        # Drop the merge_key column as it's no longer needed
        final_data = deduplicated.drop("merge_key")

        # Return the combined dataset
        mapping_count = affected_existing_sessions.count()
        logger.info(f"Reconciled {mapping_count} session ID updates")
        return final_data.select(
            "user_id", "product_code", "event_id", "timestamp", "session_id", "event_date"
        )
    else:
        # If no existing sessions need updates, just return the new data
        logger.info("No existing sessions need updates")
        return updated_new_data.select(
            "user_id", "product_code", "event_id", "timestamp", "session_id", "event_date"
        )


def write_data_with_merge(spark: SparkSession, merged_data: DataFrame) -> None:
    """
    Write data to Delta table using merge operation.

    Args:
        spark: Spark session
        merged_data: DataFrame with both new and updated records
    """
    try:
        try:
            delta_table = DeltaTable.forPath(spark, DELTA_TABLE_PATH)

            # Perform merge operation
            delta_table.alias("target").merge(
                merged_data.alias("source"),
                "target.user_id = source.user_id AND " +
                "target.product_code = source.product_code AND " +
                "target.event_id = source.event_id AND " +
                "target.timestamp = source.timestamp"
            ).whenMatchedUpdate(
                set={
                    "session_id": "source.session_id"
                }
            ).whenNotMatchedInsert(
                values={
                    "user_id": "source.user_id",
                    "event_id": "source.event_id",
                    "timestamp": "source.timestamp",
                    "product_code": "source.product_code",
                    "session_id": "source.session_id",
                    "event_date": "source.event_date"
                }
            ).execute()

            logger.info("Successfully merged data with Delta table")

        except Exception as e:
            logger.warning(f"Delta table doesn't exist yet, creating: {str(e)}")

            # Drop the merge_action column for initial write
            initial_data = merged_data.drop("merge_action")

            # Write new data normally
            initial_data.write.format("delta") \
                .partitionBy("product_code", "event_date") \
                .mode("append") \
                .save(DELTA_TABLE_PATH)

            logger.info(f"Created new Delta table with {initial_data.count()} records")

    except Exception as e:
        logger.error(f"Error writing data: {str(e)}")
        raise

def move_files(files: List[str]) -> None:
    """
    Move processed files from the raw data folder.
    Args:
        files: List of file paths to be moved
    """
    try:
        for f in files:
            if os.path.exists(f):
                shutil.move(f, f.replace(RAW_DATA_FOLDER, PROCESSED_DATA_FOLDER))
            else:
                logger.warning(f"File not found: {f}")
            
        logger.info(f"Moved {len(files)} files to processed folder")
    except Exception as e:
        logger.error(f"Error moving files: {str(e)}")
        raise

def main() -> None:
    """Main session builder pipeline."""

    # Set processing date

    # Initialize Spark session
    spark = create_spark_session()

    try:
        # 1. Read new data
        new_data, files = read_new_files(spark)

        # 2. Identify sessions within the new data
        logger.info("Identifying sessions in new data...")
        sessions = identify_sessions(new_data)

        # 4. Read existing sessions that might need reconciliation
        logger.info("Reading existing processed data...")
        existing_sessions = read_existing_sessions(
            spark, sessions
        )

        # 5. Reconcile with existing sessions
        logger.info("Reconciling with existing sessions...")
        merged_data = reconcile_sessions(sessions, existing_sessions)

        # Use a single merge operation to write data
        logger.info("Writing data using merge operation...")
        write_data_with_merge(spark, merged_data)

        # 8. Log statistics
        sessions_count = merged_data.select("session_id").distinct().count()
        events_count = merged_data.count()

        logger.info("=== Session Builder Summary ===")
        logger.info(f"Processed {events_count} events")
        logger.info(f"Identified {sessions_count} sessions")

        move_files(files)

        logger.info("=== Processing complete ===")

    except Exception as e:
        logger.error(f"Error in session builder pipeline: {str(e)}")
        raise
    finally:
        spark.stop()


if __name__ == "__main__":
    main()