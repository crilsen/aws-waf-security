# Requirements

Product requirements describe what to build and why. PRDs are the source of truth for scope; agents treat them as requirements, not suggestions. Keep this file as a short index and store full PRDs under `docs/prd/`.

## Rules

- One PRD per feature or initiative, stored as `docs/prd/NNN-<slug>.md`.
- Status lifecycle: `Draft → Approved → Implemented → Superseded`.
- Only an **Approved** PRD drives implementation; use `.ai/workflows/feature.md`.
- Acceptance criteria must be concrete and testable, and validation maps back to them.
- Do not duplicate requirements here; link to the PRD.
- Record technical choices that a PRD depends on as ADR/TDR entries in `.ai/DECISIONS.md`.
- For large or risky work, a PRD can feed an optional spec-driven flow (`.ai/SPECS.md`, `docs/spec/`) that produces design, plan, and tasks before implementation.

## PRD format

```text
# PRD-NNN — Title
Status: Draft | Approved | Implemented | Superseded
Owner: <who>
Related decisions: ADR-NNN, TDR-NNN

Problem / Context:
...

Goals:
...

Non-goals:
...

Requirements:
- [ ] <requirement>

Acceptance criteria:
- [ ] <testable criterion>

Risks / Open questions:
...
```

## Index

| ID | Title | Status | Owner | File |
| --- | --- | --- | --- | --- |
| PRD-001 | AWS WAFv2 Regional Web ACL for an existing ALB (Terraform portfolio) | Approved | Repository owner | [`aws-waf-security.md`](../aws-waf-security.md) |

## Current requirements

### PRD-001 — AWS WAFv2 Regional Web ACL for an existing ALB

- Status: **Approved**. The user supplied the specification in `aws-waf-security.md` and asked for it to be implemented.
- The authoritative text lives in [`aws-waf-security.md`](../aws-waf-security.md); it is not duplicated here.
- Summary of the acceptance criteria:
  - the existing ALB ARN is mandatory and supplied explicitly by the operator;
  - Terraform never creates or modifies the ALB;
  - the Regional Web ACL is associated only with the provided ARN;
  - rules start in `COUNT`;
  - logs go to S3 through Amazon Data Firehose;
  - GitLab CI/CD and Jenkins each have their own pipeline;
  - in both, approval happens after `plan` and before `apply`;
  - both apply the same approved plan file without regenerating a plan;
  - no automatic apply and no deployment during this work;
  - documentation states the security requirements and project limits.
- Non-goals: Athena, Glue, CloudFront/global WAF, CAPTCHA, Bot Control, multi-region, multi-account, ALB creation.
