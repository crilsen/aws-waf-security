# WAF policy for us-east-1.
#
# Deliberately different from eu-west-1 to show that each Region owns its own
# rule set, thresholds, and actions in its own reviewed file. This file must
# never contain secrets: the ALB ARN and the buckets come from the pipeline.

rule_mode = "COUNT"

# This Region runs without geographic blocking. The geo rule is absent from the
# Web ACL entirely, instead of being present but inert.
enabled_rules = [
  "ip_allowlist",
  "ip_denylist",
  "managed_common",
  "managed_known_bad_inputs",
  "rate_limit",
]

# Different thresholds and per-rule actions are allowed, but promotion still
# requires a reviewed plan and a fresh approval:
#   rule_actions = { rate_limit = "BLOCK" }
rule_actions = {}

rate_limit                       = 1000
rate_limit_evaluation_window_sec = 120

ip_allow_list            = ["192.0.2.0/24"]
ip_deny_list             = []
geo_restricted_countries = []

# Keep one noisy rule in COUNT in this Region only, without changing the group
# for any other Region.
common_rule_set_rule_overrides = {
  SizeRestrictions_BODY = "COUNT"
}

known_bad_inputs_rule_overrides = {}
