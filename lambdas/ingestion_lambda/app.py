import json
import os
from datetime import datetime, timezone

import boto3



kinesis = boto3.client("kinesis")
STREAM_NAME = os.environ["STREAM_NAME"]


def lambda_handler(event, context):
    body = json.loads(event["body"])

    if "timestamp" not in body:
        body["timestamp"] = datetime.now(timezone.utc).isoformat()

    device_id = body.get("device_id")
    if not device_id:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "device_id is required"}),
        }

    kinesis.put_record(
        StreamName=STREAM_NAME,
        Data=json.dumps(body),
        PartitionKey=device_id,
    )

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Data ingested"}),
    }
