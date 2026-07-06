# Changelog

All notable changes to this module. Versions follow [SemVer](https://semver.org).

## [1.3.1] - 2026-07-06

### Changed
- License changed from MIT to Apache-2.0 (explicit patent grant; matches the Terraform module ecosystem convention). Added NOTICE file.

## [1.3.0] - 2026-07-05

### Added
- Three usage scenarios in the README (minimal, tuned, locked-down SigV4)
- terraform-docs generated reference (requirements/providers/resources/inputs/outputs), with a CI check that fails when docs drift from the code

## [1.2.3] - 2026-07-05

### Added
- README for `examples/complete` (removes the registry's "internal-only" notice)

## [1.2.1] / [1.2.2] - 2026-07-05

### Changed
- README wording cleanups

## [1.2.0] - 2026-07-05

### Added
- `api_authorization_type` variable — set `AWS_IAM` to require SigV4-signed API requests (default `NONE`)
- Validation blocks on 9 constrained variables (runtime allow-list, durable limits, CloudWatch retention values, score/revision ranges, project naming)
- S3 server-side encryption (SSE-S3) and versioning on the posts bucket
- DynamoDB point-in-time recovery on the executions table
- Behavioral test suite ([`test/`](test)): live durable-lifecycle test proving start → checkpoint → suspend → external callback → resume → result
- Security scanning in CI: Checkov and tfsec, hard-fail, with every exception inline-reasoned
- [`DESIGN.md`](DESIGN.md) — the seven rules for building Terraform modules on Lambda durable functions
- [`SECURITY_POSTURE.md`](SECURITY_POSTURE.md) — implemented controls, reviewed exceptions, data classification

## [1.1.1] - 2026-07-05

### Changed
- Registry-friendly README: inputs/outputs as lists, deferring detail to the registry's generated tabs

## [1.1.0] - 2026-07-05

### Added
- `lambda_alias_name`, `handler`, `api_memory_mb`, `api_timeout_seconds` variables (previously hardcoded)

## [1.0.0] - 2026-07-05

### Added
- Initial release: durable orchestrator (version + alias, checkpoint IAM), API Lambda + HTTP API, DynamoDB, S3, least-privilege IAM including the versioned-ARN callback wildcard
