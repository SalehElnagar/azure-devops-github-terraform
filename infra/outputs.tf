output "website_url" {
  description = "Public HTTPS endpoint of the generated static website."
  value       = azurerm_storage_account.site.primary_web_endpoint
}

output "storage_account_name" {
  description = "Name of the website storage account."
  value       = azurerm_storage_account.site.name
}

output "deployed_commit" {
  description = "Source commit rendered into the deployed page."
  value       = var.commit_sha
}
