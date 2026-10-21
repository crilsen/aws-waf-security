data "aws_partition" "current" {}

# Fails at plan time when the operator-provided log bucket does not exist or is
# not reachable with the credentials running Terraform. This module never
# creates or modifies the bucket.
#
# `bucket_region` is used to prove the bucket and the Web ACL share a Region:
# Firehose cannot deliver to a bucket in another Region.
data "aws_s3_bucket" "logs" {
  bucket = var.log_bucket_name
}
