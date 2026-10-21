# Priority 0 — explicit operator exceptions.
#
# The allow list is an exception path, not a detection rule, so it always
# evaluates to `allow` even while every other rule is in COUNT mode. A source
# present in both lists is allowed, because this rule runs first.

locals {
  rule_ip_allowlist = (
    contains(local.enabled_rule_names, "ip_allowlist") && length(var.ip_allow_list) > 0
    ) ? [
    merge(local.rule_defaults, {
      name        = "ip-allowlist"
      priority    = 0
      action      = "allow"
      metric_name = "${local.name_base}-ip-allowlist"

      statement = merge(local.statement_defaults, {
        type       = "ip_set"
        ip_set_arn = aws_wafv2_ip_set.allow[0].arn
      })
    }),
  ] : []
}
