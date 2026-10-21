# Priority 5 — explicit denies.
#
# Cheap to evaluate and evaluated before the managed rule groups, so a known
# bad source is rejected without spending managed-rule capacity. Follows
# rule_mode: COUNT while tuning, BLOCK after review.

locals {
  rule_ip_denylist = (
    contains(local.enabled_rule_names, "ip_denylist") && length(var.ip_deny_list) > 0
    ) ? [
    merge(local.rule_defaults, {
      name        = "ip-denylist"
      priority    = 5
      action      = local.rule_action_by_name["ip_denylist"]
      metric_name = "${local.name_base}-ip-denylist"

      statement = merge(local.statement_defaults, {
        type       = "ip_set"
        ip_set_arn = aws_wafv2_ip_set.deny[0].arn
      })
    }),
  ] : []
}
