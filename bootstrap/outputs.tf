output "state" {
  description = "Non-secret state backend location values."
  value = {
    resource_group_name  = azurerm_resource_group.state.name
    storage_account_name = azurerm_storage_account.state.name
    containers = {
      bootstrap       = azurerm_storage_container.state["bootstrap"].name
      github_actions  = azurerm_storage_container.state["github-actions"].name
      azure_pipelines = azurerm_storage_container.state["azure-pipelines"].name
    }
  }
}

output "target_resource_groups" {
  description = "Target resource groups assigned to each orchestrator."
  value = {
    github_actions  = azurerm_resource_group.github.name
    azure_pipelines = azurerm_resource_group.azure_pipelines.name
  }
}

output "identity_client_ids" {
  description = "Client IDs used as non-secret pipeline configuration."
  value = {
    for key, identity in azurerm_user_assigned_identity.pipeline :
    key => identity.client_id
  }
}

output "identity_resource_ids" {
  description = "Managed identity resource IDs needed for Azure DevOps federation setup."
  value = {
    for key, identity in azurerm_user_assigned_identity.pipeline :
    key => identity.id
  }
}

output "identity_resource_group_name" {
  description = "Resource group containing the four pipeline identities."
  value       = azurerm_resource_group.identity.name
}

output "identity_names" {
  description = "Managed identity resource names used by federation setup."
  value       = local.identity_names
}

output "deployment" {
  description = "Non-secret operational metadata used by both pipeline configurations."
  value = {
    owner      = var.owner
    expires_on = var.expires_on
  }
}
