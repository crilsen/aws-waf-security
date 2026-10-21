# Priority 40 — rate limiting per client IP.
#
# Evaluated last so that requests already rejected by the deny list, the
# managed rule groups, or the geo restriction do not consume the rate counter.
#
# The aggregate key is the IP address of the request, as the specification
# requires. Forwarded-IP handling (forwarded_ip_config) is intentionally not
# configured: behind the ALB, WAF sees the load balancer's client address.

locals {
  rule_rate_limit = contains(local.enabled_rule_names, "rate_limit") ? [
    merge(local.rule_defaults, {
      name        = "rate-limit-per-ip"
      priority    = 40
      action      = local.rule_action_by_name["rate_limit"]
      metric_name = "${var.name_prefix}-rate-limit-per-ip"

      statement = merge(local.statement_defaults, {
        type                  = "rate_based"
        limit                 = var.rate_limit
        evaluation_window_sec = var.rate_limit_evaluation_window_sec
      })
    }),
  ] : []
}
