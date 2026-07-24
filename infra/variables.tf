variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test, or prod."
  }
}

variable "target_resource_group_name" {
  type        = string
  description = "Pre-created resource group assigned to this deployment path."

  validation {
    condition     = length(trimspace(var.target_resource_group_name)) > 0
    error_message = "target_resource_group_name must not be empty."
  }
}

variable "stack_name" {
  type        = string
  description = "Unique logical name for the deployment stack."

  validation {
    condition     = can(regex("^[a-z0-9]+(?:-[a-z0-9]+)*$", var.stack_name))
    error_message = "stack_name must contain lowercase letters, numbers, and single hyphens."
  }
}

variable "deployed_by" {
  type        = string
  description = "Pipeline orchestrator responsible for the deployment."

  validation {
    condition     = length(trimspace(var.deployed_by)) > 0
    error_message = "deployed_by must not be empty."
  }
}

variable "commit_sha" {
  type        = string
  description = "Full source commit associated with the deployment."

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.commit_sha))
    error_message = "commit_sha must be a 40-character lowercase Git SHA."
  }
}

variable "owner" {
  type        = string
  description = "Operational owner recorded on temporary Azure resources."

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "expires_on" {
  type        = string
  description = "ISO date after which temporary resources should not be retained."

  validation {
    condition     = can(regex("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", var.expires_on))
    error_message = "expires_on must use YYYY-MM-DD."
  }
}
