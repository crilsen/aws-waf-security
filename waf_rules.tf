# Rule aggregation.
#
# Each waf_rule_*.tf file contributes at most one rule object, and only when it
# is enabled. Rule files never talk to AWS directly: they only describe a rule.
#
# The order of this list has no security effect. AWS WAF evaluates rules by
# ascending priority, which is documented in .ai/DECISIONS.md (ADR-003).

locals {
  waf_rules = concat(
    local.rule_ip_allowlist,
    local.rule_ip_denylist,
    local.rule_managed_common,
    local.rule_managed_known_bad_inputs,
    local.rule_geo,
    local.rule_rate_limit,
  )
}
