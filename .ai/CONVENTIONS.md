# Conventions

## Annotation language

- English for code comments and relay `.md` files (`AGENTS.md`, `.ai/`, `docs/`, `README.md`, PRD/spec/decision records).
- Chosen by the user on 2026-10-21 for this session. It was not declared a standing preference, so confirm again on a new task or session unless the user states otherwise.
- The source specification `aws-waf-security.md` is written in Portuguese and stays as provided; project deliverables are written in English.

## Terraform

No Terraform code exists yet. These conventions apply to the implementation that follows the specification:

- Terraform 1.x syntax; one root module plus reusable locals; no providers beyond `aws` (and `random` only if genuinely needed).
- Files split by concern: `versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `waf.tf`, `logging.tf`, `outputs.tf`, `locals.tf`, `terraform.tfvars.example`.
- `waf_scope` selects `REGIONAL` (ALB, association resource) or `CLOUDFRONT` (global, `us-east-1` only, no association resource). Never attach a CLOUDFRONT ACL by managing another team's distribution.
- Every resource name derives from `local.name_base = "<name_prefix>-<scope>-<region>"`. Never build a resource name directly from `var.name_prefix`: scope and Region must be present so targets cannot collide and are identifiable. Keep `name_prefix` <= 24 characters to stay inside IAM/Firehose name limits.
- Every taggable resource must carry `Scope` and `Region` tags through `local.tags`; add cross-target identifiers there, not by parsing names.
- All tunables are variables with explicit `description`, `type`, and safe defaults. Values that must be supplied by the operator (ALB ARN for `REGIONAL`, log bucket name) have no default.
- Validate the ALB ARN format in a `variable` validation block; enforce Region consistency with the provider Region through a resource precondition.
- One Terraform file per WAF rule (`waf_rule_<name>.tf`), each exposing a single `local.rule_<name>`; `waf_rules.tf` aggregates them and `waf.tf` renders them with `dynamic "rule"`. Never define WAF rules inline in `waf.tf`.
- Every rule object must be merged into `local.rule_defaults` and `local.statement_defaults` so all rules share one attribute shape. Use concrete zero values (`""`, `0`, `tolist([])`) instead of `null` or `{}`: `concat` requires exactly matching types, and `null`/`{}`/`tomap({})` produce `DynamicPseudoType`/`EmptyObject`/`map(dynamic)` that do not unify with `string`/`map(string)`.
- Never put an optional map inside a shared object shape. Keep it in a separate local keyed by rule name and resolve it with `lookup()` where it is used.
- `terraform validate` does not evaluate provider-resolved types. Run a real read-only plan (or a `terraform test` with mocks) after changing the rule aggregation.
- Per-region behavior belongs in `env/<scope>/<region>.tfvars` (`enabled_rules`, `rule_actions`, thresholds, lists), never in pipeline-specific parameters. Pipelines pass only environment values (ALB ARN when applicable, buckets, region, scope, role).
- Pipeline logic lives in `scripts/tf-init.sh`, `tf-plan.sh`, and `tf-apply.sh`, so GitLab and Jenkins stay thin and cannot drift. `tf-apply.sh` must never call `terraform plan`.
- Rules ship in `COUNT` by default through a variable that selects the mode; `BLOCK` is never the initial default. The IP allow list always evaluates to `allow`, because it is an operator exception, not a detection rule.
- Never create, delete, or modify the S3 buckets for logs or state. Reference them through variables, `data` sources, and backend configuration only.
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
