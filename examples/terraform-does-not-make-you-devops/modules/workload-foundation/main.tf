locals {
  compact_name = substr(replace("${var.name_prefix}${var.environment}", "-", ""), 0, 14)
  common_tags = merge(var.tags, {
    project         = "terraform-does-not-make-you-devops"
    environment     = var.environment
    owner           = var.owner
    expires_on      = var.expires_on
    managed_by      = "terraform"
    operating_model = var.operating_model
  })
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false

  keepers = {
    environment = var.environment
    name_prefix = var.name_prefix
  }
}

resource "azurerm_resource_group" "workload" {
  name     = "rg-${var.name_prefix}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = local.common_tags

  lifecycle {
    precondition {
      condition = var.environment != "prod" || (
        var.operating_model == "devops-platform" &&
        var.enable_observability &&
        var.enable_recovery &&
        var.enable_delete_lock
      )
      error_message = "Production requires the devops-platform operating model with observability, recovery, and delete protection enabled."
    }
  }
}

resource "azurerm_virtual_network" "workload" {
  name                = "vnet-${var.name_prefix}-${var.environment}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  address_space       = var.address_space
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "workload" {
  name                = "nsg-${var.name_prefix}-${var.environment}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "workload" {
  name                              = "snet-workload"
  resource_group_name               = azurerm_resource_group.workload.name
  virtual_network_name              = azurerm_virtual_network.workload.name
  address_prefixes                  = var.subnet_prefixes
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

# The account is intentionally private and keyless. The lab does not place a
# compute workload inside the subnet, but the private endpoint keeps the
# foundation usable without exposing the storage data plane publicly.
# No Microsoft service needs data-plane access in this lab, so the storage
# firewall deliberately has no trusted-service bypass.
#trivy:ignore:AVD-AZU-0057
#trivy:ignore:AVD-AZU-0058
#trivy:ignore:AVD-AZU-0060
#trivy:ignore:AVD-AZU-0010
resource "azurerm_storage_account" "workload" {
  #checkov:skip=CKV_AZURE_33:Queue logging is not applicable; no queue service is used by this lab.
  #checkov:skip=CKV_AZURE_36:No trusted Microsoft service needs data-plane access; bypass is explicitly disabled.
  #checkov:skip=CKV_AZURE_206:LRS is an explicit low-cost choice for a disposable lab, not a production durability recommendation.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed encryption is sufficient for non-customer demonstration data.
  name                              = "st${local.compact_name}${random_string.suffix.result}"
  resource_group_name               = azurerm_resource_group.workload.name
  location                          = azurerm_resource_group.workload.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  account_kind                      = "StorageV2"
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = false

  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
  }

  dynamic "blob_properties" {
    for_each = var.enable_recovery ? [true] : []

    content {
      versioning_enabled = true

      delete_retention_policy {
        days = 7
      }

      container_delete_retention_policy {
        days = 7
      }
    }
  }

  tags = local.common_tags
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-${azurerm_virtual_network.workload.name}"
  resource_group_name   = azurerm_resource_group.workload.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.workload.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pep-${azurerm_storage_account.workload.name}-blob"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  subnet_id           = azurerm_subnet.workload.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-storage-blob"
    private_connection_resource_id = azurerm_storage_account.workload.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

resource "azurerm_log_analytics_workspace" "platform" {
  count = var.enable_observability ? 1 : 0

  name                = "log-${var.name_prefix}-${var.environment}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

resource "azurerm_application_insights" "platform" {
  count = var.enable_observability ? 1 : 0

  name                         = "appi-${var.name_prefix}-${var.environment}"
  location                     = azurerm_resource_group.workload.location
  resource_group_name          = azurerm_resource_group.workload.name
  workspace_id                 = azurerm_log_analytics_workspace.platform[0].id
  application_type             = "web"
  local_authentication_enabled = false
  tags                         = local.common_tags
}

resource "azurerm_monitor_diagnostic_setting" "network_security_group" {
  count = var.enable_observability ? 1 : 0

  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_network_security_group.workload.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform[0].id

  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }

  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}

resource "azurerm_management_lock" "resource_group" {
  count = var.enable_delete_lock && var.lifecycle_phase == "operate" ? 1 : 0

  name       = "protect-from-accidental-delete"
  scope      = azurerm_resource_group.workload.id
  lock_level = "CanNotDelete"
  notes      = "Managed by Terraform. Remove through the reviewed destroy path only."
}
