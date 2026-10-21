# Firehose error logging. Delivery errors (permission denied, throttling) show
# up here, not in the WAF console.
resource "aws_cloudwatch_log_group" "firehose" {
  count = var.enable_waf_logging ? 1 : 0

  name              = "/aws/kinesisfirehose/${local.name_base}-waf-logs"
  retention_in_days = var.firehose_log_retention_days

  tags = local.tags
}

resource "aws_cloudwatch_log_stream" "firehose" {
  count = var.enable_waf_logging ? 1 : 0

  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose[0].name
}

# Buffers WAF log records and writes them to the bucket owned by the operator.
# The bucket is never created or modified here.
resource "aws_kinesis_firehose_delivery_stream" "waf" {
  count = var.enable_waf_logging ? 1 : 0

  name        = "aws-waf-logs-${local.name_base}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose[0].arn
    bucket_arn = data.aws_s3_bucket.logs.arn

    # Partitioned layout keeps S3 listing and future query tools cheap.
    prefix              = "waf-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "waf-logs-errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"

    buffering_size     = var.firehose_buffering_size
    buffering_interval = var.firehose_buffering_interval
    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose[0].name
      log_stream_name = aws_cloudwatch_log_stream.firehose[0].name
    }
  }

  depends_on = [aws_iam_role_policy.firehose]

  lifecycle {
    precondition {
      condition     = local.log_bucket_region == var.aws_region
      error_message = "log_bucket_name is in Region '${local.log_bucket_region}' but aws_region is '${var.aws_region}'. Firehose can only deliver to a bucket in its own Region."
    }
  }

  tags = local.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = var.enable_waf_logging ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_kinesis_firehose_delivery_stream.waf[0].arn]

  # Never write credentials or session tokens to the log bucket.
  dynamic "redacted_fields" {
    for_each = var.waf_log_redacted_headers
    content {
      single_header {
        name = lower(redacted_fields.value)
      }
    }
  }
}
