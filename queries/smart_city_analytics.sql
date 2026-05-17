-- =============================================================================
-- Smart City Data Platform – Athena SQL Query Library
-- Phase 2: Analytics Templates
--
-- Usage: Open Athena console → select workgroup "smart-city-<env>"
--        → select database from the catalog → paste and run
--
-- IMPORTANT: Replace <DATABASE> with your actual Glue database name.
--            The Terraform outputs show it as "glue_database".
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. HOUSEKEEPING
-- ─────────────────────────────────────────────────────────────────────────────

-- Repair partitions after new data lands (run after a Glue crawl or ETL job)
MSCK REPAIR TABLE <DATABASE>.telemetry_processed;
MSCK REPAIR TABLE <DATABASE>.telemetry_raw;

-- Preview table structure
DESCRIBE <DATABASE>.telemetry_processed;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DEVICE OVERVIEW
-- ─────────────────────────────────────────────────────────────────────────────

-- 1a. Count of unique devices by type (today)
SELECT
    device_type,
    COUNT(DISTINCT device_id)  AS device_count,
    COUNT(*)                   AS total_events,
    MAX(event_timestamp)       AS last_event
FROM <DATABASE>.telemetry_processed
WHERE year  = cast(year(current_date)  AS varchar)
  AND month = lpad(cast(month(current_date) AS varchar), 2, '0')
  AND day   = lpad(cast(day(current_date)   AS varchar), 2, '0')
GROUP BY device_type
ORDER BY total_events DESC;

-- 1b. Devices that have NOT reported in the last 30 minutes (stale devices)
SELECT DISTINCT device_id, device_type, district, MAX(event_timestamp) AS last_seen
FROM <DATABASE>.telemetry_processed
GROUP BY device_id, device_type, district
HAVING MAX(event_timestamp) < (current_timestamp - interval '30' minute)
ORDER BY last_seen ASC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. DISTRICT / GEO ANALYTICS
-- ─────────────────────────────────────────────────────────────────────────────

-- 2a. Average metric value per district (last 7 days)
SELECT
    district,
    device_type,
    metric_name,
    ROUND(AVG(metric_value), 2) AS avg_val,
    ROUND(MIN(metric_value), 2) AS min_val,
    ROUND(MAX(metric_value), 2) AS max_val,
    COUNT(*)                    AS sample_count
FROM <DATABASE>.telemetry_processed
WHERE event_timestamp >= (current_timestamp - interval '7' day)
GROUP BY district, device_type, metric_name
ORDER BY district, avg_val DESC;

-- 2b. Top 5 "hottest" districts by average sensor reading today
SELECT
    district,
    ROUND(AVG(metric_value), 2) AS avg_metric
FROM <DATABASE>.telemetry_processed
WHERE year  = cast(year(current_date) AS varchar)
  AND metric_name = 'temperature'        -- change to any metric you care about
GROUP BY district
ORDER BY avg_metric DESC
LIMIT 5;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. TIME-SERIES / TREND ANALYSIS
-- ─────────────────────────────────────────────────────────────────────────────

-- 3a. Hourly event volume (last 24 hours) – use to spot gaps in ingestion
SELECT
    date_trunc('hour', event_timestamp) AS hour_bucket,
    device_type,
    COUNT(*)                            AS event_count
FROM <DATABASE>.telemetry_processed
WHERE event_timestamp >= (current_timestamp - interval '24' hour)
GROUP BY 1, 2
ORDER BY 1, event_count DESC;

-- 3b. 15-minute rolling average (useful for dashboards)
SELECT
    date_trunc('minute',
        event_timestamp - (minute(event_timestamp) % 15) * interval '1' minute
    ) AS bucket_15m,
    metric_name,
    ROUND(AVG(metric_value), 3) AS avg_value,
    COUNT(*)                    AS samples
FROM <DATABASE>.telemetry_processed
WHERE event_timestamp >= (current_timestamp - interval '6' hour)
GROUP BY 1, 2
ORDER BY 1 DESC;

-- 3c. Day-over-day comparison (today vs yesterday, same hour)
WITH today AS (
    SELECT
        hour(event_timestamp) AS hr,
        ROUND(AVG(metric_value), 2) AS avg_today
    FROM <DATABASE>.telemetry_processed
    WHERE cast(event_timestamp AS date) = current_date
      AND metric_name = 'co2_ppm'
    GROUP BY 1
),
yesterday AS (
    SELECT
        hour(event_timestamp) AS hr,
        ROUND(AVG(metric_value), 2) AS avg_yesterday
    FROM <DATABASE>.telemetry_processed
    WHERE cast(event_timestamp AS date) = current_date - interval '1' day
      AND metric_name = 'co2_ppm'
    GROUP BY 1
)
SELECT
    t.hr,
    t.avg_today,
    y.avg_yesterday,
    ROUND(t.avg_today - y.avg_yesterday, 2) AS delta
