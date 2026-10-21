# Tools

The rules behind these lists live in `.ai/GUARDRAILS.md`.

## Current availability

Observed on 2026-10-21 (Linux / WSL2):

| Tool | Version | Use |
| --- | --- | --- |
| `terraform` | 1.16.1 | `fmt`, `init -backend=false`, `validate` |
| `aws-cli` | 2.37.4 | Documentation reference only; no authenticated calls |
| `docker` | 29.8.1 | Optional local tooling; no AWS access |
| `python3` | 3.14.4 (PyYAML 6.0.3) | YAML parsing for pipeline validation |
| `node` / `npm` | 22.22.1 / 9.2.0 | Optional pipeline/Jenkinsfile tooling |
| `jq` | 1.8.1 | JSON inspection |
| `shellcheck` | installed | Shell script linting |

Not installed: `tofu`, `tflint`, `checkov`, `trivy`, `yamllint`, `jenkins`, `groovy`.

AWS credentials: not configured and not required. Authentication requirements for the delivered project are documented in the README (OIDC / federated role), not used here.

Never store secrets in this file.

## Allowed without additional authorization

- Read and search repository files.
- Make scoped task-related edits.
- `terraform fmt`, `terraform init -backend=false`, `terraform validate`.
- `python3`/`jq` parsing of configuration files; `shellcheck` on repository scripts.
- Run read-only commands and safe dry runs.
- Initializing git and committing at stable checkpoints (authorized by the user on 2026-10-21).
- Update this portable context.

## Requires explicit authorization

- Any `terraform plan` that would reach AWS, and every `terraform apply` or `destroy`.
- Any authenticated AWS CLI call, including read-only ones.
- Deployment or production changes.
- Secret changes, destructive state operations, irreversible changes, paid-resource creation, or any external operation with material impact.
- Pushing to a remote, force push, history rewrite.

## MCP servers and external tools

| Tool or MCP server | Purpose | Allowed | Restricted |
| --- | --- | --- | --- |
| none configured | - | - | - |

When a tool changes how context is captured or validated, note it in `.ai/LEARNINGS.md` and, if durable, in this file.

## Technology-specific guidance

| Technology | Safe | Restricted |
| --- | --- | --- |
| Terraform | `fmt`, `init -backend=false`, `validate` | `plan` against AWS, `apply`, `destroy` |
| GitLab CI | YAML parse, static assertion | triggering a real pipeline, variables containing secrets |
| Jenkins | static structural checks | running the pipeline against a real controller |
| Static analysis | `shellcheck` | tools not installed; do not invent results |
