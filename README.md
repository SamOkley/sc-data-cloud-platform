<<<<<<< HEAD
# Smart City Data Cloud Platform

A Phase 1 serverless data ingestion platform for smart-city telemetry using AWS and Terraform.

## What this project builds

Phase 1 implements a baseline, production-ready-style pipeline with:

- API Gateway HTTP API for telemetry ingestion
- Lambda ingestion function to accept telemetry payloads
- Kinesis Data Stream for buffering telemetry events
- S3 Data Lake bucket for persisted event storage
- Lambda processor function to consume Kinesis records and write to S3
- IAM role and policies for Lambda execution
- CloudWatch logging via Lambda execution role
- Terraform-based infrastructure provisioning

### Data flow

1. Client POSTs telemetry JSON to `POST /telemetry`
2. API Gateway invokes the ingestion Lambda
3. Ingestion Lambda writes the event to Kinesis
4. Processor Lambda reads from Kinesis and writes into S3

## What is included

- `terraform/` - Terraform root and module definitions
- `lambdas/` - Lambda function code and deployment packages
- `test/` - Python test harness for ingestion logic
- `.github/workflows/terraform-ci.yml` - CI workflow for Terraform validation and tests

## What is in scope for Phase 1

Completed:
- Sandbox AWS account deployment (via Terraform)
- API Gateway ingestion endpoint
- Lambda ingestion and processor functions
- Kinesis stream for buffering
- S3 data lake bucket with versioning
- CloudWatch logging support
- Basic IAM configuration
- Terraform infrastructure deployment

Not in Phase 1:
- AWS Glue
- AWS Athena
- EventBridge orchestration
- SNS notifications
- full alerting workflows
- multi-region deployment

## Setup

### Prerequisites

- AWS account and credentials configured
- AWS CLI installed
- Terraform installed
- Python 3.11+ installed
- `pytest` installed for local tests

### Configure AWS

Use a profile with permission to create IAM, Lambda, API Gateway, Kinesis, and S3 resources.

```bash
aws configure --profile smartcity-sandbox
```

### Deploy Phase 1

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Get the API endpoint

```bash
tf output api_endpoint
```

### Test the ingestion endpoint

```bash
curl -X POST "$(tf output -raw api_endpoint)/telemetry" \
  -H "Content-Type: application/json" \
  -d '{"device_id":"sensor-1","temperature":28,"humidity":60}'
```

## Local testing

Install development dependencies:

```bash
python -m pip install pytest
```

Run the unit test:

```bash
python -m pytest test/test_ingestion.py
```

## CI/CD

This repository includes a GitHub Actions workflow that performs:

- Terraform formatting check
- Terraform init and validate
- Python unit tests

## Next steps

Phase 2 work is focused on analytics and event-driven notifications:

- AWS Glue data catalog and crawler for S3 telemetry data
- AWS Athena analytics database and workgroup
- EventBridge rule and SNS topic for S3 object notifications
- documentation and outputs for analytics artifacts
- additional testing for analytics workflows

After Phase 1, the next phases should add:

- automated alerting and CloudWatch dashboards
- EventBridge or SNS notification workflows (Phase 2 / 3)
- AWS Glue / Athena analytics layers (Phase 2)
- CI/CD deployment automation with environment promotion
- security hardening and least-privilege IAM


To Do
Add Athena sample queries:

Create example SQL queries for analyzing the data lake
Add query templates for common analytics patterns
Add Glue ETL job:

Create a Glue job for data transformation/processing
Schedule or trigger ETL pipelines
Expand notifications:

Add email/SMS subscriptions to SNS
Add CloudWatch alerts for pipeline failures
Add monitoring/dashboards:

CloudWatch metrics and alarms
Data pipeline dashboards in CloudWatch
Add sample data ingestion:

Test the pipeline with sample data uploads
Validate end-to-end data flow
=======
# sc-data-cloud-platform
smart city data cloud platform
>>>>>>> bb439dce543355d262e5ab120ac523c6a1454482
