# WAF policy for eu-west-1.
#
# This file is versioned on purpose: it is the reviewed policy for one Region
# and is passed to Terraform as `-var-file="env/regional/<region>.tfvars"`. It
# must never contain secrets. The ALB ARN, the log bucket, and the state bucket
# are supplied by the pipeline as protected variables, not from this file.
#
# Observations
# - The Firehose delivery stream that receives WAF logs must be named with the
#   `aws-waf-logs-` prefix (AWS requirement). The module derives it as
#   `aws-waf-logs-<name_prefix>-<scope>-<region>`, so nothing here configures it.
# - The log bucket has no naming prerequisite: it only has to exist in the same
#   Region as the Web ACL and allow the module's Firehose role to write.
# - Resource names are immutable. Changing name_prefix, scope, or region
#   replaces the Web ACL, IP sets, Firehose stream, and IAM role, so it is a
#   reviewed plan, never a rename.

# Default action for every rule not listed in rule_actions.
# COUNT records matches without blocking; promote only through a reviewed plan.
rule_mode = "COUNT"

# Every rule is enabled in this Region.
enabled_rules = [
  "ip_allowlist",
  "ip_denylist",
  "managed_common",
  "managed_known_bad_inputs",
  "geo",
  "rate_limit",
]

# Per-rule override of rule_mode for this Region. Empty means "use rule_mode".
# Example after review:
#   rule_actions = { rate_limit = "BLOCK" }
rule_actions = {}

rate_limit                       = 2000
rate_limit_evaluation_window_sec = 300

# Optional lists; empty disables the corresponding rule.
ip_allow_list            = []
ip_deny_list             = []
geo_restricted_countries = ["KP"]

# False-positive tuning for the managed rule groups.
common_rule_set_rule_overrides  = {}
known_bad_inputs_rule_overrides = {}
