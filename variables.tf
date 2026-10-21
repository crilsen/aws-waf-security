variable "waf_scope" {
  description = "Scope of the Web ACL: REGIONAL protects an ALB in aws_region; CLOUDFRONT is the global scope used by CloudFront distributions and must be deployed in us-east-1."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.waf_scope)
    error_message = "waf_scope must be REGIONAL or CLOUDFRONT."
  }
}

variable "aws_region" {
  description = "AWS Region for the Web ACL, the Firehose delivery stream, and the existing ALB. CLOUDFRONT scope requires us-east-1."
  type        = string

  validation {
    condition = (
      can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region)) &&
      (var.waf_scope != "CLOUDFRONT" || var.aws_region == "us-east-1")
    )
    error_message = "aws_region must be a valid AWS Region identifier, for example eu-west-1. A CLOUDFRONT Web ACL must be deployed in us-east-1."
  }
}

variable "alb_arn" {
  description = "ARN of the existing Application Load Balancer to protect. Required when waf_scope = REGIONAL and must be omitted (null) for CLOUDFRONT, where the distribution owner attaches the Web ACL through its web_acl_id."
  type        = string
  default     = null

  validation {
    condition = (
      var.waf_scope == "CLOUDFRONT"
      ? var.alb_arn == null
      : var.alb_arn != null && can(regex("^arn:aws[a-zA-Z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:loadbalancer/app/.+$", var.alb_arn))
    )
    error_message = "alb_arn is required for REGIONAL scope and must be an Application Load Balancer ARN; for CLOUDFRONT scope it must be omitted."
  }
}

variable "log_bucket_name" {
  description = "Name of the existing S3 bucket that receives the WAF logs through Firehose. This project does not create or modify the bucket; it must already exist in var.aws_region with encryption, Block Public Access, and a policy allowing the Firehose role to write."
  type        = string
  nullable    = false

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.log_bucket_name)) &&
      !can(regex("\\.\\.", var.log_bucket_name)) &&
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.log_bucket_name))
    )
    error_message = "log_bucket_name must be a valid S3 bucket name: 3-63 characters, lowercase letters, digits, dots and hyphens, not formatted as an IP address."
  }
}

variable "name_prefix" {
  description = "Prefix for the names of the Web ACL, rules, IP sets, Firehose stream, and CloudWatch log group."
  type        = string
  default     = "waf-alb"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2-32 characters of lowercase letters, digits and hyphens, starting and ending with an alphanumeric character."
  }
}

variable "default_action" {
  description = "Action taken when no rule matches: allow or block. Use allow when introducing WAF in front of an existing ALB."
  type        = string
  default     = "allow"

  validation {
    condition     = contains(["allow", "block"], var.default_action)
    error_message = "default_action must be either allow or block."
  }
}

variable "rule_mode" {
  description = "Default action for detection rules and managed rule groups: COUNT (observe only) or BLOCK. rule_actions overrides this per rule. Start with COUNT; promoting to BLOCK requires a new plan and a new approval."
  type        = string
  default     = "COUNT"

  validation {
    condition     = contains(["COUNT", "BLOCK"], var.rule_mode)
    error_message = "rule_mode must be either COUNT or BLOCK."
  }
}

variable "rule_actions" {
  description = "Per-rule action for this Region, overriding rule_mode. Keys: ip_denylist, managed_common, managed_known_bad_inputs, geo, rate_limit. Values: COUNT or BLOCK. ip_allowlist is not configurable because it is an exception path, not a detection rule."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for name, action in var.rule_actions :
      contains(["ip_denylist", "managed_common", "managed_known_bad_inputs", "geo", "rate_limit"], name) &&
      contains(["COUNT", "BLOCK"], action)
    ])
    error_message = "rule_actions keys must be ip_denylist, managed_common, managed_known_bad_inputs, geo or rate_limit, and values must be COUNT or BLOCK."
  }
}

variable "enabled_rules" {
  description = "Rules created in this Region. Remove a name to leave that rule out of the Web ACL entirely, so Regions can run different rule sets without changing code. Optional rules (IP lists, geo) are also skipped when they have no data."
  type        = set(string)

  default = [
    "ip_allowlist",
    "ip_denylist",
    "managed_common",
    "managed_known_bad_inputs",
    "geo",
    "rate_limit",
  ]

  validation {
    condition = alltrue([
      for name in var.enabled_rules :
      contains(["ip_allowlist", "ip_denylist", "managed_common", "managed_known_bad_inputs", "geo", "rate_limit"], name)
    ])
    error_message = "enabled_rules entries must be among ip_allowlist, ip_denylist, managed_common, managed_known_bad_inputs, geo, rate_limit."
  }
}

