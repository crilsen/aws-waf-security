# Least-privilege role used by Amazon Data Firehose to write WAF logs into the
# bucket owned by the operator.
#
# The operator must still allow this role in the bucket policy (or in a
# bucket-level grant); see the README section "Log bucket requirements".

data "aws_iam_policy_document" "firehose_assume_role" {
  statement {
    sid     = "FirehoseAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  count = var.enable_waf_logging ? 1 : 0

  name               = "${local.name_base}-waf-firehose"
  description        = "Allows Firehose to deliver WAF logs to ${var.log_bucket_name}."
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json

  tags = local.tags
}

data "aws_iam_policy_document" "firehose_delivery" {
  count = var.enable_waf_logging ? 1 : 0

  statement {
    sid = "WriteWafLogsToOperatorBucket"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]

    resources = [
      local.log_bucket_arn,
      "${local.log_bucket_arn}/*",
    ]
  }

  statement {
    sid = "WriteFirehoseErrorLogs"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.firehose[0].arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "firehose" {
  count = var.enable_waf_logging ? 1 : 0

  name   = "${local.name_base}-waf-firehose-delivery"
  role   = aws_iam_role.firehose[0].id
  policy = data.aws_iam_policy_document.firehose_delivery[0].json
}
