# Design rules for Terraform modules built on Lambda durable functions

Lambda durable functions (GA since re:Invent 2025) introduce constraints that no
pre-existing Terraform module convention covers. These are the rules this module
follows, why each exists, and what breaks if you ignore it. Every one of them was
validated against a live deployment, not derived from documentation.

## Rule 1 — Never expose an unqualified function ARN

A durable execution can suspend for days and must resume against the **exact code
version that started it**. Lambda therefore rejects invocations of durable
functions by bare function name. The module:

- sets `publish = true` so every apply pins an immutable version,
- maintains an alias (`lambda_alias_name`, default `prod`) pointing at the latest
  version,
- exposes **only** the alias ARN (`orchestrator_qualified_arn`) as an output.

Consumers who wire up their own callers must use that output. If you hand them the
bare ARN they will get `InvalidParameterValueException` at invoke time — or worse,
`$LATEST` behavior where an in-flight execution replays against changed code and
fails non-deterministically.

## Rule 2 — Callback permissions need the versioned-ARN wildcard

The IAM resource for `lambda:SendDurableExecutionCallbackSuccess/Failure` is not
the function ARN. Callbacks are addressed as sub-resources of the **versioned**
function ARN:

```
arn:aws:lambda:REGION:ACCOUNT:function:NAME:VERSION/durable-execution/EXEC_ID/CALLBACK_ID
```

Granting on the bare function ARN or the alias ARN silently fails with
`AccessDeniedException` at callback time — after the function has already
suspended, which makes it painful to debug. The module grants on
`"${function_arn}:*"`. This is the single most common integration failure with
durable functions and the module makes it impossible to hit.

## Rule 3 — The execution role needs the durable managed policy

`AWSLambdaBasicExecutionRole` is not enough. Durable functions checkpoint through
`lambda:CheckpointDurableExecution` and `lambda:GetDurableExecutionState`, granted
by `AWSLambdaBasicDurableExecutionRolePolicy`. Without it the function fails on
its first `step()`. The module attaches both policies.

## Rule 4 — Ship the SDK in the deployment package, pinned

The managed runtimes bundle a copy of the durable execution SDK, but a runtime
update can change it **underneath an in-flight execution**, breaking replay
determinism. The module requires pre-built packages (`orchestrator_package`) and
documents that the SDK must be vendored and version-pinned. This module's
companion app learned this the concrete way: the published docs and the installed
SDK already disagreed on `wait_for_callback`'s signature within months of GA.

## Rule 5 — Two timeouts, two budgets

Durable functions have a per-invocation timeout (each replay slice, max 15 min)
and an execution timeout (the whole workflow, max 366 days). They are different
axes: one bounds compute, the other bounds wall-clock. The module exposes both
(`orchestrator_timeout_seconds`, `durable_execution_timeout_seconds`) and
validates their ranges, because setting only the Lambda timeout — the reflex from
standard Lambda — silently caps your workflow at 24 h (the execution-timeout
default).

## Rule 6 — Behavior is the contract, so test the behavior

A durable-function module that only tests "resources created successfully" has
tested nothing that matters: the failure modes live in suspend/resume, callback
delivery, and replay. The test suite in [`test/`](test) deploys the example,
drives a real execution through **start → suspend → external callback → resume →
publish**, and asserts the terminal state. `terraform validate` passing while the
callback IAM is broken is exactly the failure Rule 2 describes — only a
behavioral test catches it.

## Rule 7 — Cost posture is part of the interface

The economic reason durable functions exist is that waits are free. A module in
this domain should state its cost model and its guardrails, not leave them as an
exercise: see [Cost notes](README.md#cost-notes) and the
`*_reserved_concurrency` variables. Measured from live runs of the companion app:
a full pipeline run (5–7 Claude Haiku calls + Lambda compute + storage) lands in
the low single-digit cents; a 24-hour approval wait adds $0.00.