variable "rate_limit" {
  description = "Maximum number of requests allowed from a single IP address within the evaluation window. Requests above the limit match the rate-based rule."
  type        = number
  default     = 2000

  validation {
    condition     = var.rate_limit >= 100 && var.rate_limit <= 2000000000
    error_message = "rate_limit must be between 100 and 2000000000."
  }
}

variable "rate_limit_evaluation_window_sec" {
  description = "Evaluation window for the rate-based rule, in seconds: 60, 120, 300, or 600."
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 120, 300, 600], var.rate_limit_evaluation_window_sec)
    error_message = "rate_limit_evaluation_window_sec must be one of 60, 120, 300, or 600."
  }
}

variable "ip_allow_list" {
  description = "IPv4 CIDR blocks that are always allowed, for example trusted egress ranges. The allow rule has the highest priority and runs before every blocking rule, in COUNT and BLOCK modes alike."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.ip_allow_list : can(cidrnetmask(cidr))])
    error_message = "Every entry in ip_allow_list must be a valid IPv4 CIDR block, for example 203.0.113.0/24."
  }
}

variable "ip_deny_list" {
  description = "IPv4 CIDR blocks that are explicitly denied, for example abusive sources. Evaluated with the configured rule_mode."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.ip_deny_list : can(cidrnetmask(cidr))])
    error_message = "Every entry in ip_deny_list must be a valid IPv4 CIDR block, for example 198.51.100.0/24."
  }
}

variable "geo_restricted_countries" {
  description = "ISO 3166-1 alpha-2 country codes whose requests are blocked by the geo restriction rule. Empty disables the rule. An allow-only-country policy is out of scope; see the README limitations."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for code in var.geo_restricted_countries : can(regex("^[A-Za-z]{2}$", code))])
    error_message = "Every entry in geo_restricted_countries must be a two-letter ISO 3166-1 alpha-2 country code, for example BR."
  }
}

variable "common_rule_set_rule_overrides" {
  description = "Per-rule overrides for AWSManagedRulesCommonRuleSet, keyed by rule name, for false-positive tuning, for example { SizeRestrictions_BODY = \"COUNT\" }. Empty uses the managed rule group's default actions."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for action in values(var.common_rule_set_rule_overrides) : contains(["COUNT", "BLOCK"], action)])
    error_message = "Every value in common_rule_set_rule_overrides must be COUNT or BLOCK."
  }
}

variable "known_bad_inputs_rule_overrides" {
  description = "Per-rule overrides for AWSManagedRulesKnownBadInputsRuleSet, keyed by rule name. Empty uses the managed rule group's default actions."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for action in values(var.known_bad_inputs_rule_overrides) : contains(["COUNT", "BLOCK"], action)])
    error_message = "Every value in known_bad_inputs_rule_overrides must be COUNT or BLOCK."
  }
}

variable "enable_waf_logging" {
  description = "Send WAF logs to the operator-provided S3 bucket through Amazon Data Firehose."
  type        = bool
  default     = true
}

variable "waf_log_redacted_headers" {
  description = "Request headers removed from WAF logs. Names are lowercased automatically; AWS WAF requires lowercase header names."
  type        = list(string)
  default     = ["authorization", "cookie"]

  validation {
    condition     = alltrue([for header in var.waf_log_redacted_headers : can(regex("^[A-Za-z0-9-]+$", header))])
    error_message = "Every entry in waf_log_redacted_headers must be a single header name without spaces or wildcards."
  }
}

variable "firehose_buffering_size" {
  description = "Firehose buffer size in MiB (1-128). Larger buffers reduce S3 PUT costs and increase log latency."
  type        = number
  default     = 5

  validation {
    condition     = var.firehose_buffering_size >= 1 && var.firehose_buffering_size <= 128
    error_message = "firehose_buffering_size must be between 1 and 128 MiB."
  }
}

variable "firehose_buffering_interval" {
  description = "Firehose buffer interval in seconds (60-900)."
  type        = number
  default     = 300

  validation {
    condition     = var.firehose_buffering_interval >= 60 && var.firehose_buffering_interval <= 900
    error_message = "firehose_buffering_interval must be between 60 and 900 seconds."
  }
}

variable "firehose_log_retention_days" {
  description = "Retention in days for the CloudWatch log group that receives Firehose delivery errors."
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.firehose_log_retention_days)
    error_message = "firehose_log_retention_days must be a retention value accepted by CloudWatch Logs, for example 7, 14, 30, 90, or 365."
  }
}

variable "tags" {
  description = "Additional tags merged into the default tag set applied to every resource."
  type        = map(string)
  default     = {}
}
