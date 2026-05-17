# =============================================================================
# ATHENA MODULE - Smart City Data Platform
# Phase 2: Analytics Layer
# =============================================================================

# ── Athena Workgroup ──────────────────────────────────────────────────────────
resource "aws_athena_workgroup" "smart_city" {
  name        = "${var.project_name}-${var.environment}"
  description = "Smart City Data Platform - Athena workgroup for analytics"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.results_bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    bytes_scanned_cutoff_per_query = var.bytes_scanned_cutoff_per_query
  }

  tags = var.tags
}

# ── Glue Database (Athena uses Glue Catalog) ─────────────────────────────────
resource "aws_glue_catalog_database" "smart_city" {
  name        = replace("${var.project_name}_${var.environment}", "-", "_")
  description = "Smart City Data Lake - Glue/Athena Catalog"
}

# ── Glue Tables ───────────────────────────────────────────────────────────────

# Raw telemetry table
resource "aws_glue_catalog_table" "telemetry_raw" {
  name          = "telemetry_raw"
  database_name = aws_glue_catalog_database.smart_city.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL          = "TRUE"
    "classification"  = "json"
    "compressionType" = "none"
    "typeOfData"      = "file"

    # Partition projection: Athena synthesises partitions from the path template
    # without needing a crawler or MSCK REPAIR TABLE.
    "projection.enabled"        = "true"
    "projection.year.type"      = "integer"
    "projection.year.range"     = "2024,2030"
    "projection.month.type"     = "integer"
    "projection.month.range"    = "1,12"
    "projection.month.digits"   = "2"
    "projection.day.type"       = "integer"
    "projection.day.range"      = "1,31"
    "projection.day.digits"     = "2"
    "storage.location.template" = "s3://${var.datalake_bucket}/raw/telemetry/year=$${year}/month=$${month}/day=$${day}/"
  }

  storage_descriptor {
    location      = "s3://${var.datalake_bucket}/raw/telemetry/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"

      parameters = {
        "serialization.format" = "1"
        "ignore.malformed.json" = "TRUE"
      }
    }

    columns {
      name = "device_id"
      type = "string"
    }
    columns {
      name = "device_type"
      type = "string"
    }
    columns {
      name = "location"
      type = "struct<lat:double,lon:double,district:string>"
    }
    columns {
      name = "timestamp"
      type = "string"
    }
    columns {
      name = "metrics"
      type = "map<string,double>"
    }
    columns {
      name = "status"
      type = "string"
    }
    columns {
      name = "processed_at"
      type = "string"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
}

# Processed telemetry table (Parquet)
resource "aws_glue_catalog_table" "telemetry_processed" {
  name          = "telemetry_processed"
  database_name = aws_glue_catalog_database.smart_city.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                        = "TRUE"
    "classification"                = "parquet"
    "parquet.compress"              = "SNAPPY"
    "has_encrypted_data"            = "false"
  }

  storage_descriptor {
    location      = "s3://${var.datalake_bucket}/processed/telemetry/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "parquet-serde"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "device_id"
      type = "string"
    }
    columns {
      name = "device_type"
      type = "string"
    }
    columns {
      name = "latitude"
      type = "double"
    }
    columns {
      name = "longitude"
      type = "double"
    }
    columns {
      name = "district"
      type = "string"
    }
    columns {
      name = "event_timestamp"
      type = "timestamp"
    }
    columns {
      name = "metric_name"
      type = "string"
    }
    columns {
      name = "metric_value"
      type = "double"
    }
    columns {
      name = "status"
      type = "string"
    }
    columns {
      name = "processed_at"
      type = "timestamp"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
}

