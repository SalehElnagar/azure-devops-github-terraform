data "azurerm_resource_group" "target" {
  name = var.target_resource_group_name
}

locals {
  normalized_stack = substr(replace(var.stack_name, "-", ""), 0, 14)
  common_tags = {
    project     = "dual-pipeline-terraform"
    purpose     = "pipeline-comparison"
    owner       = var.owner
    expires_on  = var.expires_on
    environment = var.environment
    managed_by  = "terraform"
    deployed_by = var.deployed_by
    commit_sha  = var.commit_sha
  }
  page_content = templatefile("${path.module}/site/index.html.tftpl", {
    environment = var.environment
    stack_name  = var.stack_name
    deployed_by = var.deployed_by
    commit_sha  = var.commit_sha
  })
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

#trivy:ignore:AVD-AZU-0012
resource "azurerm_storage_account" "site" {
  #checkov:skip=CKV_AZURE_33:Queue Storage Analytics is not applicable; the workload uses only static website blobs.
  #checkov:skip=CKV_AZURE_59:The public static website is the demonstration output; shared keys remain disabled.
  #checkov:skip=CKV_AZURE_206:LRS is an explicit cost choice for a reproducible, disposable demonstration.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed encryption is accepted for non-customer demonstration content.
  #checkov:skip=CKV2_AZURE_33:The public static website intentionally has no private endpoint.
  #checkov:skip=CKV2_AZURE_38:Website content is source-reproducible and the lifecycle requires complete destroy.
  name                              = "st${local.normalized_stack}${random_string.suffix.result}"
  resource_group_name               = data.azurerm_resource_group.target.name
  location                          = data.azurerm_resource_group.target.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  account_kind                      = "StorageV2"
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true

  tags = local.common_tags
}

resource "azurerm_storage_container" "web" {
  #checkov:skip=CKV2_AZURE_21:The short-lived lab has no log workspace; production hosting requires diagnostics.
  name                  = "$web"
  storage_account_id    = azurerm_storage_account.site.id
  container_access_type = "private"
}

resource "azurerm_storage_account_static_website" "site" {
  storage_account_id = azurerm_storage_account.site.id
  index_document     = "index.html"

  depends_on = [azurerm_storage_container.web]
}

resource "azurerm_storage_blob" "index" {
  name                 = "index.html"
  storage_container_id = azurerm_storage_container.web.id
  type                 = "Block"
  source_content       = local.page_content
  content_type         = "text/html"

  depends_on = [azurerm_storage_account_static_website.site]
}
