"""
Smart City Data Platform – Glue ETL Job
Phase 2: Raw JSON  ->  Processed Parquet (partitioned by year/month/day)

Raw schema (from ingestion_lambda / inject_sample_data):
  device_id    : string
  device_type  : string
  location     : struct<lat:double, lon:double, district:string>
  timestamp    : string (ISO 8601)
  metrics      : map<string, double>
  status       : string
  processed_at : string (added by processor lambda)

Processed schema (one row per metric):
  device_id       : string
  device_type     : string
  latitude        : double
  longitude       : double
  district        : string
  event_timestamp : timestamp
  metric_name     : string
  metric_value    : double
  status          : string
  processed_at    : timestamp
  year / month / day : partition columns

Arguments (passed via --<key>=<value> in Glue job defaults):
  --SOURCE_BUCKET    : S3 bucket containing raw data
  --TARGET_BUCKET    : S3 bucket for processed output (usually same bucket)
  --DATABASE_NAME    : Glue catalog database name
  --SOURCE_TABLE     : Glue catalog source table  (telemetry_raw)
  --TARGET_TABLE     : Glue catalog target table  (telemetry_processed)
  --ENVIRONMENT      : dev / staging / prod
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import (
    DoubleType, MapType, StringType, StructField, StructType,
)

# ── Bootstrap ─────────────────────────────────────────────────────────────────
args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "SOURCE_BUCKET", "TARGET_BUCKET",
    "DATABASE_NAME", "SOURCE_TABLE", "TARGET_TABLE",
    "ENVIRONMENT",
])

sc          = SparkContext()
glueContext = GlueContext(sc)
spark       = glueContext.spark_session
job         = Job(glueContext)
job.init(args["JOB_NAME"], args)

logger = glueContext.get_logger()
logger.info(f"[SmartCity ETL] Starting job  : {args['JOB_NAME']}")
logger.info(f"[SmartCity ETL] Environment   : {args['ENVIRONMENT']}")
logger.info(f"[SmartCity ETL] Source table  : {args['DATABASE_NAME']}.{args['SOURCE_TABLE']}")
logger.info(f"[SmartCity ETL] Target path   : s3://{args['TARGET_BUCKET']}/processed/telemetry/")

# ── 1. Read raw JSON directly from S3 with an explicit schema ────────────────
# Spark's JSON inference would treat `metrics` as a wide struct (the union of
# every metric key seen across all device types). We need MapType<String,Double>
# so explode() works downstream — hence the explicit schema.
source_path = f"s3://{args['SOURCE_BUCKET']}/raw/telemetry/"

raw_schema = StructType([
    StructField("device_id",   StringType(), True),
    StructField("device_type", StringType(), True),
    StructField("location", StructType([
        StructField("lat",      DoubleType(), True),
        StructField("lon",      DoubleType(), True),
        StructField("district", StringType(), True),
    ]), True),
    StructField("timestamp",    StringType(), True),
    StructField("metrics",      MapType(StringType(), DoubleType()), True),
    StructField("status",       StringType(), True),
    StructField("processed_at", StringType(), True),
])

raw_df = (
    spark.read
    .schema(raw_schema)
    .option("recursiveFileLookup", "true")  # ignore Hive-style partition dirs
    .json(source_path)
)
record_count = raw_df.count()
logger.info(f"[SmartCity ETL] Records read: {record_count}")

if record_count > 0:
    # ── 2. Flatten the rich event structure ───────────────────────────────────
    flattened_df = (
        raw_df
        .withColumn("latitude",        F.col("location.lat"))
        .withColumn("longitude",       F.col("location.lon"))
        .withColumn("district",        F.col("location.district"))
        .withColumn("event_timestamp", F.to_timestamp("timestamp"))
        .withColumn("processed_at",    F.to_timestamp("processed_at"))
        .drop("location", "timestamp")
    )

    # Explode the metrics map -> one row per (device, metric_name)
    exploded_df = (
        flattened_df
        .select(
            "device_id", "device_type", "latitude", "longitude", "district",
            "event_timestamp", "status", "processed_at",
            F.explode("metrics").alias("metric_name", "metric_value"),
        )
    )

    # ── 3. Data quality checks ────────────────────────────────────────────────
    valid_df = (
        exploded_df
        .filter(F.col("device_id").isNotNull())
        .filter(F.col("event_timestamp").isNotNull())
        .filter(F.col("metric_value").isNotNull())
        .filter(F.col("latitude").between(-90, 90))
        .filter(F.col("longitude").between(-180, 180))
    )

    invalid_count = exploded_df.count() - valid_df.count()
    valid_count   = valid_df.count()
    logger.info(f"[SmartCity ETL] Records dropped (DQ): {invalid_count}")
    logger.info(f"[SmartCity ETL] Records passing DQ  : {valid_count}")

    if valid_count > 0:
        # ── 4. Add partition columns ──────────────────────────────────────────
        partitioned_df = (
            valid_df
            .withColumn("year",  F.date_format("event_timestamp", "yyyy"))
            .withColumn("month", F.date_format("event_timestamp", "MM"))
            .withColumn("day",   F.date_format("event_timestamp", "dd"))
        )

        # ── 5. Write Parquet via Glue sink (registers partitions in Catalog) ─
        target_path = f"s3://{args['TARGET_BUCKET']}/processed/telemetry/"
        logger.info(f"[SmartCity ETL] Writing {valid_count} records to: {target_path}")

        output_dyf = DynamicFrame.fromDF(partitioned_df, glueContext, "output")

        sink = glueContext.getSink(
            connection_type     = "s3",
            path                = target_path,
            enableUpdateCatalog = True,
            updateBehavior      = "UPDATE_IN_DATABASE",
            partitionKeys       = ["year", "month", "day"],
            transformation_ctx  = "processed_sink",
        )
        sink.setCatalogInfo(
            catalogDatabase  = args["DATABASE_NAME"],
            catalogTableName = args["TARGET_TABLE"],
        )
        sink.setFormat("glueparquet", compression="snappy")
        sink.writeFrame(output_dyf)
else:
    logger.info("[SmartCity ETL] No new records - nothing to write.")

logger.info("[SmartCity ETL] Job completed successfully.")
job.commit()
