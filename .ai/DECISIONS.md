# Decision Records

Durable, meaningful choices. Two types:

- **ADR** — architecture decision: how the system is structured.
- **TDR** — technology decision: stack, library, provider, protocol, or tooling.

Status lifecycle: `Proposed → Accepted → Superseded | Deprecated`. ADR and TDR use separate ID sequences.

## Modes

Choose one mode per project and record the choice at adoption. The index below is used in both modes.

- **Simple (default):** entries live inline in this file. Best for small projects and up to roughly 15–20 active records.
- **Scale:** one file per record under `docs/decisions/`, named `ADR-NNN-<slug>.md` or `TDR-NNN-<slug>.md`. This file stays as the index only.

Migrate from simple to scale when the inline log gets unwieldy. Keep IDs stable during migration.

**This project uses simple mode** (chosen 2026-10-21 at adoption). Records are added inline under "Records" as the implementation makes real choices.

## Entry format

```text
## ADR-NNN / TDR-NNN — Title
Type: ADR | TDR
Status: Proposed | Accepted | Superseded | Deprecated
Date: YYYY-MM-DD
Owners: <who>
Supersedes: <ID or none>

Context:
...

Decision:
...

Reasoning:
...

Consequences:
...
```

## Index

| ID | Type | Title | Status | Date | File |
| --- | --- | --- | --- | --- | --- |
| ADR-001 | ADR | S3 buckets for logs and state are operator-provided | Accepted | 2026-10-21 | inline |
| ADR-002 | ADR | One Terraform file per WAF rule | Accepted | 2026-10-21 | inline |
| ADR-003 | ADR | WAF rule priority order | Accepted | 2026-10-21 | inline |
| TDR-001 | TDR | AWS WAFv2 Regional with Firehose to S3 logging | Accepted | 2026-10-21 | inline |
| TDR-002 | TDR | S3 native state locking instead of DynamoDB | Accepted | 2026-10-21 | inline |
| ADR-004 | ADR | Multi-region means one deployment per Region | Accepted | 2026-10-21 | inline |
| ADR-005 | ADR | Per-region rule policy in `env/<region>.tfvars` | Accepted | 2026-10-21 | inline |
| ADR-006 | ADR | CloudFront (global) scope with manual attachment | Accepted | 2026-10-21 | inline |

## Records

### ADR-001 — S3 buckets for logs and state are operator-provided

Type: ADR
Status: Accepted
Date: 2026-10-21
Owners: repository owner
Supersedes: none

Context:
The specification requires protecting the S3 log destination (encryption, access control, retention) and a secure remote state backend, but the operator already owns the buckets. Provisioning a state bucket from the same root module that uses it as a backend is impossible, and creating buckets would widen the blast radius of a security-focused plan.

Decision:
The project creates neither bucket. `log_bucket_name` is a required input; the state bucket is supplied at `terraform init` through `backend.hcl` or `-backend-config`. A `data "aws_s3_bucket"` lookup fails fast when the log bucket is missing, and a precondition rejects a log bucket in a different Region. Required bucket settings are documented in the README, not enforced by this module.

Reasoning:
Keeps bucket lifecycle, policies, and retention under the platform team that owns them; avoids a chicken-and-egg bootstrap inside the WAF module; keeps the plan limited to WAF, Firehose, and IAM.

Consequences:
- A misconfigured bucket (no TLS-only policy, no Block Public Access, no encryption) is only detected by review and the documented checklist.
- The Firehose role's permissions must be granted by the bucket policy, which this project documents but does not manage.
- `terraform plan` needs `s3:ListBucket`/`s3:GetBucketLocation` on the log bucket.

### ADR-002 — One Terraform file per WAF rule

Type: ADR
Status: Accepted
Date: 2026-10-21
Owners: repository owner
Supersedes: none

Context:
Each rule must be promotable to `BLOCK` independently, after observing metrics and logs. Rules defined inline in a single file are hard to review, diff, and promote one at a time.

Decision:
Every rule lives in its own top-level `waf_rule_<slug>.tf` file and exposes exactly one `local.rule_<slug>` object. `waf_rules.tf` aggregates the enabled rules into `local.waf_rules`; `waf.tf` renders them with a single `dynamic "rule"` block.

