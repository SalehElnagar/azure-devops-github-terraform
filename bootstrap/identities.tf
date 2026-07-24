locals {
  identity_names = {
    github_plan           = "id-${var.name_prefix}-gha-plan"
    github_apply          = "id-${var.name_prefix}-gha-apply"
    azure_pipelines_plan  = "id-${var.name_prefix}-azdo-plan"
    azure_pipelines_apply = "id-${var.name_prefix}-azdo-apply"
  }
}

resource "azurerm_user_assigned_identity" "pipeline" {
  for_each = local.identity_names

  name                = each.value
  location            = azurerm_resource_group.identity.location
  resource_group_name = azurerm_resource_group.identity.name
  tags                = merge(local.common_tags, { identity_purpose = each.key })
}
