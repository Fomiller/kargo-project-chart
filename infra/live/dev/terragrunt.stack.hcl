locals {
  stacks_path  = find_in_parent_folders("stacks")
  account_vars = read_terragrunt_config("${get_terragrunt_dir()}/account.hcl")
}

stack "aws" {
  source                  = "${local.stacks_path}/aws/global"
  path                    = "aws/global"
  no_dot_terragrunt_stack = true

  values = {
    environment = local.account_vars.locals.environment
  }
}
