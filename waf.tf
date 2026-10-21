resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name_prefix}-web-acl"
  description = "Regional Web ACL protecting the existing ALB supplied by the operator."
  scope       = "REGIONAL"

  default_action {
    dynamic "allow" {
      for_each = var.default_action == "allow" ? [1] : []
      content {}
    }
    dynamic "block" {
      for_each = var.default_action == "block" ? [1] : []
      content {}
    }
  }

  # Rules are defined one per file (waf_rule_*.tf), aggregated in waf_rules.tf.
  # Their order here is irrelevant: AWS WAF evaluates by ascending priority.
  dynamic "rule" {
    for_each = local.waf_rules

    content {
      name     = rule.value.name
      priority = rule.value.priority

      dynamic "action" {
        for_each = rule.value.action == null ? [] : [rule.value.action]
        content {
          dynamic "allow" {
            for_each = action.value == "allow" ? [1] : []
            content {}
          }
          dynamic "block" {
            for_each = action.value == "block" ? [1] : []
            content {}
          }
          dynamic "count" {
            for_each = action.value == "count" ? [1] : []
            content {}
          }
        }
      }

      dynamic "override_action" {
        for_each = rule.value.override_action == null ? [] : [rule.value.override_action]
        content {
          dynamic "none" {
            for_each = override_action.value == "none" ? [1] : []
            content {}
          }
          dynamic "count" {
            for_each = override_action.value == "count" ? [1] : []
            content {}
          }
        }
      }

      statement {
        dynamic "managed_rule_group_statement" {
          for_each = rule.value.statement.type == "managed_rule_group" ? [rule.value.statement] : []
          content {
            name        = managed_rule_group_statement.value.managed_rule_group_name
            vendor_name = managed_rule_group_statement.value.vendor_name

            dynamic "rule_action_override" {
              for_each = managed_rule_group_statement.value.rule_action_overrides
              content {
                name = rule_action_override.key

                action_to_use {
                  dynamic "count" {
                    for_each = rule_action_override.value == "COUNT" ? [1] : []
                    content {}
                  }
                  dynamic "block" {
                    for_each = rule_action_override.value == "BLOCK" ? [1] : []
                    content {}
                  }
                }
              }
            }
          }
        }

        dynamic "rate_based_statement" {
          for_each = rule.value.statement.type == "rate_based" ? [rule.value.statement] : []
          content {
            limit                 = rate_based_statement.value.limit
            evaluation_window_sec = rate_based_statement.value.evaluation_window_sec
            aggregate_key_type    = "IP"
          }
        }

        dynamic "ip_set_reference_statement" {
          for_each = rule.value.statement.type == "ip_set" ? [rule.value.statement] : []
          content {
            arn = ip_set_reference_statement.value.ip_set_arn
          }
        }

        dynamic "geo_match_statement" {
          for_each = rule.value.statement.type == "geo_match" ? [rule.value.statement] : []
          content {
            country_codes = geo_match_statement.value.country_codes
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.value.metric_name
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = local.tags
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn

  lifecycle {
    # The ARN format is validated on the variable; this proves the ALB and the
    # Web ACL are in the same Region before any request is made.
    precondition {
      condition     = local.alb_region == var.aws_region
      error_message = "alb_arn is in Region '${local.alb_region}' but aws_region is '${var.aws_region}'. A Regional Web ACL can only be associated with an ALB in the same Region."
    }
  }
}
