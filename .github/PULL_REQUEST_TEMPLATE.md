## What

<!-- One or two sentences: what changes and why. -->

## Checklist

- [ ] `terraform fmt -recursive` and `terraform validate` pass
- [ ] `tflint` passes
- [ ] `terraform-docs -c .terraform-docs.yml .` run (README tables up to date)
- [ ] Checkov + Trivy pass; any new exception is inline-reasoned **and** added to SECURITY_POSTURE.md
- [ ] CHANGELOG.md updated for user-visible changes
- [ ] IAM / durable-execution changes checked against DESIGN.md constraints

## Breaking change?

<!-- Does this change defaults, rename variables, or alter created resources
     in a way that forces replacement? Say so explicitly. -->
