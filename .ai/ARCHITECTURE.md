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
        └─ logs → Amazon Data Firehose → [operator-provided S3 bucket]
```

Rule evaluation order (priority): IP allow list, IP deny list, AWS Managed Common Rule Set, AWS Managed Known Bad Inputs, geo restriction, rate limit. Rationale is recorded in `DECISIONS.md`.

## Rule file layout

Terraform does not read subdirectories of a root module, so each rule lives in its own top-level file and is aggregated by `waf_rules.tf`:

```text
waf_rule_ip_allowlist.tf          priority 0    action allow (always)
waf_rule_ip_denylist.tf           priority 5    COUNT | BLOCK
waf_rule_managed_common.tf        priority 10   override_action none | count
waf_rule_managed_known_bad_inputs.tf  priority 20   override_action none | count
waf_rule_geo.tf                   priority 30   COUNT | BLOCK
waf_rule_rate_limit.tf            priority 40   COUNT | BLOCK
waf_ip_sets.tf                    optional aws_wafv2_ip_set resources
waf.tf                            web ACL + association
```

## Operator-owned buckets

- **Logs bucket:** name is a required variable. The project creates the Firehose delivery stream, its IAM role, and the WAF logging configuration, but not the bucket or its policy. A `data "aws_s3_bucket"` lookup fails fast when the bucket is missing, and a precondition rejects a bucket in a different Region.
- **State bucket:** configured at `terraform init` time through `backend.hcl` or `-backend-config`. Backend block enables encryption and S3 native state locking (`use_lockfile`), so no DynamoDB table is required. The bucket, versioning, encryption, and Block Public Access are the operator's responsibility and are documented in the README.

## Boundaries

- The project creates the Web ACL, its association to the provided ALB ARN, the optional IP sets, the Firehose delivery stream, and the supporting IAM.
- The ALB and both S3 buckets are inputs, never managed resources. A plan must not propose changes to them.
- Terraform state uses a remote backend with encryption and locking, both supplied by the operator.

## Delivery architecture

- **GitLab CI/CD:** format and validate on branches and merge requests; `plan` and `apply` restricted to the protected default branch; plan exposed as a restricted, short-lived artifact; manual approval job after `plan`; `apply` depends on both the artifact and the approval; protected environment where available; ALB ARN supplied as a protected variable; AWS access through OIDC with temporary credentials.
- **Jenkins:** declarative `Jenkinsfile` with parameters for AWS Region and existing ALB ARN; stages `Validate` → `Plan` → `Approval` → `Apply`; deployment restricted to the protected default branch; manual approval limited to an authorized user or group; the plan file is preserved between stages; temporary credentials from an IAM role.
- Both pipelines apply the exact binary plan file approved earlier and never regenerate a plan after approval.

## Multi-region

Each Region is an independent deployment with its own state (`aws-waf-security/<region>/terraform.tfstate`), its own Web ACL, Firehose stream, and protected environment. There is no single apply that spans Regions, and no global (CloudFront) Web ACL. Rationale: ADR-004.

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
