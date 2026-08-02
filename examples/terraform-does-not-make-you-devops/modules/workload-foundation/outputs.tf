output "resource_group" {
  description = "Resource group contract exposed to workload teams."
  value = {
    id       = azurerm_resource_group.workload.id
    name     = azurerm_resource_group.workload.name
    location = azurerm_resource_group.workload.location
  }
}

output "network" {
  description = "Network contract exposed to workload teams."
  value = {
    virtual_network_id = azurerm_virtual_network.workload.id
    subnet_id          = azurerm_subnet.workload.id
  }
}

output "storage_account_id" {
  description = "Resource ID of the private, keyless workload storage account."
  value       = azurerm_storage_account.workload.id
}

output "storage_private_endpoint_id" {
  description = "Resource ID of the storage blob private endpoint."
  value       = azurerm_private_endpoint.storage_blob.id
}

output "operational_capabilities" {
  description = "Capabilities selected by the consuming operating model."
  value = {
    operating_model     = var.operating_model
    lifecycle_phase     = var.lifecycle_phase
    observability       = var.enable_observability
    recovery            = var.enable_recovery
    deletion_protection = var.enable_delete_lock && var.lifecycle_phase == "operate"
  }
}
