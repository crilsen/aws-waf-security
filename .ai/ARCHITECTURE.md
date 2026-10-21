# Architecture

## Current repository state

Observed: the repository contains only `AGENTS.md`, `aws-waf-security.md`, and `.ai/`. There is no Terraform code, pipeline definition, or project documentation yet.

The architecture below is **specified** by `aws-waf-security.md` and is **not implemented** at the time of this writing.

## Target architecture (specified)

```text
Internet
   │
   ▼
[existing ALB]                  ← not created or modified by this project
   │  ARN provided as TF variable / GitLab variable / Jenkins parameter
   │  must be in the same Region as the Web ACL
   ▼
AWS WAFv2 Regional Web ACL
   ├─ default action (configurable)
   ├─ AWS Managed Rules: Common Rule Set, Known Bad Inputs
   ├─ rate limit per IP (configurable)
   ├─ optional allow list of IPs
   ├─ optional deny list of IPs
   └─ optional geographic blocking (configurable)
        │
        ├─ metrics + sampled requests
        └─ logs → Amazon Data Firehose → S3 (encrypted, access-controlled, retention)
```

Rule evaluation order and precedence across the optional lists are still to be designed during implementation and recorded in `DECISIONS.md`.

## Boundaries

- The project creates the Web ACL, its association to the provided ALB ARN, the Firehose delivery stream, the log bucket, and supporting IAM.
- The ALB is an input, never a managed resource. A plan must not propose changes to the ALB.
- Terraform state uses a remote backend with encryption, versioning, and locking. The backend is documented, not provisioned by this project.

## Delivery architecture

- **GitLab CI/CD:** format and validate on branches and merge requests; `plan` and `apply` restricted to the protected default branch; plan exposed as a restricted, short-lived artifact; manual approval job after `plan`; `apply` depends on both the artifact and the approval; protected environment where available; ALB ARN supplied as a protected variable; AWS access through OIDC with temporary credentials.
- **Jenkins:** declarative `Jenkinsfile` with parameters for AWS Region and existing ALB ARN; stages `Validate` → `Plan` → `Approval` → `Apply`; deployment restricted to the protected default branch; manual approval limited to an authorized user or group; the plan file is preserved between stages; temporary credentials from an IAM role.
- Both pipelines apply the exact binary plan file approved earlier and never regenerate a plan after approval.

## Context-layer layout

```text
Tool-specific adapter (optional)
            ↓
        AGENTS.md
            ↓
          .ai/
  project · architecture · conventions · decisions
  tasks · handoff · tools · validation · workflows · prompts
```

`.ai/` is the portable source of truth. Tool-specific adapters must only route agents to it.

## Applicable workflows

- `terraform-change.md` — applies once Terraform code exists.
- `install`/CI workflows for pipeline edits.
- Not applicable: `kubernetes-change.md` (no Kubernetes in this project) and `cloud-port.md` (single cloud provider by design).

## Recommended convention

Document the architecture that exists, not an idealized future design. Mark facts as observed, inferences as inferred, proposed patterns as recommended, and unavailable facts as unknown.
