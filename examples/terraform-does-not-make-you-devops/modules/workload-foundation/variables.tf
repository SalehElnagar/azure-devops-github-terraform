variable "name_prefix" {
  type        = string
  description = "Lowercase prefix used in Azure resource names."

  validation {
    condition     = can(regex("^[a-z0-9]{4,12}$", var.name_prefix))
    error_message = "name_prefix must contain 4-12 lowercase letters or numbers."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test, or prod."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the workload foundation."
  default     = "canadacentral"
}

variable "address_space" {
  type        = list(string)
  description = "Address space assigned to the workload virtual network."
  default     = ["10.42.0.0/16"]

  validation {
    condition     = length(var.address_space) == 1 && can(cidrnetmask(var.address_space[0]))
    error_message = "address_space must contain exactly one valid CIDR block."
  }
}

variable "subnet_prefixes" {
  type        = list(string)
  description = "Address prefixes assigned to the workload subnet."
  default     = ["10.42.1.0/24"]

  validation {
    condition     = length(var.subnet_prefixes) == 1 && can(cidrnetmask(var.subnet_prefixes[0]))
    error_message = "subnet_prefixes must contain exactly one valid CIDR block."
  }
}

variable "owner" {
  type        = string
  description = "Operational owner recorded in Azure tags."

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "expires_on" {
  type        = string
  description = "ISO date after which this temporary lab deployment must be removed."

  validation {
    condition     = can(regex("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", var.expires_on))
    error_message = "expires_on must use YYYY-MM-DD."
  }
}

variable "operating_model" {
  type        = string
  description = "Operating model demonstrated by this module instance."

  validation {
    condition     = contains(["ticket-driven", "devops-platform"], var.operating_model)
    error_message = "operating_model must be ticket-driven or devops-platform."
  }
}

variable "enable_observability" {
  type        = bool
  description = "Create a Log Analytics workspace, Application Insights, and NSG diagnostics."
  default     = false
}

variable "enable_recovery" {
  type        = bool
  description = "Enable blob versioning and short-lived soft-delete retention."
  default     = false
}

variable "enable_delete_lock" {
  type        = bool
  description = "Protect the workload resource group from accidental deletion."
  default     = false
}

variable "lifecycle_phase" {
  type        = string
  description = "Operate normally with protection, or enter an explicit teardown phase that removes the delete lock first."
  default     = "operate"

  validation {
    condition     = contains(["operate", "teardown"], var.lifecycle_phase)
    error_message = "lifecycle_phase must be operate or teardown."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional non-secret tags merged into the required operating metadata."
  default     = {}
}
