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

- `terraform plan` requires AWS credentials and a real ALB ARN. **Not permitted** for this project; do not run it.
- `terraform apply` / `destroy` are always forbidden (see `TOOLS.md`).
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
