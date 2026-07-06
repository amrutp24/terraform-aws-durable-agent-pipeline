# Complete example

Deploys the full pipeline: durable orchestrator, API Lambda + HTTP API,
DynamoDB, and S3.

The module takes pre-built Lambda packages, so build those first. The
orchestrator zip must bundle the durable execution SDK, and both need a
`lambda_function.py` with a `lambda_handler`. For working handler code, see the
companion app repo:
[durable-ai-agent-pipeline](https://github.com/amrutp24/durable-ai-agent-pipeline).

```bash
# 1. Build the packages this example zips up
mkdir -p build/orchestrator build/api
pip install aws-durable-execution-sdk-python -t build/orchestrator
cp your_orchestrator.py build/orchestrator/lambda_function.py
cp your_api.py          build/api/lambda_function.py

# 2. Deploy (needs Bedrock model access in the region if your handler calls it)
terraform init
terraform apply

# 3. Clean up
terraform destroy
```

The `api_endpoint` output is the base URL for `POST /posts`, `GET /posts/{id}`,
and `POST /posts/{id}/approve`.
