locals {
  tags = merge(
    {
      Project   = "aws-waf-security"
      ManagedBy = "terraform"
      Component = "waf"
    },
    var.tags,
  )

  # Action applied to the detection rules (deny list, geo, rate limit) and the
  # override action applied to the AWS managed rule groups.
  #
  # COUNT is the only sane initial value: it evaluates and records matching
  # requests without blocking them. Promoting to BLOCK requires a new plan and
  # a new approval in both pipelines.
  rule_action             = var.rule_mode == "BLOCK" ? "block" : "count"
  managed_override_action = var.rule_mode == "BLOCK" ? "none" : "count"

  # Region encoded in the ALB ARN. The format itself is validated on the
  # variable; this value is used to prove Region consistency at plan time.
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
    country_codes           = null
  }
}
