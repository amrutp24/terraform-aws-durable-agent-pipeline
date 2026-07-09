# Security Policy

## Supported versions

Only the latest release published to the
[Terraform Registry](https://registry.terraform.io/modules/amrutp24/durable-agent-pipeline/aws)
receives security fixes.

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Report privately via
[GitHub Security Advisories](https://github.com/amrutp24/terraform-aws-durable-agent-pipeline/security/advisories/new)
("Report a vulnerability"). You can expect an acknowledgement within 72
hours and a fix or mitigation plan within 14 days for confirmed issues.

## Scope

In scope:

- IAM grants broader than documented in [SECURITY_POSTURE.md](SECURITY_POSTURE.md)
  (in particular anything that widens the durable-callback grant beyond the
  orchestrator's own versioned ARNs)
- Any way to invoke the orchestrator or approve a pending run without the
  documented authorization path
- Defaults that silently disable a documented control

Out of scope:

- Vulnerabilities in consumer-supplied Lambda packages
- The `api_authorization_type = "NONE"` default (documented demo trade-off;
  set `AWS_IAM` in production)
- Findings already listed as reasoned exceptions in SECURITY_POSTURE.md
  (though arguments that an exception is wrong are welcome — open a regular
  issue for those)
