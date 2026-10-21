# Validation

## Completion rule

Before completion, run all applicable project validations that are available and safe. Report each as **Validated**, **Partially validated**, or **Not validated**, with the reason for anything not run. Never claim validation that did not occur.

## Terraform

Available locally (`terraform` 1.16.1):

```bash
terraform fmt -check -recursive          # formatting gate
terraform init -backend=false -input=false   # provider download only, no backend
terraform validate                       # configuration validity
```

- `terraform plan` is allowed **read-only** with explicit authorization from the operator, because it only reads data sources and never mutates AWS. Prefer a local state (`init -backend=false` in a scratch copy) so the operator's backend is never touched.
- `terraform apply` requires **explicit authorization** from the operator for that specific change, must apply a reviewed plan file, and must be recorded in `HANDOFF.md`. Never apply automatically.
- `terraform destroy` requires the same explicit authorization and a reviewed plan.
- A real read-only plan was executed on 2026-10-21 against a real account in `us-east-1` (ALB ARN supplied at runtime, log bucket `cn-logs-us-east-1`): 9 resources to add, no changes to existing resources.
- An authorized apply was executed on 2026-10-21: Web ACL and association created in `us-east-1`, logging disabled because the account blocks Firehose creation (`SubscriptionRequiredException`).
- An authorized destroy was executed on 2026-10-21 from a reviewed `-destroy` plan: association, Web ACL, and IP set removed; the ALB has no WAF. Only the empty state object remains in the operator's bucket.
- A real Jenkins pipeline run (build #6, 2026-10-21) completed Validate → Plan → Approval → Apply. The first Apply attempt exposed a missing `elasticloadbalancing:SetWebACL` permission in the deployer policy; fixed and re-applied successfully.
- Not available: `tflint`, `checkov`, `trivy`. Record as "Not validated — tool not installed" rather than claiming a pass.

## Pipeline configuration

- GitLab: parse `.gitlab-ci.yml` with PyYAML (`python3 -c "import yaml,sys; yaml.safe_load(open('.gitlab-ci.yml'))"`) to prove it is valid YAML.
- Jenkins: parse the declarative `Jenkinsfile` structure by static checks (balanced braces, required stages present, no `input` on `apply` bypass). `jenkins` and `groovy` are not installed, so full pipeline parsing is not possible.
- Assert statically that both pipelines gate `apply` on both the plan artifact and a manual approval, and that neither regenerates a plan after approval.

## Shell and security checks

- `shellcheck` any shell script added to the repository.
- Grep the tree for committed secrets, state files, and plan files; confirm `.gitignore` covers them.

## Documentation checks

1. Confirm the annotation language matches `.ai/HANDOFF.md` (`Annotation language: English`).
2. Confirm every README section required by `aws-waf-security.md` exists.
3. Confirm acceptance criteria in the specification map to a validation or an explicit limitation.

## Acceptance criteria traceability

Each acceptance criterion in `aws-waf-security.md` must be verifiable from the repository. Validation is by static inspection plus `fmt`/`validate`; runtime behavior against AWS is out of scope and must be stated as not validated.
