locals {
  tags = merge(
    {
      Project   = "aws-waf-security"
      ManagedBy = "terraform"
      Component = "waf"
    },
    var.tags,
  )

  # Rule names are the keys shared by enabled_rules and rule_actions.
  rule_names = toset([
    "ip_allowlist",
    "ip_denylist",
    "managed_common",
    "managed_known_bad_inputs",
    "geo",
    "rate_limit",
  ])

  enabled_rule_names = toset(var.enabled_rules)

  # rule_mode is the per-deployment default; rule_actions overrides it per rule,
  # which is how each Region gets its own policy from its own var file.
  effective_rule_actions = merge(
    { for name in local.rule_names : name => var.rule_mode },
    var.rule_actions,
  )

  # Terminating rules (deny list, geo, rate limit) use `action`.
  rule_action_by_name = {
    for name, mode in local.effective_rule_actions : name => mode == "BLOCK" ? "block" : "count"
  }

  # Managed rule groups use `override_action`: `none` keeps the group's verdicts,
  # `count` forces the whole group to COUNT.
  managed_override_action_by_name = {
    for name, mode in local.effective_rule_actions : name => mode == "BLOCK" ? "none" : "count"
  }

  # Region encoded in the ALB ARN. The format itself is validated on the
  # variable; this value is used to prove Region consistency at plan time.
  # Empty for CLOUDFRONT scope, where no ALB is involved.
  alb_region = try(regex("^arn:aws[a-zA-Z-]*:elasticloadbalancing:([a-z0-9-]+):", var.alb_arn)[0], "")

  log_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.log_bucket_name}"

  # AWS returns an empty value for buckets in us-east-1.
  log_bucket_region = try(coalesce(data.aws_s3_bucket.logs.region, "us-east-1"), "us-east-1")

  geo_country_codes = [for code in var.geo_restricted_countries : upper(code)]

  # Shared shape for every rule object. Rule files merge into these defaults so
  # all rules share one object type and can be concatenated into a single list
  # consumed by `dynamic "rule"` in waf.tf. Unused fields stay null.
  rule_defaults = {
    name            = null
    priority        = null
    action          = null
    override_action = null
    metric_name     = null
    statement       = null
  }

  statement_defaults = {
    type                    = null
    managed_rule_group_name = null
    vendor_name             = "AWS"
    rule_action_overrides   = {}
    ip_set_arn              = null
    limit                   = null
    evaluation_window_sec   = null
    # Concrete list type on purpose: a tuple here makes `concat` panic with
    # "inconsistent list element types" once the geo rule sets a real list.
    country_codes = tolist([])
  }
}
