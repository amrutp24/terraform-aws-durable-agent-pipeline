#!/usr/bin/env bash
# Builds the behavioral-test fixture packages (vendors the durable SDK).
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/orchestrator build/api

pip install aws-durable-execution-sdk-python -t build/orchestrator --quiet
cp orchestrator/lambda_function.py build/orchestrator/
cp api/lambda_function.py build/api/

echo "fixtures built"
