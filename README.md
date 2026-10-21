# AWS WAFv2 Regional Web ACL for an existing ALB

Portfolio project that puts an **AWS WAFv2 Regional Web ACL** in front of an **Application Load Balancer that already exists**, using Terraform. The project never creates or changes the ALB, the VPC, listeners, target groups, the application, or DNS: it receives the ALB ARN and associates a Web ACL with it.

The Web ACL ships with AWS Managed Rules, a per-IP rate limit, optional IP allow/deny lists, optional geographic blocking, CloudWatch metrics, sampled requests, and logging to S3 through Amazon Data Firehose.

Every rule starts in `COUNT` mode. Blocking is a deliberate, reviewed step that requires a new plan and a new approval.

> This is an independent public project. It is not the implementation of any company, and it contains no real ARNs, account IDs, domains, or credentials.

## Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Operator-provided resources](#operator-provided-resources)
- [Repository layout](#repository-layout)
- [Variables](#variables)
- [Terraform state backend](#terraform-state-backend)
- [IAM permissions](#iam-permissions)
- [Local usage](#local-usage)
- [GitLab CI/CD pipeline](#gitlab-cicd-pipeline)
- [Jenkins pipeline](#jenkins-pipeline)
- [Manual approval](#manual-approval)
- [Operating the rules](#operating-the-rules)
- [Logging](#logging)
- [Multi-region](#multi-region)
- [Troubleshooting](#troubleshooting)
- [Cost](#cost)
- [Cleanup](#cleanup)
- [Limitations](#limitations)
- [Validation performed](#validation-performed)

## Architecture

```text
                          Internet
                              │
                              ▼
                 ┌──────────────────────────┐
                 │  existing ALB (not       │
                 │  managed by this project)│
                 └────────────┬─────────────┘
                              │  ARN supplied as a variable
                              ▼
              ┌────────────────────────────────────┐
              │ AWS WAFv2 Regional Web ACL         │
              │                                    │
              │  0  IP allow list      allow       │
              │  5  IP deny list       COUNT/BLOCK │
              │ 10  Common Rule Set    COUNT/BLOCK │
              │ 20  Known Bad Inputs   COUNT/BLOCK │
              │ 30  Geo restriction    COUNT/BLOCK │
              │ 40  Rate limit per IP  COUNT/BLOCK │
              └───────┬────────────────────┬───────┘
                      │                    │
          metrics + sampled        logs (GZIP, redacted
          requests (CloudWatch)    headers)
                      │                    │
                      │                    ▼
                      │        Amazon Data Firehose
                      │        aws-waf-logs-<name_prefix>
                      │                    │
                      │                    ▼
                      │      S3 bucket provided by the operator
                      │      (encryption, BPA, retention)
                      ▼
                CloudWatch dashboards / alarms
```

Evaluation stops at the first terminating action, in ascending priority order. The order is explained in [Operating the rules](#operating-the-rules) and recorded in [`.ai/DECISIONS.md`](.ai/DECISIONS.md) (ADR-003).

## Prerequisites

| Requirement | Details |
| --- | --- |
| Terraform | >= 1.10 (S3 native state locking). This repository was validated with 1.16.1. |
| AWS provider | `hashicorp/aws ~> 5.60` (resolved to 5.100.0 during validation). |
| AWS credentials | Temporary credentials from an assumed role. No static access keys anywhere. |
| Existing ALB | The ARN must be known in advance and be in `aws_region`. |
| Log bucket | Existing S3 bucket in `aws_region` for WAF logs (see below). |
| State bucket | Existing S3 bucket for Terraform state (see below). |
| Local tooling | `aws-cli` v2, `jq` (optional), `sha256sum`. |
| GitLab | Protected `main` branch, protected environment, OIDC identity provider in AWS. |
| Jenkins | Multibranch Pipeline on protected `main`; agent labelled `terraform` with terraform, aws-cli, git, sha256sum. |

The project has **no** dependency on the application itself: the ALB can be serving anything.

## Operator-provided resources

This project creates **no S3 buckets**. Both buckets are owned by the operator and are inputs.

### Log bucket

The bucket named by `log_bucket_name` must already exist and must have:

- default encryption (`SSE-S3` or `SSE-KMS`) enabled;
- Block Public Access fully enabled;
- a TLS-only bucket policy;
- a bucket policy that allows the Firehose role to write (see [`docs/iam/log-bucket-policy.json`](docs/iam/log-bucket-policy.json));
- a lifecycle rule that matches your retention requirement (for example expire objects after 90 or 365 days).

The Firehose role ARN is predictable before the first apply:

```text
arn:aws:iam::<ACCOUNT_ID>:role/<name_prefix>-waf-firehose
```

Apply the bucket policy with that principal before the first `apply`, otherwise Firehose is created successfully but every delivery fails.

The module validates the bucket at plan time with a `data "aws_s3_bucket"` lookup and refuses a bucket in a different Region from `aws_region`.

### State bucket

The bucket used by the S3 backend must already exist and must have:

- versioning enabled (state history and recovery);
- default encryption (`SSE-S3` or `SSE-KMS`);
- Block Public Access fully enabled;
- a TLS-only bucket policy;
- access limited to the deployment role and Terraform operators.

The backend uses `use_lockfile = true`, so no DynamoDB table is needed: the lock is an object written next to the state.

## Repository layout

```text
.
├── versions.tf              terraform + provider constraints, partial S3 backend
├── providers.tf             AWS provider and default tags
├── variables.tf             every input, with validation
├── locals.tf                tags, effective actions, shared rule shape
├── data.tf                  partition, caller identity, log bucket lookup
├── waf.tf                   Web ACL and ALB association (renders the rules)
├── waf_rules.tf             aggregates the rules from the files below
├── waf_ip_sets.tf           optional IP sets for the allow/deny lists
├── waf_rule_ip_allowlist.tf        priority 0
├── waf_rule_ip_denylist.tf         priority 5
├── waf_rule_managed_common.tf      priority 10
├── waf_rule_managed_known_bad_inputs.tf  priority 20
├── waf_rule_geo.tf                 priority 30
├── waf_rule_rate_limit.tf          priority 40
├── logging.tf               Firehose, error log group, WAF logging configuration
├── iam.tf                   Firehose role and least-privilege policy
├── outputs.tf               Web ACL, association, Firehose, rule summary
├── scripts/assume-role.sh   STS web identity (GitLab) or role assumption (Jenkins)
├── scripts/require-env.sh   fails fast on missing pipeline variables
├── scripts/validate.sh      runs every local validation below
├── tests/check_pipelines.py static assertions for both pipelines
├── .gitlab-ci.yml           validate -> plan -> approval -> apply
├── Jenkinsfile              validate -> plan -> approval -> apply
├── docs/iam/                deployer policy, bucket policy, GitLab trust policy
├── env/<region>.tfvars      reviewed WAF policy per Region (no secrets)
├── terraform.tfvars.example fictional values
└── backend.hcl.example      backend keys, state key scoped by Region
```

One rule per file is intentional: a rule promotion to `BLOCK`, or a false-positive override, changes exactly one file and is easy to review. Terraform only reads top-level `.tf` files, so rule files live at the repository root and are aggregated by `waf_rules.tf`.

## Variables

Values that must be supplied explicitly have no default.

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `aws_region` | string | required | Region of the ALB, Web ACL, Firehose stream, and log bucket. |
| `alb_arn` | string | required | ARN of the existing ALB. Format and Region are validated. |
| `log_bucket_name` | string | required | Existing bucket for WAF logs. |
| `name_prefix` | string | `waf-alb` | Prefix for ACL, rules, IP sets, Firehose, and log group. |
| `default_action` | string | `allow` | Action when no rule matches: `allow` or `block`. |
| `rule_mode` | string | `COUNT` | Default action for every detection rule and managed group. `rule_actions` overrides it per rule. |
| `rule_actions` | map(string) | `{}` | Per-rule action for this Region, for example `{ rate_limit = "BLOCK" }`. Keys: `ip_denylist`, `managed_common`, `managed_known_bad_inputs`, `geo`, `rate_limit`. |
| `enabled_rules` | set(string) | all six | Rules created in this Region. Removing a name leaves that rule out of the Web ACL entirely. |
| `rate_limit` | number | `2000` | Requests per IP per evaluation window. |
| `rate_limit_evaluation_window_sec` | number | `300` | `60`, `120`, `300`, or `600`. |
| `ip_allow_list` | list(string) | `[]` | IPv4 CIDRs always allowed (priority 0). |
| `ip_deny_list` | list(string) | `[]` | IPv4 CIDRs denied at priority 5. |
| `geo_restricted_countries` | list(string) | `[]` | ISO alpha-2 codes blocked at priority 30. Empty disables the rule. |
| `common_rule_set_rule_overrides` | map(string) | `{}` | Per-rule `COUNT`/`BLOCK` overrides for the Common Rule Set. |
| `known_bad_inputs_rule_overrides` | map(string) | `{}` | Per-rule overrides for Known Bad Inputs. |
| `enable_waf_logging` | bool | `true` | Create Firehose and the WAF logging configuration. |
| `waf_log_redacted_headers` | list(string) | `["authorization", "cookie"]` | Headers removed from logs. |
| `firehose_buffering_size` | number | `5` | MiB per buffer (1-128). |
| `firehose_buffering_interval` | number | `300` | Seconds per buffer (60-900). |
| `firehose_log_retention_days` | number | `14` | Retention for the Firehose error log group. |
| `tags` | map(string) | `{}` | Extra tags merged into the defaults. |

Outputs: `web_acl_arn`, `web_acl_id`, `web_acl_name`, `web_acl_association_id`, `associated_alb_arn`, `rule_mode`, `enabled_rules`, `effective_rule_actions`, `rules`, `log_bucket_name`, `firehose_delivery_stream_arn`, `firehose_iam_role_arn`, `firehose_error_log_group_name`.

## Terraform state backend

The backend block is partial on purpose: `bucket`, `key`, and `region` come from init time, because the bucket belongs to the operator and the key must be Region-specific.

```bash
cp backend.hcl.example backend.hcl     # edit bucket + region + key
terraform init -backend-config=backend.hcl
```

`backend.hcl` is git-ignored. The key must follow:

```text
aws-waf-security/<region>/terraform.tfstate
```

so that each Region has independent state, an independent lock, and an independent approval. Never share one state between two Regions: the Web ACL, association, and Firehose are regional resources and would be destroyed and recreated on every Region switch.

In pipelines the key is derived from `AWS_REGION` automatically.

## IAM permissions

Two separate roles are involved.

### 1. Deployment role (assumed by GitLab or Jenkins)

Uses temporary credentials only. See [`docs/iam/deployer-policy.json`](docs/iam/deployer-policy.json) for a least-privilege starting point: WAFv2 (Web ACL, IP sets, logging configuration), Firehose, the Firehose role with `iam:PassRole` restricted to `firehose.amazonaws.com`, the Firehose error log group, read access to the log bucket, and read/write access to the state bucket prefix.

Replace `<ACCOUNT_ID>`, `<AWS_REGION>`, `<LOG_BUCKET>`, `<TF_STATE_BUCKET>`, and `<NAME_PREFIX>` before use.

### 2. Firehose delivery role (created by Terraform)

`<name_prefix>-waf-firehose` can only write to the operator's log bucket and to its own CloudWatch log group. It cannot read or delete anything else.

### GitLab OIDC

Create an IAM OIDC provider for `gitlab.com` and a role whose trust policy restricts the subject to the protected default branch. See [`docs/iam/gitlab-oidc-trust-policy.json`](docs/iam/gitlab-oidc-trust-policy.json). No static access keys are stored in GitLab.

### Jenkins

The agent's instance profile (or another ambient credential source) may call `sts:AssumeRole` on the deployment role. The role ARN is stored as the Jenkins secret text credential `waf-deploy-role-arn`; nothing is typed into parameters or committed.

## Local usage

```bash
# 1. Configure inputs
cp terraform.tfvars.example terraform.tfvars   # fictional values, git-ignored
cp env/eu-west-1.tfvars env/<your-region>.tfvars  # reviewed policy, versioned

# 2. Initialize with the operator's backend
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl

# 3. Review
terraform fmt -recursive
terraform validate
terraform console -var-file="env/<your-region>.tfvars"   # sanity-check the policy
terraform plan -var-file="env/<your-region>.tfvars" -out=tfplan.bin

# 4. Apply only after reviewing the plan
terraform apply tfplan.bin
```

Use a dedicated, short-lived role for local runs. Do not keep long-lived credentials in the environment, in shell history, or in `terraform.tfvars`.

`terraform.tfvars`, `*.tfplan`, `backend.hcl`, and `ci.auto.tfvars` are git-ignored.

## GitLab CI/CD pipeline

`.gitlab-ci.yml` defines four stages.

| Stage | Job | Runs on | What it does |
| --- | --- | --- | --- |
| validate | `fmt` | every branch and merge request | `terraform fmt -check -recursive -diff` |
| validate | `validate` | every branch and merge request | `init -backend=false` + `validate` |
| plan | `plan` | protected default branch only | assumes the role through OIDC, plans, uploads the binary plan, its text rendering, and a SHA-256 checksum |
| approval | `approval` | protected default branch only | blocking manual job (`when: manual`, `allow_failure: false`) |
| apply | `apply` | protected default branch only | downloads the plan artifact, verifies the checksum, applies the stored plan |

Protection settings to configure in GitLab:

- `main` is the protected default branch, with no direct pushes and at least one approval on merge requests;
- CI/CD variables are **protected**: `AWS_REGION`, `AWS_ROLE_ARN`, `ALB_ARN`, `TF_STATE_BUCKET`, `TF_LOG_BUCKET`, and optionally `TF_STATE_REGION`;
- `env/<region>.tfvars` exists and is reviewed: it is the WAF policy for that Region, and the plan job fails when it is missing;
- the `production/<region>` environment has protected environments enabled and requires approval;
- runners are trusted, since they handle credentials and the plan artifact;
- the plan artifact expires in one day and is restricted to maintainers.

The `plan` job also writes `tfplan.txt` (the human-readable plan) for review; the approval decision is based on that file.

## Jenkins pipeline

`Jenkinsfile` is a declarative Multibranch Pipeline with the stages `Validate`, `Plan`, `Approval`, `Apply`.

Parameters:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `AWS_REGION` | `eu-west-1` | Region and state-key selector. |
| `ALB_ARN` | empty | Existing ALB to protect (required). |
| `LOG_BUCKET` | empty | Existing bucket for WAF logs (required). |
| `TF_STATE_BUCKET` | empty | Existing bucket for state (required). |
| `TF_STATE_REGION` | empty | Defaults to `AWS_REGION`. |
| `APPROVERS` | `waf-approvers` | Jenkins user or group allowed to approve. |
| `CREDENTIALS_ID` | `waf-deploy-role-arn` | Secret text credential holding the role ARN. |

Behaviour:

- `Plan`, `Approval`, and `Apply` only run on the protected `main` branch (`when { branch 'main' }`, which requires a Multibranch Pipeline).
- The plan file is stashed after `Plan` and unstashed by `Apply`; the checksum is verified before applying.
- `Apply` never runs `terraform plan`; it applies the stored file.
- The WAF policy is not a build parameter: `Plan` loads `env/<AWS_REGION>.tfvars`, so every policy change is reviewed in git before it ever reaches a plan.
- The approval step times out after 24 hours and is restricted with `submitter: params.APPROVERS`.
- The workspace is cleaned of plan files in the `post` block, and the text plan is archived for review.
- The agent must never run with `set -x` around `scripts/assume-role.sh`: it prints export statements, not secrets, but tracing would still be noisy and unsafe.

## Manual approval

Both pipelines enforce the same order:

```text
validate -> plan -> [human reviews tfplan.txt] -> approval -> apply(tfplan.bin)
```

Guarantees:

1. `apply` depends on both the `plan` artifact and the `approval` job.
2. The plan file is checksummed and the checksum is verified immediately before applying.
3. No step regenerates a plan between approval and apply.
4. No automatic apply exists: without a human approval the pipeline stops.

Promoting rules to `BLOCK` or changing any variable that affects behavior is a new run: new plan, new review, new approval.

## Operating the rules

### Start in COUNT

With `rule_mode = "COUNT"` (the default), the detection rules and both managed rule groups only count matching requests. Nothing is blocked, so a false positive cannot break traffic while you build a baseline.

`rule_actions` promotes individual rules without touching the rest, and `enabled_rules` removes a rule from a Region entirely.

The IP allow list is the exception: it evaluates to `allow` from the start, because it is an operator exception, not a detection rule. A source in both lists is allowed.

### Observe

- **CloudWatch metrics**: one metric namespace per rule, named `<name_prefix>-<rule>`; the Web ACL itself uses `<name_prefix>-web-acl`.
- **Sampled requests**: enabled on every rule and on the Web ACL. Inspect them in the WAF console under the Web ACL's traffic overview to see the URI, headers, and the rule that matched.
- **Logs**: the full request records are in the log bucket (see [Logging](#logging)). Use them to identify offending clients, URIs, and rule names.

### Investigate false positives

1. Identify the rule name in the sampled request or in the log record (`terminatingRuleId` / `nonTerminatingMatchingRules`).
2. Add a per-rule override instead of disabling the whole group:

```hcl
common_rule_set_rule_overrides = {
  SizeRestrictions_BODY = "COUNT"
}
```

3. Plan and review the change; the override is visible in the plan.
4. Keep the override in place while you confirm the application behavior, then remove it if the rule is safe.

### Promote to BLOCK

Promotion is per rule and per Region, which is the point of `rule_actions`:

```hcl
# env/eu-west-1.tfvars
rule_mode   = "COUNT"                        # everything else stays observable
rule_actions = { rate_limit = "BLOCK" }      # only rate limiting blocks here
```

1. Confirm the rule has been matching only traffic you want to block for a full traffic cycle, including peak hours.
2. Add or change the entry in `rule_actions` inside `env/<region>.tfvars` and open a merge request.
3. Run the pipeline: a new plan is produced, a human reviews it, and only then is it applied.
4. Watch HTTP 5xx/4xx rates and WAF `BlockedRequests` metrics immediately after the change.
5. Other Regions are untouched: they keep their own `env/<region>.tfvars`.

Rollback is the same procedure in reverse: remove the entry (or set it back to `COUNT`), plan, approve, apply. Do not "fix" blocking with `default_action` changes.

A rule that should not exist in a Region at all is removed from `enabled_rules` in that Region's file, not deleted from the code.

## Logging

When `enable_waf_logging = true` (default):

- WAF sends every request record to Firehose `aws-waf-logs-<name_prefix>`;
- Firehose buffers (5 MiB / 300 s by default), compresses with GZIP, and writes to the operator's bucket under `waf-logs/year=.../month=.../day=.../hour=.../`;
- delivery errors are written to `<bucket>/waf-logs-errors/<error-type>/...` and recorded in the CloudWatch log group `/aws/kinesisfirehose/<name_prefix>-waf-logs` (14-day retention by default);
- the `authorization` and `cookie` headers are redacted by default (`waf_log_redacted_headers`).

Logging every request has a cost. If the volume is high, lower the buffering frequency impact by increasing `firehose_buffering_size` / `firehose_buffering_interval`, and consider adding a WAF logging filter (see [Limitations](#limitations)).

## Multi-region

Each Region is an independent deployment with its own reviewed policy:

```bash
terraform init -backend-config=backend.hcl                 # key includes the region
terraform plan -var-file="env/eu-west-1.tfvars" \
  -var="aws_region=eu-west-1" -var="alb_arn=..." ...
```

- one Web ACL, association, and Firehose stream per Region;
- one state object per Region (`aws-waf-security/<region>/terraform.tfstate`) and therefore one lock per Region;
- one protected environment per Region in GitLab (`production/<region>`) and one pipeline run per Region in Jenkins;
- approvals are per Region: a plan for `eu-west-1` cannot apply to `us-east-1`.

### Per-region policy

`env/<region>.tfvars` is the policy file for one Region and is versioned on purpose. It can differ freely between Regions:

| File | What it controls |
| --- | --- |
| `env/eu-west-1.tfvars` | all six rules enabled, geo blocking for `KP`, 2000 req/IP |
| `env/us-east-1.tfvars` | geo rule absent, allow list for `192.0.2.0/24`, 1000 req/IP, `SizeRestrictions_BODY` overridden to `COUNT` |

Because both pipelines load `-var-file="env/<AWS_REGION>.tfvars"` and fail when the file is missing, adding a Region means adding its policy file, not editing code:

```bash
cp env/eu-west-1.tfvars env/ap-southeast-2.tfvars
terraform init -backend-config=backend.hcl
terraform plan -var-file="env/ap-southeast-2.tfvars" -var="aws_region=ap-southeast-2" ...
```

Secrets never belong in these files. The ALB ARN, the log bucket, the state bucket, and the role ARN stay as protected pipeline variables.

Validation: `terraform validate` does not evaluate variable values, so run `terraform console -var-file="env/<region>.tfvars"` (or `terraform plan`) after editing a policy file. The repository was checked this way for both included Regions.

Global WAF (CloudFront) and multi-account are out of scope.

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `Error: reading S3 Bucket (...) : NotFound` during plan | `log_bucket_name` typo, wrong account, or missing `s3:ListBucket` | Check the name and the deployment role's read permission. |
| `log_bucket_name is in Region 'x' but aws_region is 'y'` | Bucket and Web ACL in different Regions | Use a bucket in `aws_region`. |
| `alb_arn is in Region 'x' but aws_region is 'y'` | ALB and Web ACL in different Regions | Set `aws_region` to the ALB's Region. |
| Legitimate users receive 403 | A rule is in `BLOCK` and matches real traffic | Find the rule in sampled requests, set a per-rule `COUNT` override, plan, approve, apply. |
| Nothing is blocked | `rule_mode = "COUNT"` | Expected until you promote to `BLOCK`; check the metrics first. |
| Requests are still served and WAF metrics are flat | Web ACL associated with another ARN | Check `associated_alb_arn` output and the WAF console association. |
| Firehose delivery errors | Bucket policy does not allow `<name_prefix>-waf-firehose` | Apply [`docs/iam/log-bucket-policy.json`](docs/iam/log-bucket-policy.json) with the correct principal. |
| `InvalidParameterException: WAFInvalidParameterException` on logging | Firehose stream and Web ACL in different Regions | Keep both in `aws_region`. |
| `Error acquiring the state lock` | A previous run is still holding the lock | Confirm no run is active, then use `terraform force-unlock <ID>` deliberately (never in CI). |
| Plan wants to replace the association on every run | State and Region mismatch between runs | Ensure the state key includes the Region and matches the Region being deployed. |
| `AccessDenied` from `data.aws_s3_bucket` | Deployment role lacks `s3:ListBucket`/`GetBucketLocation` | Update the deployer policy. |

Debugging tips:

- `terraform plan` failures are cheaper to diagnose than apply failures: read the precondition message, which names both Regions.
- Never debug by applying changes manually in the console; the next pipeline run will plan them away, and the console state is not reviewed.
- For a suspected false positive, compare the sampled request with the log record for the same timestamp; the log shows the full rule list.

## Cost

Approximate monthly cost, excluding request volume and storage growth. Confirm current prices on the AWS pricing pages; values change.

| Item | Typical price |
| --- | --- |
| Web ACL | about USD 5 per ACL per month |
| Rules | about USD 1 per rule per month (6 rules here, fewer when optional rules are disabled) |
| Requests | about USD 0.60 per million requests |
| Firehose | about USD 0.029 per GB ingested, plus PUT payload units |
| S3 | storage and requests for the log objects |
| CloudWatch | custom metrics for the Web ACL and each rule, sampled requests included |
| CloudWatch Logs | Firehose error log group, 14-day retention by default |

Cost controls: keep the optional rules disabled when unused, increase the Firehose buffer, and set a retention lifecycle on the log bucket.

## Cleanup

```bash
terraform destroy -var="aws_region=..." -var="alb_arn=..." -var="log_bucket_name=..." ...
```

What is removed: the Web ACL and its association (traffic stops being filtered by this ACL, the ALB is untouched), the Firehose stream, the Firehose role and policy, and the error log group. Optional IP sets are removed too.

What is kept: the ALB, the log bucket with its objects and policy, the state bucket, and the state history. Delete those deliberately, outside Terraform, after confirming no audit obligation requires the logs.

Run cleanup from the same Region/state pair that created the resources. Do not delete the state bucket before the destroy completes.

## Limitations

- **One ALB per deployment.** The ARN is a single required input by design; several ALBs in one Region need several deployments with distinct `name_prefix` and state keys.
- **Fixed rule catalog.** The six rules are the supported set; `enabled_rules` and `rule_actions` change which of them exist and how they act per Region, but a new kind of statement (custom match, header rule, trusted IP group) is a code change.
- **IPv4 only.** IP sets use `IPV4`; IPv6 CIDRs are rejected by validation.
- **Geo blocking only.** `geo_restricted_countries` blocks the listed countries. An "allow only these countries" policy is not expressible without listing every other country, so it is out of scope.
- **No global WAF.** CloudFront-scoped Web ACLs are out of scope; this project is Regional only.
- **No Bot Control, CAPTCHA, or challenge actions.** Only `allow`, `block`, and `count` are used.
- **No Athena/Glue.** Logs are plain GZIP JSON in S3; query tooling is the operator's choice.
- **No logging filter.** Every request is logged, which is simple to audit but not the cheapest option; add a `logging_filter` if volume demands it.
- **Buckets are not managed.** Encryption, Block Public Access, lifecycle, and the bucket policy are the operator's responsibility and are documented, not enforced.
- **No alarms or dashboards.** CloudWatch metrics exist; alerting is out of scope.
- **No cross-Region aggregation.** Each Region has its own metrics, logs prefix, state, and approval.
- **The plan artifact is sensitive.** It can contain ARNs and account identifiers and is why artifacts expire in one day and are restricted.
- **Static validation only in CI.** `fmt`, `validate`, and pipeline parsing run in CI. No integration test exercises AWS behavior, and no test creates real resources.
- **State locking requires Terraform >= 1.10.**
- **Jenkins assumes a trusted agent.** The agent handles temporary credentials and the plan file.

## Validation performed

Everything below is reproducible with `./scripts/validate.sh`, which never touches AWS and never initializes the remote backend.

- `terraform fmt -check -recursive` — passed.
- `terraform init -backend=false` — passed; AWS provider 5.100.0 locked in `.terraform.lock.hcl`.
- `terraform validate` — passed.
- `.gitlab-ci.yml` parsed as YAML; stages, jobs, artifact, checksum step, OIDC tokens, branch restrictions, and the blocking manual approval asserted by `tests/check_pipelines.py`.
- `Jenkinsfile` checked structurally: stage order, `stash`/`unstash` around the plan file, `apply` never calls `terraform plan`, approval restricted by `submitter` and a timeout, protected branch on Plan/Approval/Apply.
- `shellcheck` on `scripts/*.sh`.
- Per-region policy files resolved with `terraform console -var-file=env/<region>.tfvars` for both included Regions, confirming different rule sets and actions (`eu-west-1`: 4 rules including geo; `us-east-1`: allow list, no geo, different thresholds). This check caught a real defect: a tuple-typed country list made `concat` fail at plan time, fixed by forcing `tolist` in `local.statement_defaults`.

Not validated: `terraform plan`, `terraform apply`, and any AWS interaction. Those require an account, an existing ALB, and both buckets, and are intentionally out of scope for this repository.
