include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment_config = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
}

inputs = {
  name_prefix          = local.environment_config.locals.name_prefix
  environment          = local.environment_config.locals.environment
  location             = local.environment_config.locals.location
  address_space        = local.environment_config.locals.address_space
  subnet_prefixes      = local.environment_config.locals.subnet_prefixes
  owner                = local.environment_config.locals.owner
  expires_on           = local.environment_config.locals.expires_on
  operating_model      = "devops-platform"
  enable_observability = true
  enable_recovery      = true
  enable_delete_lock   = true
  lifecycle_phase      = local.environment_config.locals.lifecycle_phase

  tags = {
    delivery_path = "reviewed-terragrunt"
    state_model   = "remote-azure-blob"
    service_tier  = "platform-foundation"
  }
}
