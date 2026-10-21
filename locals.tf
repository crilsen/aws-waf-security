locals {
  tags = merge(
    {
      Project   = "aws-waf-security"
      ManagedBy = "terraform"
      Component = "waf"
      Scope     = var.waf_scope
      Region    = var.aws_region
    },
    var.tags,
  )

  # Base for every resource name in this target.
  #
  # Scope and Region are part of the name because names of Firehose streams and
  # IAM roles are unique per account/Region regardless of WAF scope: without the
  # scope, a Regional deployment in us-east-1 and the CloudFront deployment would
  # collide. With the Region, resources from different targets are also
  # distinguishable in inventory and logs.
  name_base = "${var.name_prefix}-${lower(var.waf_scope)}-${var.aws_region}"

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
  # all rules share one concrete type and can be concatenated into a single list
  # consumed by `dynamic "rule"` in waf.tf.
  #
  # Every field has a concrete zero value instead of null: `null` and `{}` become
  # DynamicPseudoType/EmptyObject at plan time, and `concat` panics when one rule
  # ends up with a different type from its sibling. Unused fields stay "" or 0.
  rule_defaults = {
    name            = ""
    priority        = 0
    action          = ""
    override_action = ""
    metric_name     = ""
    statement       = null
  }

  statement_defaults = {
    type                    = ""
    managed_rule_group_name = ""
    vendor_name             = "AWS"
    ip_set_arn              = ""
    limit                   = 0
    evaluation_window_sec   = 0
    country_codes           = tolist([])
  }

  # Managed rule group overrides, keyed by the WAF rule name. They are kept out
  # of the rule objects because an empty map literal is `map(dynamic)` while the
  # variables are `map(string)`, and `concat` requires exactly matching types.
  rule_action_overrides = {
    "aws-managed-common"           = var.common_rule_set_rule_overrides
    "aws-managed-known-bad-inputs" = var.known_bad_inputs_rule_overrides
  }
}
