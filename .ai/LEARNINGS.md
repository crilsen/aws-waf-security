# Learnings

Append-only buffer of reusable, non-obvious learnings captured while working, so future sessions and tools do not rediscover them. This is not task state (`TASKS.md`), not a session handoff (`HANDOFF.md`), and not a durable decision record (`DECISIONS.md`).

## How to use

- Append one entry per learning. Do not rewrite or delete entries; to correct one, mark it `superseded` and add a new entry.
- Capture only learnings that are non-obvious and likely to recur. Skip anything already stated in `CONVENTIONS.md`, `DECISIONS.md`, `TOOLS.md`, or `VALIDATION.md`.
- Keep each entry short and evidence-based. Prefer `observed` facts over speculation.
- This file is a buffer, not a permanent home: promote durable learnings and keep the entry as a breadcrumb.

## Entry format

```text
### L-001 — <short title>
Date: YYYY-MM-DD
Status: active | superseded | promoted
Confidence: observed | inferred
Scope: repo | <path-or-glob> | <technology>
Context: <what was being done>
Evidence: <file:line, command output, or concrete observation>
Pattern / rule: <the reusable takeaway>
Promotion: none | CONVENTIONS.md | DECISIONS.md#ADR-nnn | TOOLS.md | VALIDATION.md
```

## Promotion rules

- Recurring pattern → `CONVENTIONS.md`
- Durable architectural choice → `DECISIONS.md` (ADR), cross-referenced here
- Safe or restricted command rule → `TOOLS.md`
- Completion or validation check → `VALIDATION.md`

After promotion, set the entry to `Status: promoted` and keep it as a breadcrumb; do not duplicate the rule body.

## Compaction

- Keep at most 40 active entries. When exceeded, consolidate related entries, promote what is durable, and mark the rest `superseded`.
- Compaction means summarizing and promoting, not erasing history. Record the compaction in `HANDOFF.md`.

## Entries

### L-001 — aws_s3_bucket data source exposes `region`, not `bucket_region`

Date: 2026-10-21
Status: active
Confidence: observed
Scope: terraform/aws-provider
Context: Needed the log bucket's Region to enforce same-Region delivery for Firehose.
Evidence: `terraform validate` rejected `data.aws_s3_bucket.logs.bucket_region`; `terraform providers schema -json` lists `region` among the data source attributes. There is no `aws_s3_bucket_location` data source in provider 5.100.0.
Pattern / rule: Use `data.aws_s3_bucket.<name>.region` for a bucket's Region; it can be empty for us-east-1, so coalesce with `"us-east-1"`.
Promotion: none

### L-002 — Terraform 1.16 unifies heterogeneous objects in `concat`

Date: 2026-10-21
Status: active
Confidence: observed
Scope: terraform
Context: Aggregating rule objects with different attributes from per-rule files into one list for `dynamic "rule"`.
Evidence: A scratch config with `concat()` of objects having different attribute sets passed `terraform validate` on 1.16.1, but attribute access on a missing key still fails at plan time.
Pattern / rule: Type unification is not a substitute for a stable shape: merge every rule into shared defaults (`local.rule_defaults`, `local.statement_defaults`) so every object exposes the same attributes.
Promotion: CONVENTIONS.md

### L-003 — `concat` of rule objects panics when a nested field switches from null to tuple

Date: 2026-10-21
Status: promoted
Confidence: observed
Scope: terraform
Context: Adding per-region geo blocking exposed a latent failure while evaluating rule aggregation with real values.
Evidence: `terraform console -var-file=env/eu-west-1.tfvars` failed with `panic in function implementation: inconsistent list element types`, because `country_codes` was `cty.DynamicPseudoType` (null) in one rule and `cty.Tuple([string])` in the geo rule. `terraform validate` reported success.
Pattern / rule: Give every nested field in a shared object shape a concrete type. Use `tolist([])` as the default and `tolist(...)` on assignment instead of `null`/bare lists.
Promotion: CONVENTIONS.md

### L-004 — CloudFront Web ACLs have no association resource

Date: 2026-10-21
Status: active
Confidence: observed
Scope: terraform/aws-provider
Context: Adding `waf_scope = "CLOUDFRONT"` to the module.
Evidence: `aws_wafv2_web_acl_association` only accepts resources such as ALB and API Gateway; CloudFront attachments are made through `web_acl_id` on `aws_cloudfront_distribution`. The API also requires CLOUDFRONT-scoped ACLs to live in `us-east-1`, which is why `aws_region` and `tf-init.sh` reject any other Region for that scope.
Pattern / rule: For CloudFront, create the ACL in `us-east-1`, output the ARN, and let the distribution owner set `web_acl_id`; never import a distribution just to attach an ACL. Destroy requires detaching it first.
Promotion: none

### L-005 — `concat` requires exactly matching types: `map(dynamic)` is not `map(string)`

Date: 2026-10-21
Status: active
Confidence: observed
Scope: terraform
Context: A real read-only `terraform plan` panicked while `terraform validate` and `terraform console` with the same policy file both passed.
Evidence: `concat` failed with `panic in function implementation: inconsistent list element types`, comparing `rule_action_overrides: cty.Map(cty.DynamicPseudoType)` (from `tomap({})`) with `cty.Map(cty.String)` (from a `map(string)` variable). `tomap({})` is `map(dynamic)` and does not unify with `map(string)` in `concat`.
Pattern / rule: Do not put optional maps inside a shared object shape. Keep per-rule lookups (for example rule name to overrides) in a separate local and resolve them with `lookup()` where they are used. Only a real plan evaluates provider-resolved types; treat `validate` as insufficient.
Promotion: CONVENTIONS.md


### L-006 — Firehose can be subscription-blocked in restricted accounts

Date: 2026-10-21
Status: active
Confidence: observed
Scope: aws-account/firehose
Context: Applying the stack to a real account.
Evidence: `CreateDeliveryStream` failed with `SubscriptionRequiredException: The AWS Access Key Id needs a subscription for the service`, while `ListDeliveryStreams` was inconsistent between calls. The Web ACL, association, IP set, IAM role, and CloudWatch log group were created normally.
Pattern / rule: Treat Firehose as an account capability, not a given. When it is unavailable, set `enable_waf_logging = false` so the Web ACL converges without logging, and record the degraded mode in the target's policy file. The WAF and its association do not depend on logging.
Promotion: none