Reasoning:
Terraform only evaluates top-level `.tf` files in a root module, so a `rules/` subdirectory would silently not apply. One local per file keeps the diff of a rule promotion limited to one file.

Consequences:
- The rule shape is a typed object contract between each rule file and `waf.tf`; adding a statement type means extending the `dynamic` blocks in `waf.tf`.
- Optional rules (empty IP lists, no geo restriction) contribute zero entries to `local.waf_rules`.

### ADR-003 — WAF rule priority order

Type: ADR
Status: Accepted
Date: 2026-10-21
Owners: repository owner
Supersedes: none

Context:
AWS WAF evaluates rules by ascending priority and stops at the first terminating action. Ordering changes both security behavior and cost.

Decision:

| Priority | Rule | Action |
| --- | --- | --- |
| 0 | IP allow list | allow |
| 5 | IP deny list | COUNT or BLOCK |
| 10 | AWSManagedRulesCommonRuleSet | override_action none or count |
| 20 | AWSManagedRulesKnownBadInputsRuleSet | override_action none or count |
| 30 | Geo restriction | COUNT or BLOCK |
| 40 | Rate limit per IP | COUNT or BLOCK |

Reasoning:
The allow list short-circuits first so trusted automation is not throttled. The deny list is cheap and blocks known-bad sources before managed rules run. Managed rules run before geo and rate limiting so their verdicts are not masked; rate limiting runs last so already-blocked requests do not consume the rate counter.

Consequences:
- A source in both lists is allowed, because the allow list wins. This is documented.
- Promoting the deny list to `BLOCK` requires a new plan and a new approval, like every other promotion.

### TDR-001 — AWS WAFv2 Regional with Firehose to S3 logging

Type: TDR
Status: Accepted
Date: 2026-10-21
Owners: repository owner
Supersedes: none

Context:
The Web ACL protects a Regional ALB, and logs must land in S3 through Amazon Data Firehose.

Decision:
Use `aws_wafv2_web_acl` with `scope = "REGIONAL"`, `aws_wafv2_web_acl_association` bound to the supplied ALB ARN, and `aws_wafv2_web_acl_logging_configuration` with an `aws_kinesis_firehose_delivery_stream` (`DirectPut`, `extended_s3_configuration`, GZIP) as the destination. Redact `authorization` and `cookie` headers by default.

Reasoning:
Regional scope is the only valid scope for an ALB. Firehose buffers and compresses records, which is cheaper than direct S3 delivery and is the AWS-recommended path.

Consequences:
- Global (CloudFront) WAF stays out of scope.
- Firehose naming uses the `aws-waf-logs-` prefix required by AWS tooling.
- Redaction limits some header-based investigations; the list is a variable.

### TDR-002 — S3 native state locking instead of DynamoDB

Type: TDR
Status: Accepted
Date: 2026-10-21
Owners: repository owner
Supersedes: none

Context:
State must be encrypted and locked, and the operator provides only the bucket. DynamoDB would require an extra table and extra permissions.

Decision:
Use the S3 backend with `encrypt = true` and `use_lockfile = true` (Terraform >= 1.10). Both pipelines initialize with `-backend-config` pointing at the operator's bucket.

Reasoning:
Removes a DynamoDB dependency and the IAM surface that comes with it; the lock lives next to the state object.

Consequences:
- Terraform < 1.10 cannot initialize this backend.
- Pipelines pin Terraform 1.16.x.

### ADR-004 — Multi-region means one deployment per Region

Type: ADR
Status: Accepted
Date: 2026-10-21
Owners: repository owner
Supersedes: none (the original specification excluded multi-region from the MVP; this records the later request)

Context:
The owner asked to consider multi-region. A WAFv2 Web ACL is always regional, so protecting ALBs in several Regions requires one Web ACL, one association, and one Firehose stream per Region. The specification still excludes CloudFront/global WAF and multi-account.

Decision:
The project supports multi-region by running the same root module once per Region, each with its own state. The operator supplies `aws_region` and the matching ALB ARN; the state key is `aws-waf-security/<region>/terraform.tfstate`. Pipelines take `AWS_REGION` as a parameter/protected variable and derive the state key from it, so each Region is planned, approved, and applied independently.

