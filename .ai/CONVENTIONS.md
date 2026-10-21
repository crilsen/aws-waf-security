# Conventions

## Annotation language

- English for code comments and relay `.md` files (`AGENTS.md`, `.ai/`, `docs/`, `README.md`, PRD/spec/decision records).
- Chosen by the user on 2026-10-21 for this session. It was not declared a standing preference, so confirm again on a new task or session unless the user states otherwise.
- The source specification `aws-waf-security.md` is written in Portuguese and stays as provided; project deliverables are written in English.

## Terraform

No Terraform code exists yet. These conventions apply to the implementation that follows the specification:

- Terraform 1.x syntax; one root module plus reusable locals; no providers beyond `aws` (and `random` only if genuinely needed).
- Files split by concern: `versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `waf.tf`, `logging.tf`, `outputs.tf`, `locals.tf`, `terraform.tfvars.example`.
- All tunables are variables with explicit `description`, `type`, and safe defaults. Values that must be supplied by the operator (ALB ARN) have no default.
- Validate the ALB ARN format in a `variable` validation block, including the `arn:aws:elasticloadbalancing:` prefix and Region consistency with the configured provider Region.
- Rules ship in `COUNT` by default through a variable that selects the mode; `BLOCK` is never the initial default.
- Tag every taggable resource with a shared `local.tags` map; no account IDs, domains, or identifiers from third parties.
- No hardcoded credentials, regions with real account data, or example values that look real. Examples use fictional values only.
- Run `terraform fmt -recursive` before considering work complete.

## Pipelines

- GitLab configuration lives in `.gitlab-ci.yml` at the repository root.
- Jenkins configuration lives in `Jenkinsfile` at the repository root, declarative pipeline syntax.
- Both pipelines must expose the plan as an artifact and gate `apply` behind a manual approval.
- No secrets in pipeline files; AWS credentials come from OIDC/federated roles.

## Documentation

- `README.md` at the root is the entry point and must cover every section required by `aws-waf-security.md`.
- Reference authoritative documents instead of copying them.
- Keep `TASKS.md` current-state only and `HANDOFF.md` operational, not a chat transcript.
- Treat `LEARNINGS.md` as a bounded, append-only buffer; promote durable learnings into `CONVENTIONS.md`, `DECISIONS.md`, `TOOLS.md`, or `VALIDATION.md`.
- Keep tool-specific files as thin adapters that only route to `AGENTS.md`; record their paths in `.ai/ADAPTERS.md`.
- Keep the Resume block in `HANDOFF.md` current as a rolling checkpoint and honor the thresholds in `.ai/LIMITS.md`.
- Only the primary agent writes `HANDOFF.md`, `TASKS.md`, and `LEARNINGS.md`; subagents report back instead of committing shared state.
- Use simple mode for decision records (inline in `DECISIONS.md`); this project is small enough that scale mode is unnecessary.
