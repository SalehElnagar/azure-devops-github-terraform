mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      object_id       = "11111111-1111-1111-1111-111111111111"
      client_id       = "22222222-2222-2222-2222-222222222222"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
      subscription_id = "44444444-4444-4444-4444-444444444444"
    }
  }
}

mock_provider "random" {
  mock_resource "random_string" {
    defaults = {
      result = "abc123"
    }
  }
}

run "plan_keyless_versioned_state_backend" {
  command = plan

  variables {
    name_prefix = "tndstate"
    owner       = "platform-team"
    expires_on  = "2026-08-31"
  }

  assert {
    condition     = !azurerm_storage_account.state.shared_access_key_enabled
    error_message = "The state backend must disable shared-key authorization."
  }

  assert {
    condition     = azurerm_storage_account.state.default_to_oauth_authentication
    error_message = "The state backend must default to Microsoft Entra authorization."
  }

  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].versioning_enabled
    error_message = "The state backend must enable blob versioning."
  }

  assert {
    condition     = azurerm_storage_container.state.container_access_type == "private"
    error_message = "The state container must remain private."
  }

  assert {
    condition     = azurerm_role_assignment.operator_state.role_definition_name == "Storage Blob Data Contributor"
    error_message = "The operator needs data-plane access without storage account keys."
  }
}
