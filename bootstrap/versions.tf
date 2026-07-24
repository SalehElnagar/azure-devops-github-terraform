terraform {
  required_version = "= 1.14.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.81.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "= 3.9.0"
    }
  }

  # The ephemeral lab must be able to destroy the state account it creates.
  # Production users should replace this with a separately owned remote backend.
  backend "local" {
    path = "../local/bootstrap.tfstate"
  }
}
