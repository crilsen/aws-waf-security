# Project

## Identity

- **Name:** aws-waf-security
- **Objective:** Public portfolio project that protects an existing Application Load Balancer with AWS WAFv2, provisioned with Terraform.
- **Repository purpose:** Demonstrate a reviewable, production-minded delivery of a Regional Web ACL: AWS managed rules, IP rate limiting, optional IP and geographic restrictions, logging to S3 through Amazon Data Firehose, and two independent CI pipelines with mandatory human approval between plan and apply.
- **Status:** Specification only. `aws-waf-security.md` defines the work; no Terraform code, pipelines, or project documentation exist yet.

## Scope (from `aws-waf-security.md`)

In scope:

- Regional Web ACL associated with one ALB whose ARN is supplied explicitly by the operator.
- Optional global (CloudFront) Web ACL created in `us-east-1`, attached by the distribution owner through `web_acl_id`.
- The S3 bucket used for WAF logs and the S3 bucket used for Terraform state are supplied by the operator. The project creates neither bucket, and it does not modify their policies.
- Configurable default action.
- AWS Managed Rules Common Rule Set and Known Bad Inputs.
- IP-based rate limiting with a configurable limit.
- Optional allow list and deny list of IPs.
- Optional, configurable geographic blocking.
- WAF metrics, sampled requests, and logging to S3 via Amazon Data Firehose.
- Rules start in `COUNT`; promotion to `BLOCK` requires a new plan and a new approval.
- One Terraform file per WAF rule, so each rule can be reviewed and promoted to `BLOCK` on its own.
- Multi-region delivery: the same module runs once per Region, with one state per Region and `AWS_REGION` as a pipeline parameter.
- GitLab CI/CD and Jenkins pipelines: format and validate, produce a plan, require manual approval, then apply the exact approved plan file.
- Documentation: README, architecture diagram, prerequisites, parameters, remote backend setup, least-privilege IAM, local usage, both pipelines, manual approval, rule operation, logging, troubleshooting, cost, cleanup, and limitations.

Out of scope:

- Creating or changing the ALB, VPC, listeners, target groups, application, or DNS.
- Creating, deleting, or reconfiguring the S3 buckets for logs and state; the operator owns them.
- Discovering or selecting an ALB automatically: the ARN is a required input.
- Athena, Glue, CAPTCHA, Bot Control, multi-account.

## Constraints

- Never deploy, apply, destroy, or access a real AWS account during this work.
- Do not copy code, rules, names, domains, IDs, configurations, or proprietary information from SoftExpert, and never present the project as a real company implementation.
- Do not commit credentials, Terraform state, plan files, or local variable files.
- The ALB and the Web ACL must be in the same AWS Region; document this requirement.

## Observed environment

- Installed: `terraform` 1.16.1, `aws-cli` 2.37.4, `docker` 29.8.1, `python` 3.14.4 (with `PyYAML` 6.0.3), `node` 22.22.1, `jq` 1.8.1, `shellcheck`.
- Not installed: `tofu`, `tflint`, `checkov`, `trivy`, `yamllint`, `jenkins`, `groovy`.
- Platform: Linux (WSL2).
- No AWS credentials were used or verified; AWS access is not required or permitted for this work.
