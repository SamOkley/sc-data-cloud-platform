import base64
import json
import os
import uuid
from datetime import datetime, timezone


import boto3
s3 = boto3.client("s3")
BUCKET = os.environ["DATA_LAKE_BUCKET"]

boto3
def lambda_handler(event, context):
    records_written = 0
    now = datetime.now(timezone.utc)
    year = now.strftime("%Y")
    month = now.strftime("%m")
    day = now.strftime("%d")

    for record in event["Records"]:
        payload = base64.b64decode(record["kinesis"]["data"])
        data = json.loads(payload)

        data.setdefault("processed_at", now.isoformat())

        key = (
            f"raw/telemetry/year={year}/month={month}/day={day}/"
            f"{uuid.uuid4()}.json"
        )

        s3.put_object(
            Bucket=BUCKET,
            Key=key,
            Body=json.dumps(data),
            ContentType="application/json",
        )

        records_written += 1

    print(f"[processor] {records_written} records written to s3://{BUCKET}/raw/telemetry/")

    return {
        "statusCode": 200,
        "records_written": records_written,
    }
