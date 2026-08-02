locals {
  subscription_id        = get_env("ARM_SUBSCRIPTION_ID")
  state_resource_group   = get_env("TG_STATE_RESOURCE_GROUP")
  state_storage_account  = get_env("TG_STATE_STORAGE_ACCOUNT")
  state_container        = get_env("TG_STATE_CONTAINER", "tfstate")
  workload_module_source = "${get_repo_root()}/examples/terraform-does-not-make-you-devops/modules/workload-foundation"
}

remote_state {
  backend = "azurerm"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    resource_group_name  = local.state_resource_group
    storage_account_name = local.state_storage_account
    container_name       = local.state_container
    key                  = "${path_relative_to_include()}/terraform.tfstate"
    subscription_id      = local.subscription_id
    use_azuread_auth     = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "azurerm" {
      features {}
      storage_use_azuread = true
    }
  EOF
}

terraform {
  source = local.workload_module_source
}
