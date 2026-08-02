output "terragrunt_backend" {
  description = "Non-secret values exported as TG_STATE_* environment variables."
  value = {
    resource_group_name  = azurerm_resource_group.state.name
    storage_account_name = azurerm_storage_account.state.name
    container_name       = azurerm_storage_container.state.name
  }
}
