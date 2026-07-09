# Contributing

Thanks for taking the time to contribute!

## Development setup

```bash
git clone https://github.com/amrutp24/terraform-aws-durable-agent-pipeline
cd terraform-aws-durable-agent-pipeline
terraform init -backend=false
terraform validate
```

## Before opening a PR

1. **Format**: `terraform fmt -recursive` (CI rejects unformatted code).
2. **Validate**: `terraform validate` on the module and `examples/complete`
   (create empty `build/orchestrator` and `build/api` stubs first — see
   `.github/workflows/ci.yml` for the exact commands).
3. **Lint**: `tflint --init && tflint`.
4. **Docs**: variable/output changes must be reflected in the README —
   run `terraform-docs -c .terraform-docs.yml .` (CI fails on drift).
5. **Security scans**: `checkov -d . --framework terraform` and
   `trivy config .` must pass. If a finding is a deliberate trade-off, add an
   inline reasoned `#checkov:skip` / `.trivyignore` entry **and** document it
   in [SECURITY_POSTURE.md](SECURITY_POSTURE.md) — unexplained suppressions
   are not accepted.
6. **Tests**: `cd test && go vet ./... && go test -run TestExampleValidates`.
   The live durable-lifecycle test needs AWS credentials and deploys real
   infrastructure; it's gated behind the `TERRATEST_ENABLED` repo variable.

## Design constraints

Read [DESIGN.md](DESIGN.md) before changing the orchestrator/callback IAM or
the alias/versioning setup — durable functions have non-obvious requirements
(qualified ARNs, callback sub-resources) that look like they can be
"simplified" but can't.

## Versioning

Releases are tagged manually following SemVer. Note user-visible changes in
[CHANGELOG.md](CHANGELOG.md).

## Reporting bugs / requesting features

Use the issue templates. For security vulnerabilities, **do not open a
public issue** — see [SECURITY.md](SECURITY.md).