# ── Named Queries (saved Athena queries) ──────────────────────────────────────
resource "aws_athena_named_query" "device_summary" {
  name        = "device-summary-by-type"
  workgroup   = aws_athena_workgroup.smart_city.id
  database    = aws_glue_catalog_database.smart_city.name
  description = "Summarise device count and latest reading per device type"

  query = <<-SQL
    SELECT
        device_type,
        COUNT(DISTINCT device_id)   AS device_count,
        COUNT(*)                    AS total_readings,
        MAX(event_timestamp)        AS last_seen,
        AVG(metric_value)           AS avg_metric_value
    FROM "${aws_glue_catalog_database.smart_city.name}"."telemetry_processed"
    WHERE year  = cast(year(current_date)  AS varchar)
      AND month = lpad(cast(month(current_date) AS varchar), 2, '0')
      AND day   = lpad(cast(day(current_date)   AS varchar), 2, '0')
    GROUP BY device_type
    ORDER BY total_readings DESC;
  SQL
}

resource "aws_athena_named_query" "district_heatmap" {
  name        = "district-metric-heatmap"
  workgroup   = aws_athena_workgroup.smart_city.id
  database    = aws_glue_catalog_database.smart_city.name
  description = "Average metric values by district for the past 7 days"

  query = <<-SQL
    SELECT
        district,
        device_type,
        metric_name,
        ROUND(AVG(metric_value), 2)  AS avg_value,
        ROUND(MIN(metric_value), 2)  AS min_value,
        ROUND(MAX(metric_value), 2)  AS max_value,
        COUNT(*)                     AS sample_count
    FROM "${aws_glue_catalog_database.smart_city.name}"."telemetry_processed"
    WHERE from_iso8601_timestamp(cast(event_timestamp AS varchar))
              >= (current_timestamp - interval '7' day)
    GROUP BY district, device_type, metric_name
    ORDER BY district, avg_value DESC;
  SQL
}

resource "aws_athena_named_query" "anomaly_detection" {
  name        = "anomaly-detection-zscore"
  workgroup   = aws_athena_workgroup.smart_city.id
  database    = aws_glue_catalog_database.smart_city.name
  description = "Detect anomalies using Z-score (values > 2 std devs from mean)"

  query = <<-SQL
    WITH stats AS (
        SELECT
            device_type,
            metric_name,
            AVG(metric_value)    AS mean_val,
            STDDEV(metric_value) AS stddev_val
        FROM "${aws_glue_catalog_database.smart_city.name}"."telemetry_processed"
        WHERE year  = cast(year(current_date)  AS varchar)
        GROUP BY device_type, metric_name
    )
    SELECT
        t.device_id,
        t.device_type,
        t.district,
        t.metric_name,
        t.metric_value,
        s.mean_val,
        s.stddev_val,
        ROUND(ABS(t.metric_value - s.mean_val) / NULLIF(s.stddev_val, 0), 2) AS z_score,
        t.event_timestamp
    FROM "${aws_glue_catalog_database.smart_city.name}"."telemetry_processed" t
    JOIN stats s
      ON t.device_type = s.device_type
     AND t.metric_name = s.metric_name
    WHERE s.stddev_val > 0
      AND ABS(t.metric_value - s.mean_val) / s.stddev_val > 2
    ORDER BY z_score DESC
    LIMIT 100;
  SQL
}

resource "aws_athena_named_query" "pipeline_health" {
  name        = "pipeline-health-check"
  workgroup   = aws_athena_workgroup.smart_city.id
  database    = aws_glue_catalog_database.smart_city.name
  description = "Check data pipeline health – record counts and latency per hour"

  query = <<-SQL
    SELECT
        date_trunc('hour', event_timestamp)   AS hour_bucket,
        device_type,
        COUNT(*)                              AS record_count,
        COUNT(DISTINCT device_id)             AS unique_devices,
        ROUND(
            AVG(
                date_diff('second',
                    event_timestamp,
                    processed_at)
            ), 1)                             AS avg_processing_latency_secs
    FROM "${aws_glue_catalog_database.smart_city.name}"."telemetry_processed"
    WHERE year  = cast(year(current_date) AS varchar)
      AND month = lpad(cast(month(current_date) AS varchar), 2, '0')
      AND day   = lpad(cast(day(current_date)   AS varchar), 2, '0')
    GROUP BY 1, 2
    ORDER BY 1 DESC, record_count DESC;
  SQL
}
