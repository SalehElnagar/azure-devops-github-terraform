mock_provider "azurerm" {}

mock_provider "random" {
  mock_resource "random_string" {
    defaults = {
      result = "abc123"
    }
  }
}

run "devops_platform_enables_operational_capabilities" {
  command = plan

  variables {
    name_prefix          = "tndplatform"
    environment          = "dev"
    owner                = "platform-team"
    expires_on           = "2026-08-31"
    operating_model      = "devops-platform"
    enable_observability = true
    enable_recovery      = true
    enable_delete_lock   = true
  }

  assert {
    condition     = !azurerm_storage_account.workload.shared_access_key_enabled
    error_message = "The platform storage account must disable shared-key authorization."
  }

  assert {
    condition     = !azurerm_storage_account.workload.public_network_access_enabled
    error_message = "The platform storage account must disable public network access."
  }

  assert {
    condition     = azurerm_storage_account.workload.network_rules[0].default_action == "Deny"
    error_message = "The platform storage account network ACL must default to deny."
  }

  assert {
    condition = (
      length(azurerm_storage_account.workload.network_rules[0].bypass) == 1 &&
      contains(azurerm_storage_account.workload.network_rules[0].bypass, "None")
    )
    error_message = "The platform storage account must explicitly disable trusted-service bypass."
  }

  assert {
    condition     = contains(azurerm_private_endpoint.storage_blob.private_service_connection[0].subresource_names, "blob")
    error_message = "The storage account must be reachable only through a blob private endpoint."
  }

  assert {
    condition     = length(azurerm_storage_account.workload.blob_properties) == 1
    error_message = "The platform path must configure blob recovery properties."
  }

  assert {
    condition     = azurerm_storage_account.workload.blob_properties[0].versioning_enabled
    error_message = "The platform path must enable blob versioning."
  }

  assert {
    condition     = azurerm_storage_account.workload.blob_properties[0].delete_retention_policy[0].days == 7
    error_message = "The platform path must retain deleted blobs for seven days."
  }

  assert {
    condition     = azurerm_storage_account.workload.blob_properties[0].container_delete_retention_policy[0].days == 7
    error_message = "The platform path must retain deleted containers for seven days."
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.platform) == 1
    error_message = "The platform path must create a Log Analytics workspace."
  }

  assert {
    condition     = length(azurerm_application_insights.platform) == 1
    error_message = "The platform path must create Application Insights."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.network_security_group) == 1
    error_message = "The platform path must route NSG diagnostics to Log Analytics."
  }

  assert {
    condition     = length(azurerm_management_lock.resource_group) == 1
    error_message = "The platform path must protect the resource group from accidental deletion."
  }

  assert {
    condition     = azurerm_resource_group.workload.tags["operating_model"] == "devops-platform"
    error_message = "Azure tags must identify the selected operating model."
  }
}

run "ticket_driven_path_provisions_without_lifecycle_capabilities" {
  command = plan

  variables {
    name_prefix          = "tndticket"
    environment          = "dev"
    owner                = "cloud-operations"
    expires_on           = "2026-08-31"
    operating_model      = "ticket-driven"
    enable_observability = false
    enable_recovery      = false
    enable_delete_lock   = false
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.platform) == 0
    error_message = "The ticket-driven path should expose the absence of an observability contract."
  }

  assert {
    condition     = length(azurerm_storage_account.workload.blob_properties) == 0
    error_message = "The ticket-driven path should expose the absence of a recovery contract."
  }

  assert {
    condition     = length(azurerm_management_lock.resource_group) == 0
    error_message = "The ticket-driven path should expose the absence of deletion protection."
  }

  assert {
    condition     = azurerm_resource_group.workload.tags["operating_model"] == "ticket-driven"
    error_message = "Azure tags must identify the selected operating model."
  }
}

run "production_rejects_incomplete_operating_model" {
  command = plan

  variables {
    name_prefix          = "tndprod"
    environment          = "prod"
    owner                = "platform-team"
    expires_on           = "2026-08-31"
    operating_model      = "ticket-driven"
    enable_observability = false
    enable_recovery      = false
    enable_delete_lock   = false
  }

  expect_failures = [azurerm_resource_group.workload]
}

run "teardown_phase_removes_only_the_delete_lock" {
  command = plan

  variables {
    name_prefix          = "tndteardown"
    environment          = "dev"
    owner                = "platform-team"
    expires_on           = "2026-08-31"
    operating_model      = "devops-platform"
    enable_observability = true
    enable_recovery      = true
    enable_delete_lock   = true
    lifecycle_phase      = "teardown"
  }

  assert {
    condition     = length(azurerm_management_lock.resource_group) == 0
    error_message = "The explicit teardown phase must remove the delete lock before destroy."
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.platform) == 1
    error_message = "Entering teardown must not disable unrelated platform capabilities."
  }

  assert {
    condition = (
      output.operational_capabilities.lifecycle_phase == "teardown" &&
      !output.operational_capabilities.deletion_protection
    )
    error_message = "The module output must expose that teardown protection is no longer active."
  }
}
