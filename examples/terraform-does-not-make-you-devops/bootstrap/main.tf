data "azurerm_client_config" "current" {}

locals {
  common_tags = {
    project     = "terraform-does-not-make-you-devops"
    purpose     = "terragrunt-state-backend"
    owner       = var.owner
    expires_on  = var.expires_on
    managed_by  = "terraform"
    environment = "lab"
  }
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${var.name_prefix}-${random_string.suffix.result}"
  location = var.location
  tags     = local.common_tags
}

# The public endpoint permits a local or hosted runner to reach the backend.
# Microsoft Entra authorization is mandatory; shared keys and anonymous access
# are disabled. Production should prefer private endpoints and private runners.
#trivy:ignore:AVD-AZU-0012
#trivy:ignore:AVD-AZU-0057
#trivy:ignore:AVD-AZU-0058
#trivy:ignore:AVD-AZU-0060
resource "azurerm_storage_account" "state" {
  #checkov:skip=CKV_AZURE_33:Queue logging is not applicable; this account stores only Terraform state blobs.
  #checkov:skip=CKV_AZURE_59:The temporary lab backend must be reachable from the operator workstation; shared keys remain disabled.
  #checkov:skip=CKV_AZURE_206:LRS is an explicit low-cost choice for a disposable lab, not a production durability recommendation.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed encryption is accepted for this temporary demonstration backend.
  #checkov:skip=CKV2_AZURE_33:Private endpoints require network-integrated runners outside this self-contained lab.
  name                              = "st${var.name_prefix}${random_string.suffix.result}"
  resource_group_name               = azurerm_resource_group.state.name
  location                          = azurerm_resource_group.state.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  account_kind                      = "StorageV2"
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

resource "azurerm_storage_container" "state" {
  #checkov:skip=CKV2_AZURE_21:The disposable lab backend has no monitoring sink; production state requires diagnostics.
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "operator_state" {
  scope                = azurerm_storage_container.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
