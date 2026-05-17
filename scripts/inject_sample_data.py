#!/usr/bin/env python3
"""
Smart City Data Platform – Sample Data Injector & E2E Validator
Phase 2: End-to-end pipeline test

Usage:
    # Install dependencies (once)
    pip install boto3 requests --break-system-packages

    # Inject data through API Gateway (recommended – tests the whole stack)
    python scripts/inject_sample_data.py \
        --api-url https://<id>.execute-api.<region>.amazonaws.com/<stage>/ingest \
        --count 50

    # Write directly to S3 (bypasses API/Lambda, useful for Glue/Athena testing)
    python scripts/inject_sample_data.py \
        --mode s3 \
        --bucket smart-city-dev-datalake \
        --count 200

    # Validate data made it through the pipeline
    python scripts/inject_sample_data.py \
        --mode validate \
        --bucket smart-city-dev-datalake \
        --workgroup smart-city-dev \
        --database smart_city_dev
"""

import argparse
import json
import math
import random
import sys
import time
from datetime import datetime, timezone, timedelta

import boto3
import requests

# ── Device catalogue ──────────────────────────────────────────────────────────
DEVICE_TYPES = {
    "air_quality_sensor": {
        "metrics": {
            "co2_ppm":    (350, 800),
            "pm25":       (0, 150),
            "pm10":       (0, 200),
            "humidity":   (20, 95),
            "temperature": (10, 40),
        }
    },
    "traffic_counter": {
        "metrics": {
            "vehicle_count":   (0, 300),
            "avg_speed_kmh":   (0, 120),
            "occupancy_pct":   (0, 100),
        }
    },
    "smart_streetlight": {
        "metrics": {
            "power_watts":     (50, 250),
            "lux":             (0, 1000),
            "temperature":     (15, 70),
        }
    },
    "water_meter": {
        "metrics": {
            "flow_lpm":        (0, 500),
            "pressure_bar":    (1, 8),
            "temperature":     (5, 30),
        }
    },
    "noise_sensor": {
        "metrics": {
            "decibels":        (30, 100),
            "peak_db":         (40, 120),
        }
    },
}

DISTRICTS = ["CBD", "North", "South", "East", "West", "Inner-West", "Harbour"]

STATUSES = ["active", "active", "active", "active", "degraded", "offline"]  # weighted


def _rand_metric(low, high):
    """Gaussian-ish value within [low, high]."""
    mid = (low + high) / 2
    std = (high - low) / 6
    return max(low, min(high, random.gauss(mid, std)))


def generate_event(device_id: str = None, ts: datetime = None) -> dict:
    """Generate one realistic telemetry event."""
    d_type = random.choice(list(DEVICE_TYPES.keys()))
    device  = DEVICE_TYPES[d_type]
    district = random.choice(DISTRICTS)

    # Rough lat/lon centred on Sydney
    lat = -33.87 + random.uniform(-0.15, 0.15)
    lon = 151.21 + random.uniform(-0.15, 0.15)

    ts = ts or datetime.now(timezone.utc)

    return {
        "device_id":   device_id or f"{d_type}-{random.randint(1000, 9999)}",
        "device_type": d_type,
        "location":    {"lat": round(lat, 6), "lon": round(lon, 6), "district": district},
        "timestamp":   ts.isoformat(),
        "metrics":     {
            k: round(_rand_metric(*v), 3)
            for k, v in device["metrics"].items()
        },
        "status":      random.choice(STATUSES),
    }


# ── Injection modes ───────────────────────────────────────────────────────────

def inject_via_api(api_url: str, count: int, delay: float = 0.1) -> None:
    """POST events to the API Gateway endpoint."""
    print(f"[API] Sending {count} events to {api_url}")
    errors = 0
    for i in range(count):
        event = generate_event()
        try:
            resp = requests.post(
                api_url,
                json=event,
                timeout=10,
                headers={"Content-Type": "application/json"},
            )
            if resp.status_code not in (200, 201, 202):
                errors += 1
                print(f"  ✗ [{i+1}/{count}] HTTP {resp.status_code}: {resp.text[:120]}")
            else:
                if (i + 1) % 10 == 0:
                    print(f"  ✓ [{i+1}/{count}] sent OK")
        except requests.RequestException as e:
            errors += 1
            print(f"  ✗ [{i+1}/{count}] Request error: {e}")
        time.sleep(delay)

    print(f"\n[API] Done. {count - errors}/{count} succeeded, {errors} errors.")


