locals {
  project = "dual-pipeline-terraform"
  common_tags = {
    project     = local.project
    purpose     = "pipeline-comparison"
    owner       = var.owner
    expires_on  = var.expires_on
    environment = "dev"
    managed_by  = "terraform"
  }
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${var.name_prefix}-state-${random_string.suffix.result}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "identity" {
  name     = "rg-${var.name_prefix}-identity-${random_string.suffix.result}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "github" {
  name     = "rg-${var.name_prefix}-gha-dev-${random_string.suffix.result}"
  location = var.location
  tags     = merge(local.common_tags, { apply_owner = "github-actions" })
}

resource "azurerm_resource_group" "azure_pipelines" {
  name     = "rg-${var.name_prefix}-azdo-dev-${random_string.suffix.result}"
  location = var.location
  tags     = merge(local.common_tags, { apply_owner = "azure-pipelines" })
}

#trivy:ignore:AVD-AZU-0012
resource "azurerm_storage_account" "state" {
  #checkov:skip=CKV_AZURE_33:Queue Storage Analytics is not applicable; this account stores only Terraform blobs.
  #checkov:skip=CKV_AZURE_59:Hosted runners require the public endpoint; anonymous access and shared keys remain disabled.
  #checkov:skip=CKV_AZURE_206:LRS is an explicit cost choice for a disposable lab; durable backends require stronger replication.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed encryption is accepted for ephemeral, non-customer demonstration state.
  #checkov:skip=CKV2_AZURE_33:Hosted runners cannot reach a private endpoint in this self-contained public-runner lab.
  name                              = "st${var.name_prefix}${random_string.suffix.result}"
  resource_group_name               = azurerm_resource_group.state.name
  location                          = azurerm_resource_group.state.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  account_kind                      = "StorageV2"
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
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
  #checkov:skip=CKV2_AZURE_21:The short-lived lab has no log workspace; production state requires diagnostic retention.
  for_each = toset([
    "bootstrap",
    "github-actions",
    "azure-pipelines",
  ])

  name                  = each.value
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}
