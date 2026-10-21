terraform {
  # >= 1.10 is required for S3 native state locking (use_lockfile).
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Partial backend configuration.
  #
  # The state bucket is owned by whoever runs this project, so `bucket` and
  # `region` are deliberately absent here and must be supplied at init time:
  #
  #   terraform init -backend-config=backend.hcl
  #
  # `key` is also supplied at init time and MUST include the Region, so each
  # regional deployment has independent state and can be planned and approved
  # on its own:
  #
  #   aws-waf-security/<region>/terraform.tfstate
  #
  # `backend.hcl` is git-ignored; `backend.hcl.example` shows the expected keys.
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
