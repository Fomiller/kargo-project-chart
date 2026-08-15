# Root Terragrunt config. Every unit includes this, so a unit's own
# terragrunt.hcl only needs `include "root"` plus its inputs.
#
# This mirrors the layout in Fomiller/homelab, minus the multi-provider
# dispatch: every unit here is AWS, so the provider block is written directly
# rather than derived from the path. State lands in the same bucket homelab
# uses, namespaced by repo_name.

locals {
  service_vars = read_terragrunt_config(find_in_parent_folders("service.hcl"))
  tag_vars     = read_terragrunt_config(find_in_parent_folders("tags.hcl"))
  version_vars = read_terragrunt_config(find_in_parent_folders("version.hcl"))
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  environment = local.account_vars.locals.environment
  region      = local.account_vars.locals.region

  bucket = "fomiller-terraform-state-${local.environment}"
}

remote_state {
  backend = "s3"
  config = {
    encrypt               = true
    disable_bucket_update = true
    bucket                = local.bucket
    # <repo>/<env>/<provider>/<scope>/<unit>/terraform.tfstate
    key          = "${local.service_vars.locals.repo_name}/${path_relative_to_include()}/terraform.tfstate"
    region       = local.region
    use_lockfile = true
  }
  generate = {
    path      = "_.backend.gen.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "_.provider.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "aws" {
      region = "${local.region}"
      default_tags {
        tags = ${jsonencode(local.tag_vars.locals.default_tags)}
      }
    }
  EOT
}

generate "versions" {
  path      = "_.versions.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = "${local.version_vars.locals.terraform_version}"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "${local.version_vars.locals.aws_provider_version}"
        }
      }
    }
  EOF
}

generate "variables" {
  path      = "_.variables.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    variable "environment" {
      type    = string
      default = "${local.environment}"
    }

    variable "app_prefix" {
      type    = string
      default = "${local.service_vars.locals.app_prefix}"
    }

    variable "namespace" {
      type    = string
      default = "${local.service_vars.locals.namespace}"
    }

    variable "asset_name" {
      type = string
    }
  EOF
}
