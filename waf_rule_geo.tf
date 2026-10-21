# Priority 30 — optional geographic blocking.
#
# Disabled when geo_restricted_countries is empty, so a project that does not
# need geo blocking pays nothing and creates no extra rule.
#
# Requests originating in the listed countries match this rule and receive
# rule_action (COUNT while tuning, BLOCK after review). Countries that are not
# listed are unaffected.
#
# An "allow only these countries" policy is deliberately out of scope: AWS WAF
# cannot express the complement of a country list, and pretending otherwise
# would silently mislead the operator.

locals {
  rule_geo = (
    contains(local.enabled_rule_names, "geo") && length(var.geo_restricted_countries) > 0
    ) ? [
    merge(local.rule_defaults, {
      name        = "geo-restriction"
      priority    = 30
      action      = local.rule_action_by_name["geo"]
      metric_name = "${var.name_prefix}-geo-restriction"

      statement = merge(local.statement_defaults, {
        type          = "geo_match"
        country_codes = tolist(local.geo_country_codes)
      })
    }),
  ] : []
}
