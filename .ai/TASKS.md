# Current Work

## Active

- Context bootstrap: `.ai/` was still the `ai-agent-relay` template and has been populated with facts observed from this repository and from `aws-waf-security.md` (2026-10-21).

## Planned

Implementation of PRD-001 (`aws-waf-security.md`), in this order:

1. Repository skeleton: `.gitignore`, `README.md` outline, `docs/` layout.
2. Terraform root module: `versions.tf`, `providers.tf`, `variables.tf` (including ALB ARN format and Region validation), `locals.tf`.
3. Web ACL: default action, AWS Managed Rules (Common Rule Set, Known Bad Inputs), IP rate limit, optional allow/deny IP lists, optional geo blocking — all defaulting to `COUNT`.
4. Association resource bound to the supplied ALB ARN only.
5. Logging: S3 bucket (encryption, access control, retention), Amazon Data Firehose delivery stream, WAF logging configuration, required IAM.
6. Outputs and `terraform.tfvars.example` with fictional values.
7. `.gitlab-ci.yml`: fmt/validate on branches and merge requests, plan/apply on the protected default branch, plan artifact, manual approval, OIDC.
8. `Jenkinsfile`: declarative, parameters for Region and ALB ARN, Validate → Plan → Approval → Apply, plan preserved between stages, IAM role credentials.
9. `README.md`: all sections required by the specification, including backend setup, least-privilege IAM, COUNT→BLOCK promotion, troubleshooting, cost, cleanup, limitations.
10. Validation: `terraform fmt`, `terraform init -backend=false`, `terraform validate`, YAML parse, static pipeline assertions, `shellcheck`; report what could not run.

## Blocked

- Nothing blocking. `terraform plan`/`apply` and AWS access are intentionally out of scope and must not be performed.

## Completed

- 2026-10-21: populated `.ai/PROJECT.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `VALIDATION.md`, `TOOLS.md`, `REQUIREMENTS.md`, `HANDOFF.md`, `TASKS.md`.
- 2026-10-21: initialized git and added `.gitignore` covering Terraform state/plans, local variable files, secrets, and CI artifacts.
