resource "azurerm_federated_identity_credential" "github_plan" {
  name                = "github-main-plan"
  resource_group_name = azurerm_resource_group.identity.name
  parent_id           = azurerm_user_assigned_identity.pipeline["github_plan"].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "${var.github_oidc_subject_prefix}:ref:refs/heads/${var.github_branch}"
}

resource "azurerm_federated_identity_credential" "github_apply" {
  for_each = toset([
    var.github_apply_environment,
    var.github_destroy_environment,
  ])

  name                = "github-${replace(each.value, "_", "-")}"
  resource_group_name = azurerm_resource_group.identity.name
  parent_id           = azurerm_user_assigned_identity.pipeline["github_apply"].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "${var.github_oidc_subject_prefix}:environment:${each.value}"
}
