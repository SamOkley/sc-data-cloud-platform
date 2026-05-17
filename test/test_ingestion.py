import json
import os
from unittest.mock import MagicMock, patch

# 2. Set environment variables
os.environ["STREAM_NAME"] = "test-stream"

# 3. Import your lambda app AFTER boto3 is guaranteed to be installed
from lambdas.ingestion_lambda.app import lambda_handler


def test_lambda_handler_puts_record_to_kinesis():
    event = {
        "body": json.dumps({
            "device_id": "sensor-1",
            "temperature": 28,
            "humidity": 60,
        })
    }

    mock_client = MagicMock()
    with patch("lambdas.ingestion_lambda.app.kinesis", mock_client):
        response = lambda_handler(event, None)

    mock_client.put_record.assert_called_once()
    _, kwargs = mock_client.put_record.call_args

    assert kwargs["StreamName"] == "test-stream"

    payload = json.loads(kwargs["Data"])
    assert payload["device_id"] == "sensor-1"
    assert payload["temperature"] == 28
    assert payload["humidity"] == 60
    assert "timestamp" in payload

    assert response["statusCode"] == 200
    assert json.loads(response["body"]) == {"message": "Data ingested"}
