locals {
  state_bindings = {
    github_plan = {
      container = "github-actions"
    }
    github_apply = {
      container = "github-actions"
    }
    azure_pipelines_plan = {
      container = "azure-pipelines"
    }
    azure_pipelines_apply = {
      container = "azure-pipelines"
    }
  }

  target_bindings = {
    github_plan = {
      scope      = azurerm_resource_group.github.id
      management = "Reader"
      data       = "Storage Blob Data Reader"
    }
    github_apply = {
      scope      = azurerm_resource_group.github.id
      management = "Contributor"
      data       = "Storage Blob Data Contributor"
    }
    azure_pipelines_plan = {
      scope      = azurerm_resource_group.azure_pipelines.id
      management = "Reader"
      data       = "Storage Blob Data Reader"
    }
    azure_pipelines_apply = {
      scope      = azurerm_resource_group.azure_pipelines.id
      management = "Contributor"
      data       = "Storage Blob Data Contributor"
    }
  }
}

resource "azurerm_role_assignment" "state" {
  for_each = local.state_bindings

  scope                = azurerm_storage_container.state[each.value.container].resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.pipeline[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "target_management" {
  for_each = local.target_bindings

  scope                = each.value.scope
  role_definition_name = each.value.management
  principal_id         = azurerm_user_assigned_identity.pipeline[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "target_data" {
  for_each = local.target_bindings

  scope                = each.value.scope
  role_definition_name = each.value.data
  principal_id         = azurerm_user_assigned_identity.pipeline[each.key].principal_id
  principal_type       = "ServicePrincipal"
}
resource "azurerm_role_assignment" "bootstrap_operator_state" {
  scope                = azurerm_storage_container.state["bootstrap"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.bootstrap_operator_object_id
}
