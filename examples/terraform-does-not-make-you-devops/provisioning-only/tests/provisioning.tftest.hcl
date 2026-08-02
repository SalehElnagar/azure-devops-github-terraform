mock_provider "azurerm" {}

mock_provider "random" {
  mock_resource "random_string" {
    defaults = {
      result = "abc123"
    }
  }
}

run "ticket_driven_root_wires_the_provisioning_only_contract" {
  command = plan

  variables {
    name_prefix = "tndticket"
    owner       = "cloud-operations"
    expires_on  = "2099-12-31"
  }

  assert {
    condition     = output.deployment.operational_capabilities.operating_model == "ticket-driven"
    error_message = "The direct Terraform root must identify the ticket-driven operating model."
  }

  assert {
    condition = (
      !output.deployment.operational_capabilities.observability &&
      !output.deployment.operational_capabilities.recovery &&
      !output.deployment.operational_capabilities.deletion_protection
    )
    error_message = "The direct Terraform root must make its missing lifecycle capabilities explicit."
  }
}
