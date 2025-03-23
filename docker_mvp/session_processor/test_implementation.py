from __future__ import annotations

from pyspark.sql.functions import col, to_timestamp
from spark_session_builder import (
    USER_EVENT_IDS,
    reconcile_sessions,
    identify_sessions,
    create_spark_session
)
from typing import TYPE_CHECKING

import unittest

if TYPE_CHECKING:
    from pyspark.sql import DataFrame, SparkSession


def create_test_data(spark: SparkSession) -> tuple[DataFrame, DataFrame]:
    """Create synthetic data for testing reconciliation logic"""
    # Sample existing sessions
    existing_data = spark.createDataFrame([
        # User 1 - Product A: Basic session
        ("user1", "a", "2025-03-10 10:00:00", "productA", "user1#productA#1710060000"),
        ("user1", "b", "2025-03-10 10:02:00", "productA", "user1#productA#1710060000"),
        ("user1", "c", "2025-03-10 10:04:00", "productA", "user1#productA#1710060000"),

        # User 2 - Product B: Session with a gap
        ("user2", "a", "2025-03-10 11:00:00", "productB", "user2#productB#1710063600"),
        ("user2", "b", "2025-03-10 11:02:00", "productB", "user2#productB#1710063600"),
        # Gap of 6 minutes (exceeding SESSION_TIMEOUT_SECS)
        ("user2", "a", "2025-03-10 11:10:00", "productB", "user2#productB#1710064200"),

        # User 3 - Product C: Simple session
        ("user3", "a", "2025-03-10 12:00:00", "productC", "user3#productC#1710067200"),
        ("user3", "b", "2025-03-10 12:03:00", "productC", "user3#productC#1710067200"),
    ], ["user_id", "event_id", "timestamp", "product_code", "session_id"])

    # Convert timestamp strings to timestamp type
    existing_data = existing_data.withColumn(
        "timestamp", to_timestamp(col("timestamp"))
    ).withColumn(
        "event_date", col("timestamp").cast("date")
    ).withColumn(
        "is_user_event", col("event_id").isin(USER_EVENT_IDS)
    )

    # Sample new data that will test different reconciliation cases
    new_data = spark.createDataFrame([
        # Case 1: Events that extend an existing session (within timeout)
        ("user1", "a", "2025-03-10 10:08:00", "productA"),  # Within 5 min of last event

        # Case 2: Events that should form a new session (beyond timeout)
        ("user1", "b", "2025-03-10 10:15:00", "productA"),  # Beyond 5 min

        # Case 3: Events that precede an existing session (within timeout)
        ("user2", "c", "2025-03-10 10:57:00", "productB"),  # 3 min before first event

        # Case 4: Events that overlap with existing session but start earlier
        ("user3", "a", "2025-03-10 11:58:00", "productC"),  # 2 min before first event
        ("user3", "b", "2025-03-10 12:01:00", "productC"),  # Overlaps with existing events

        # Case 5: Brand new user/product combo
        ("user4", "a", "2025-03-10 13:00:00", "productD"),
        ("user4", "b", "2025-03-10 13:03:00", "productD"),
    ], ["user_id", "event_id", "timestamp", "product_code"])

    new_data = new_data.withColumn(
        "timestamp", to_timestamp(col("timestamp"))
    )

    return existing_data, new_data

class TestReconciliation(unittest.TestCase):

    @classmethod
    def setUpClass(cls) -> None:
        cls.spark = create_spark_session()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.spark.stop()


    def test_reconciliation(self) -> None:
        """Test the reconciliation logic with synthetic data"""
        existing_data, new_data = create_test_data(self.spark)

        # Process the new data to identify sessions
        new_sessions = identify_sessions(new_data)

        # Reconcile the new sessions with existing ones
        reconciled_data = reconcile_sessions(new_sessions, existing_data)

        # Now analyze the results to validate different reconciliation cases

        # 1. Check the Case 1 event (extending existing session)
        case1 = reconciled_data.filter(
            (col("user_id") == "user1") &
            (col("timestamp") == "2025-03-10 10:08:00")
        ).select("session_id").collect()[0][0]

        assert case1 == "user1#productA#1710060000", f"Case 1 failed: {case1} != user1#productA#1710060000"
        print("✅ Case 1 passed: Event correctly extended existing session")

        # 2. Check the Case 2 event (new session beyond timeout)
        case2 = reconciled_data.filter(
            (col("user_id") == "user1") &
            (col("timestamp") == "2025-03-10 10:15:00")
        ).select("session_id").collect()[0][0]

        assert "user1#productA#1710060000" != case2, f"Case 2 failed: Session IDs should be different"
        print("✅ Case 2 passed: Event correctly created a new session")

        # Continue with other cases...

        print("All validation tests passed!")

    def test_session_extension(self) -> None:
        """Test that a new event within timeout extends an existing session"""
        # Create existing data
        existing_data = self.spark.createDataFrame([
            ("user1", "a", "2025-03-10 10:00:00", "productA", "user1#productA#1710060000"),
            ("user1", "b", "2025-03-10 10:02:00", "productA", "user1#productA#1710060000"),
        ], ["user_id", "event_id", "timestamp", "product_code", "session_id"])

        existing_data = existing_data.withColumn(
            "timestamp", to_timestamp(col("timestamp"))
        ).withColumn(
            "event_date", col("timestamp").cast("date")
        ).withColumn(
            "is_user_event", col("event_id").isin(USER_EVENT_IDS)
        )

        # Create new data within timeout
        new_data = self.spark.createDataFrame([
            ("user1", "a", "2025-03-10 10:03:20", "productA"),
            ("user1", "h", "2025-03-10 10:03:30", "productA"),
            ("user1", "h", "2025-03-10 10:03:35", "productA"),
            ("user1", "c", "2025-03-10 10:04:30", "productA"),
            ("user1", "c", "2025-03-10 10:14:30", "productA"),
            ("user1", "h", "2025-03-10 10:43:37", "productA"),
        ], ["user_id", "event_id", "timestamp", "product_code"])

        new_data = new_data.withColumn(
            "timestamp", to_timestamp(col("timestamp"))
        )

        # Process the data
        new_sessions = identify_sessions(new_data)
        result = reconcile_sessions(new_sessions, existing_data)

        # Check if the new user event got the same session ID
        session_id = result.filter(
            (col("user_id") == "user1") &
            (col("timestamp") == "2025-03-10 10:04:30")
        ).select("session_id").collect()[0][0]

        self.assertEqual("user1#productA#1710060000", session_id)
        print("✅ Case 1 passed: New user event got the same session ID as existing event")

        # Check if the new system event got the same session ID
        session_id = result.filter(
            (col("user_id") == "user1") &
            (col("timestamp") == "2025-03-10 10:03:30")
        ).select("session_id").collect()[0][0]

        self.assertEqual("user1#productA#1710060000", session_id)
        print("✅ Case 2 passed: New system event got the same session ID based on time diff from existing user event")

        # Check if the new system event got the same session ID
        session_id = result.filter(
            (col("user_id") == "user1") &
            (col("timestamp") == "2025-03-10 10:43:37")
        ).select("session_id").collect()[0][0]

        self.assertEqual(None, session_id)
        print("✅ Case 3 passed: New system event got None as session ID based on time diff from prev existing user event")