Reasoning:
- No provider aliases and no dynamic `for_each` over Regions, which Terraform cannot express cleanly.
- A failure or a bad plan in one Region cannot affect another Region's Web ACL.
- Approvals stay per Region, because each Region has its own plan artifact and protected environment.
- State locking remains native to S3 with one lock per Region.

Consequences:
- Adding a Region is a configuration change plus a new pipeline run, not a new resource block.
- Cross-Region aggregates (one dashboard for all Regions) are out of scope; each Region has its own metrics and log prefix. The log prefix includes the Region in the pipeline configuration, so objects do not collide in a shared bucket.
- Global WAF for CloudFront and multi-account are still out of scope.

### ADR-005 — Per-region rule policy in `env/<region>.tfvars`

Type: ADR
Status: Accepted
Date: 2026-10-21
Owners: repository owner
Supersedes: none

Context:
The owner needs a different rule set and different actions per Region. Before this decision, `rule_mode` was a single switch for deny list, geo, rate limit, and both managed rule groups, and the rule catalog could not be changed without editing code. Pipeline variables exposed only four inputs, so per-region tuning required editing the pipeline itself.

Decision:
- `enabled_rules` (set of rule names) decides which rules exist in a Region.
- `rule_actions` (map of rule name to `COUNT`/`BLOCK`) overrides `rule_mode` per rule.
- The reviewed policy for each target lives in `env/<scope>/<region>.tfvars`, is committed, and is loaded by both pipelines through `-var-file="env/<scope>/<region>.tfvars"`. Plan fails when the file is missing.
- `rule_mode` remains the default for any rule not listed in `rule_actions`.

Reasoning:
Policy becomes reviewable in a diff, one Region can be promoted independently, and the pipeline keeps passing only the values that are genuinely environment-specific (ALB ARN, buckets, region, role).

Consequences:
- A policy change is a commit + merge request + plan + approval, not a pipeline parameter change.
- `env/*.tfvars` must never hold secrets; `.gitignore` re-includes `env/*/*.tfvars` on purpose.
- `terraform validate` does not evaluate variable values, so policy edits must also be checked with `terraform console -var-file=...` or a plan. This is documented in the README.
- The rule catalog is still fixed: `enabled_rules` selects among the six supported rules; a new statement type is a code change.

### ADR-006 — CloudFront (global) scope with manual attachment

Type: ADR
Status: Accepted
Date: 2026-10-21
Owners: repository owner
Supersedes: none (the original specification excluded CloudFront/global WAF; this records the later request)

Context:
The owner asked to also cover a CloudFront distribution. A CloudFront Web ACL is global, must be created in `us-east-1`, and has no standalone association resource: AWS attaches it only through `web_acl_id` on the distribution. Managing the distribution is outside this project's remit (it never creates or changes entry points).

Decision:
`waf_scope` selects `REGIONAL` (default) or `CLOUDFRONT`.
- `CLOUDFRONT` requires `aws_region = "us-east-1"` and rejects a non-null `alb_arn`; both are input validations.
- The association resource is created only for `REGIONAL`.
- For `CLOUDFRONT`, the project outputs `web_acl_arn` and the distribution owner sets `web_acl_id` in the stack that manages the distribution.
- Logging uses the same Firehose path, in `us-east-1`, because Firehose cannot deliver across Regions.

Reasoning:
- Keeps the project's hard boundary: it never mutates the resource it protects.
- Avoids the alternative of importing and managing the CloudFront distribution just to set one attribute.
- Uses the same module, rules, policy files, and approval gate for both scopes.

Consequences:
- CloudFront protection is two-step: apply this project, then attach the ARN in the distribution stack. The README documents it and the outputs make the ARN explicit.
- A CloudFront deployment needs its own policy file (`env/cloudfront/us-east-1.tfvars`), state key, and approval; it is a separate target, not a Region.
- Destroying the CloudFront ACL requires detaching `web_acl_id` first, otherwise AWS refuses to delete an in-use ACL.
- CloudFront global scope is still single-account: multi-account remains out of scope.





Do not backfill invented history. Record decisions that are observed, expressly documented, or approved during future work.

The design rationale for this template itself lives in [`docs/design.md`](../docs/design.md).