FROM today t
LEFT JOIN yesterday y ON t.hr = y.hr
ORDER BY t.hr;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. ANOMALY DETECTION
-- ─────────────────────────────────────────────────────────────────────────────

-- 4a. Z-score based anomalies (readings > 2 std devs from mean, last 24h)
WITH stats AS (
    SELECT
        device_type,
        metric_name,
        AVG(metric_value)    AS mean_val,
        STDDEV(metric_value) AS stddev_val
    FROM <DATABASE>.telemetry_processed
    WHERE event_timestamp >= (current_timestamp - interval '24' hour)
    GROUP BY device_type, metric_name
)
SELECT
    t.device_id,
    t.device_type,
    t.district,
    t.metric_name,
    ROUND(t.metric_value, 3)         AS raw_value,
    ROUND(s.mean_val, 3)             AS mean_val,
    ROUND(s.stddev_val, 3)           AS stddev_val,
    ROUND(ABS(t.metric_value - s.mean_val) / NULLIF(s.stddev_val, 0), 2) AS z_score,
    t.event_timestamp
FROM <DATABASE>.telemetry_processed t
JOIN stats s
  ON t.device_type = s.device_type
 AND t.metric_name = s.metric_name
WHERE s.stddev_val > 0
  AND t.event_timestamp >= (current_timestamp - interval '24' hour)
  AND ABS(t.metric_value - s.mean_val) / NULLIF(s.stddev_val, 0) > 2
ORDER BY z_score DESC
LIMIT 100;

-- 4b. Devices with sudden spikes (current value > 3× rolling average)
WITH rolling AS (
    SELECT
        device_id,
        metric_name,
        metric_value,
        event_timestamp,
        AVG(metric_value) OVER (
            PARTITION BY device_id, metric_name
            ORDER BY event_timestamp
            ROWS BETWEEN 10 PRECEDING AND 1 PRECEDING
        ) AS rolling_avg
    FROM <DATABASE>.telemetry_processed
    WHERE event_timestamp >= (current_timestamp - interval '2' hour)
)
SELECT *,
    ROUND(metric_value / NULLIF(rolling_avg, 0), 2) AS spike_ratio
FROM rolling
WHERE rolling_avg > 0
  AND metric_value > 3 * rolling_avg
ORDER BY spike_ratio DESC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. PIPELINE HEALTH & OPS
-- ─────────────────────────────────────────────────────────────────────────────

-- 5a. Records per hour with processing latency
SELECT
    date_trunc('hour', event_timestamp) AS hour_bucket,
    COUNT(*)                            AS record_count,
    COUNT(DISTINCT device_id)           AS unique_devices,
    ROUND(AVG(date_diff('second', event_timestamp, processed_at)), 1) AS avg_latency_secs,
    MAX(date_diff('second', event_timestamp, processed_at))           AS max_latency_secs
FROM <DATABASE>.telemetry_processed
WHERE event_timestamp >= (current_timestamp - interval '48' hour)
GROUP BY 1
ORDER BY 1 DESC;

-- 5b. Partition coverage check – detect missing hours
WITH hours AS (
    SELECT sequence(
        cast(current_date - interval '7' day AS timestamp),
        cast(current_date AS timestamp),
        interval '1' hour
    ) AS h_arr
),
expanded AS (SELECT h FROM hours CROSS JOIN UNNEST(h_arr) AS t(h))
SELECT
    e.h                        AS expected_hour,
    COALESCE(a.record_count, 0) AS record_count,
    CASE WHEN a.record_count IS NULL THEN 'MISSING' ELSE 'OK' END AS status
FROM expanded e
LEFT JOIN (
    SELECT date_trunc('hour', event_timestamp) AS hour_bucket, COUNT(*) AS record_count
    FROM <DATABASE>.telemetry_processed
    WHERE event_timestamp >= current_timestamp - interval '7' day
    GROUP BY 1
) a ON e.h = a.hour_bucket
ORDER BY e.h DESC;

-- 5c. Data volume estimate (helps with Athena cost monitoring)
SELECT
    year, month, day,
    COUNT(*)                                   AS record_count,
    COUNT(DISTINCT device_id)                  AS unique_devices,
    ROUND(SUM(length(cast(metric_value AS varchar))) / 1024.0 / 1024.0, 2) AS est_mb
FROM <DATABASE>.telemetry_processed
GROUP BY year, month, day
ORDER BY year DESC, month DESC, day DESC
LIMIT 30;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. COST OPTIMISATION
-- ─────────────────────────────────────────────────────────────────────────────

-- Always include partition filters in WHERE clauses to minimise bytes scanned:
--   WHERE year='2025' AND month='06' AND day='15'
--
-- Use the workgroup's bytes-scanned limit (set in Terraform: 1 GB by default).
-- Run EXPLAIN on expensive queries before executing them.

-- Example: efficient single-day scan
SELECT device_id, metric_name, AVG(metric_value) AS avg_val
FROM <DATABASE>.telemetry_processed
WHERE year  = '2025'
  AND month = '06'
  AND day   = '15'
GROUP BY device_id, metric_name;