def inject_via_s3(bucket: str, count: int) -> None:
    """Write events directly to S3 raw prefix (skips API+Lambda)."""
    s3 = boto3.client("s3")
    now = datetime.now(timezone.utc)
    prefix = f"raw/telemetry/year={now.year}/month={now.month:02d}/day={now.day:02d}"

    print(f"[S3] Writing {count} events to s3://{bucket}/{prefix}/")

    batch_size = 50
    batches    = math.ceil(count / batch_size)

    for b in range(batches):
        lines = []
        for _ in range(min(batch_size, count - b * batch_size)):
            ts    = now - timedelta(seconds=random.randint(0, 3600))
            event = generate_event(ts=ts)
            event["processed_at"] = now.isoformat()
            lines.append(json.dumps(event))

        key  = f"{prefix}/sample-{b:04d}-{int(now.timestamp())}.json"
        body = "\n".join(lines)
        s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType="application/json")
        print(f"  ✓ Batch {b+1}/{batches} → {key}")

    print(f"\n[S3] Done. {count} events written.")


# ── Validation ────────────────────────────────────────────────────────────────

def validate_pipeline(bucket: str, workgroup: str, database: str) -> None:
    """Run lightweight checks across S3, Athena, and Glue."""
    print("\n=== Pipeline Validation ===\n")

    s3     = boto3.client("s3")
    athena = boto3.client("athena")
    glue   = boto3.client("glue")

    # 1. S3 raw object count
    resp = s3.list_objects_v2(Bucket=bucket, Prefix="raw/telemetry/", MaxKeys=10)
    raw_count = resp.get("KeyCount", 0)
    print(f"[S3]     Raw objects found  : {raw_count}  {'✓' if raw_count > 0 else '✗ (no raw data!)'}")

    resp = s3.list_objects_v2(Bucket=bucket, Prefix="processed/telemetry/", MaxKeys=10)
    proc_count = resp.get("KeyCount", 0)
    print(f"[S3]     Processed objects  : {proc_count}  {'✓' if proc_count > 0 else '⚠ (Glue job not run yet?)'}")

    # 2. Glue catalog check
    try:
        glue.get_table(DatabaseName=database, Name="telemetry_raw")
        print(f"[Glue]   telemetry_raw table : ✓ exists")
    except glue.exceptions.EntityNotFoundException:
        print(f"[Glue]   telemetry_raw table : ✗ NOT FOUND – did Terraform apply succeed?")

    try:
        glue.get_table(DatabaseName=database, Name="telemetry_processed")
        print(f"[Glue]   telemetry_processed : ✓ exists")
    except glue.exceptions.EntityNotFoundException:
        print(f"[Glue]   telemetry_processed : ✗ NOT FOUND")

    # 3. Athena quick query
    print(f"\n[Athena] Running test query against workgroup '{workgroup}' ...")
    query = f"SELECT COUNT(*) AS cnt FROM \"{database}\".\"telemetry_processed\" LIMIT 1;"
    output_loc = f"s3://{bucket}/athena-results/"

    start = athena.start_query_execution(
        QueryString=query,
        WorkGroup=workgroup,
        QueryExecutionContext={"Database": database},
        ResultConfiguration={"OutputLocation": output_loc},
    )
    qid = start["QueryExecutionId"]

    for _ in range(30):
        time.sleep(2)
        status = athena.get_query_execution(QueryExecutionId=qid)
        state  = status["QueryExecution"]["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break

    if state == "SUCCEEDED":
        results = athena.get_query_results(QueryExecutionId=qid)
        row     = results["ResultSet"]["Rows"]
        count   = row[1]["Data"][0]["VarCharValue"] if len(row) > 1 else "0"
        print(f"[Athena] Row count in processed table: {count}  ✓")
    else:
        reason = status["QueryExecution"]["Status"].get("StateChangeReason", "unknown")
        print(f"[Athena] Query {state}: {reason}")

    print("\n=== Validation complete ===")


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Smart City – sample data injector")
    parser.add_argument("--mode",      choices=["api", "s3", "validate"], default="api")
    parser.add_argument("--api-url",   help="API Gateway endpoint URL")
    parser.add_argument("--bucket",    help="S3 data lake bucket name")
    parser.add_argument("--workgroup", help="Athena workgroup name (for validate)")
    parser.add_argument("--database",  help="Glue/Athena database name (for validate)")
    parser.add_argument("--count",     type=int, default=50, help="Number of events to generate")
    parser.add_argument("--delay",     type=float, default=0.05, help="Seconds between API calls")
    args = parser.parse_args()

    if args.mode == "api":
        if not args.api_url:
            print("ERROR: --api-url is required for api mode"); sys.exit(1)
        inject_via_api(args.api_url, args.count, args.delay)

    elif args.mode == "s3":
        if not args.bucket:
            print("ERROR: --bucket is required for s3 mode"); sys.exit(1)
        inject_via_s3(args.bucket, args.count)

    elif args.mode == "validate":
        if not all([args.bucket, args.workgroup, args.database]):
            print("ERROR: --bucket, --workgroup, and --database are required for validate mode")
            sys.exit(1)
        validate_pipeline(args.bucket, args.workgroup, args.database)


if __name__ == "__main__":
    main()
