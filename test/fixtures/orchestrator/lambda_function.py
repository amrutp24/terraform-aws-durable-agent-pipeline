"""
Behavioral-test fixture: the smallest durable function that exercises every
module guarantee - checkpointed steps (Rule 3 IAM), suspension via
wait_for_callback (Rule 2 IAM from the outside), and replay.

Deliberately Bedrock-free so the test runs in any account without model access.
"""

import json
import os

import boto3
from aws_durable_execution_sdk_python import DurableContext, durable_execution
from aws_durable_execution_sdk_python.config import Duration, WaitForCallbackConfig

table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
s3 = boto3.client("s3")


@durable_execution
def lambda_handler(event, context: DurableContext):
    run_id = event["run_id"]

    # Step: proves checkpoint permissions work
    marker = context.step(lambda _: f"step-completed-{run_id}", name="marker")

    # Suspend: proves an external caller can deliver a callback
    def publish_callback_id(callback_id, _ctx):
        table.put_item(Item={"execution_id": run_id, "callback_id": callback_id})

    payload_raw = context.wait_for_callback(
        publish_callback_id,
        name="test-callback",
        config=WaitForCallbackConfig(timeout=Duration.from_seconds(600)),
    )
    payload = json.loads(payload_raw) if payload_raw else {}

    # Resume: proves replay reached the code after the wait
    def write_result(_):
        s3.put_object(
            Bucket=os.environ["BUCKET_NAME"],
            Key=f"{run_id}.json",
            Body=json.dumps({"marker": marker, "echo": payload}).encode(),
            ContentType="application/json",
        )
        return "written"

    context.step(write_result, name="write-result")
    return {"run_id": run_id, "status": "DONE"}
