terraform {
  required_version = "= 1.14.7"

  backend "local" {
    path = "terraform.tfstate"
  }

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
}
