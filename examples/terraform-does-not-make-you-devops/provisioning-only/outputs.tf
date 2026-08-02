output "deployment" {
  description = "Provisioned Azure foundation and the capabilities this path omitted."
  value = {
    resource_group           = module.workload_foundation.resource_group
    network                  = module.workload_foundation.network
    storage_account_id       = module.workload_foundation.storage_account_id
    operational_capabilities = module.workload_foundation.operational_capabilities
  }
}
