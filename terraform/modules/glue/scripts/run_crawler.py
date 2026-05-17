"""
Smart City Data Platform – Glue Crawler Runner
Triggers the raw data crawler and waits for it to complete,
then optionally kicks off the ETL job.

Usage:
    python run_crawler.py --env dev --region ap-southeast-2
    python run_crawler.py --env dev --region ap-southeast-2 --run-etl
"""

import argparse
import time
import boto3
import sys

def parse_args():
    parser = argparse.ArgumentParser(description="Run Glue crawler and optionally trigger ETL")
    parser.add_argument("--env",        default="dev",            help="Environment (dev/staging/prod)")
    parser.add_argument("--project",    default="smart-city",     help="Project name prefix")
    parser.add_argument("--region",     default="ap-southeast-2", help="AWS region")
    parser.add_argument("--run-etl",    action="store_true",      help="Trigger ETL job after crawler succeeds")
    parser.add_argument("--profile",    default=None,             help="AWS profile name")
    return parser.parse_args()


def wait_for_crawler(glue, crawler_name, poll_seconds=15):
    print(f"⏳ Waiting for crawler '{crawler_name}' to complete...")
    while True:
        response = glue.get_crawler(Name=crawler_name)
        state    = response["Crawler"]["State"]
        print(f"   State: {state}")

        if state == "READY":
            last = response["Crawler"].get("LastCrawl", {})
            status = last.get("Status", "UNKNOWN")
            if status == "SUCCEEDED":
                print(f"✅ Crawler completed successfully.")
                tables = last.get("TablesChanged", 0) + last.get("TablesAdded", 0)
                print(f"   Tables added/updated: {tables}")
                return True
            else:
                print(f"❌ Crawler finished with status: {status}")
                print(f"   Error: {last.get('ErrorMessage', 'none')}")
                return False

        time.sleep(poll_seconds)


def wait_for_job(glue, job_name, run_id, poll_seconds=20):
    print(f"⏳ Waiting for Glue job '{job_name}' to complete...")
    while True:
        response = glue.get_job_run(JobName=job_name, RunId=run_id)
        state    = response["JobRun"]["JobRunState"]
        duration = response["JobRun"].get("ExecutionTime", 0)
        print(f"   State: {state} | Duration: {duration}s")

        if state in ("SUCCEEDED", "FAILED", "STOPPED", "ERROR", "TIMEOUT"):
            if state == "SUCCEEDED":
                print(f"✅ ETL job completed successfully in {duration}s.")
            else:
                err = response["JobRun"].get("ErrorMessage", "unknown error")
                print(f"❌ ETL job ended with state: {state}")
                print(f"   Error: {err}")
            return state == "SUCCEEDED"

        time.sleep(poll_seconds)


def main():
    args = parse_args()

    session = boto3.Session(profile_name=args.profile, region_name=args.region)
    glue    = session.client("glue")

    crawler_name = f"{args.project}-{args.env}-raw-crawler"
    job_name     = f"{args.project}-{args.env}-etl"

    # ── 1. Start crawler ──────────────────────────────────────────────────────
    print(f"\n🔍 Starting crawler: {crawler_name}")
    try:
        glue.start_crawler(Name=crawler_name)
    except glue.exceptions.CrawlerRunningException:
        print("   Crawler already running, waiting for it to finish...")
    except Exception as e:
        print(f"❌ Failed to start crawler: {e}")
        sys.exit(1)

    # ── 2. Wait for crawler ───────────────────────────────────────────────────
    time.sleep(5)  # brief pause before first poll
    success = wait_for_crawler(glue, crawler_name)
    if not success:
        sys.exit(1)

    # ── 3. Show discovered tables ─────────────────────────────────────────────
    print(f"\n📋 Tables in Glue catalog:")
    try:
        tables = glue.get_tables(DatabaseName=f"smart_city_{args.env}")
        for t in tables["TableList"]:
            print(f"   - {t['Name']} ({t.get('StorageDescriptor', {}).get('Location', '')})")
    except Exception as e:
        print(f"   Could not list tables: {e}")

    # ── 4. Optionally run ETL job ─────────────────────────────────────────────
    if args.run_etl:
        print(f"\n🚀 Starting ETL job: {job_name}")
        try:
            response = glue.start_job_run(JobName=job_name)
            run_id   = response["JobRunId"]
            print(f"   JobRunId: {run_id}")
            time.sleep(10)
            wait_for_job(glue, job_name, run_id)
        except Exception as e:
            print(f"❌ Failed to start ETL job: {e}")
            sys.exit(1)

    print("\n✅ Done.")


if __name__ == "__main__":
    main()