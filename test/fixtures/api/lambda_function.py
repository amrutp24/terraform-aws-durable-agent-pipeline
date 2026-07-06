"""Minimal API fixture - the behavioral test drives the orchestrator directly,
so this only needs to deploy successfully."""


def lambda_handler(event, context):
    return {"statusCode": 200, "body": "ok"}
