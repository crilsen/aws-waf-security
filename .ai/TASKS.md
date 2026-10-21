# Current Work

## Active

- Nothing in progress. PRD-001 is implemented, validated locally, and published.

## Planned

1. Optional hardening not in the MVP: CloudWatch alarms on `BlockedRequests`, WAF logging filter to reduce log volume, IPv6 IP sets.
2. First real usage: create the deployment role and state/log buckets outside this repository, then run the GitLab or Jenkins pipeline for one Region in `COUNT` mode.

## Blocked

- `terraform plan`/`apply` and any AWS call remain out of scope for this repository: they need real buckets, a real ALB ARN, and credentials.

## Completed

- 2026-10-21: populated `.ai/` from observed facts and recorded PRD-001.
- 2026-10-21: initialized git, added `.gitignore`, published to `github.com/crilsen/aws-waf-security`.
- 2026-10-21: recorded ADR-001..ADR-004 and TDR-001..TDR-002.
- 2026-10-21: implemented the Terraform module with one file per rule, operator-provided log and state buckets, Firehose logging, and least-privilege IAM.
- 2026-10-21: implemented `.gitlab-ci.yml` (validate → plan → approval → apply, OIDC, plan artifact + checksum) and `Jenkinsfile` (same gate, stashed plan, restricted submitter).
- 2026-10-21: added `scripts/assume-role.sh`, `scripts/require-env.sh`, `scripts/validate.sh`, `tests/check_pipelines.py`, and `docs/iam/*.json`.
- 2026-10-21: wrote the README covering every section required by the specification.
- 2026-10-21: validated with `terraform fmt -check`, `init -backend=false`, `validate`, pipeline static checks, and `shellcheck`; all passed.
