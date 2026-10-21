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
- 2026-10-21: implemented per-region policy (ADR-005): `enabled_rules`, `rule_actions`, and `env/<region>.tfvars` loaded by both pipelines; removed `RULE_MODE` from pipeline parameters so policy changes are reviewed in git.
- 2026-10-21: fixed a plan-time `concat` panic caused by a tuple-typed `country_codes`; defaults now use `tolist([])`, verified with `terraform console` for both Regions and for per-rule BLOCK overrides.
- 2026-10-21: added `waf_scope` (`REGIONAL`/`CLOUDFRONT`) with validation that CloudFront uses `us-east-1` and omits `alb_arn`; the association resource exists only for `REGIONAL` (ADR-006).
- 2026-10-21: moved pipeline logic into `scripts/tf-init.sh`, `tf-plan.sh`, and `tf-apply.sh`; both pipelines now call the same scripts, and policy files moved to `env/<scope>/<region>.tfvars`.
- 2026-10-21: validated all three targets with `terraform console` (regional eu-west-1, regional us-east-1, cloudfront us-east-1) and confirmed the two CloudFront rejections.
