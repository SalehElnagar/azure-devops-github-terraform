mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      id       = "/subscriptions/example/resourceGroups/rg-example"
      name     = "rg-example"
      location = "canadacentral"
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

run "plan_secure_static_website" {
  command = plan

  variables {
    environment                = "dev"
    target_resource_group_name = "rg-example"
    stack_name                 = "dual-pipeline-test"
    deployed_by                = "Terraform Test"
    commit_sha                 = "0123456789abcdef0123456789abcdef01234567"
    owner                      = "platform-team"
    expires_on                 = "2026-07-31"
  }

  assert {
    condition     = azurerm_storage_account.site.min_tls_version == "TLS1_2"
    error_message = "The website storage account must require TLS 1.2 or later."
  }

  assert {
    condition     = azurerm_storage_account.site.https_traffic_only_enabled
    error_message = "The website storage account must enforce HTTPS-only traffic."
  }

  assert {
    condition     = !azurerm_storage_account.site.shared_access_key_enabled
    error_message = "Shared-key authorization must be disabled."
  }

  assert {
    condition     = !azurerm_storage_account.site.allow_nested_items_to_be_public
    error_message = "General nested-item anonymous access must be disabled."
  }

  assert {
    condition     = azurerm_storage_account.site.tags["managed_by"] == "terraform"
    error_message = "The managed_by tag must identify Terraform."
  }

  assert {
    condition     = azurerm_storage_account.site.tags["commit_sha"] == "0123456789abcdef0123456789abcdef01234567"
    error_message = "The source commit must be present in resource metadata."
  }

  assert {
    condition     = azurerm_storage_blob.index.content_type == "text/html"
    error_message = "The generated website must be served as HTML."
  }
}
