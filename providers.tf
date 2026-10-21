provider "aws" {
  region = var.aws_region

  # Applied to every taggable resource created by this module.
  default_tags {
    tags = local.tags
  }
}
