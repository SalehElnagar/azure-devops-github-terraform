variable "location" {
  type        = string
  description = "Azure region for temporary demonstration resources."
  default     = "canadacentral"
}

variable "name_prefix" {
  type        = string
  description = "Lowercase prefix used for globally and locally unique resource names."
  default     = "dualpipeline"

  validation {
    condition     = can(regex("^[a-z0-9]{4,12}$", var.name_prefix))
    error_message = "name_prefix must contain 4-12 lowercase letters or numbers."
  }
}

variable "owner" {
  type        = string
  description = "Operational owner recorded in resource tags."

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "expires_on" {
  type        = string
  description = "ISO date after which the temporary demonstration must be removed."

  validation {
    condition     = can(regex("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", var.expires_on))
    error_message = "expires_on must use YYYY-MM-DD."
  }
}

variable "bootstrap_operator_object_id" {
  type        = string
  description = "Microsoft Entra object ID of the operator migrating bootstrap state."

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.bootstrap_operator_object_id))
    error_message = "bootstrap_operator_object_id must be a UUID."
  }
}

variable "github_oidc_subject_prefix" {
  type        = string
  description = "Exact GitHub OIDC repository prefix, including immutable IDs when enabled."

  validation {
    condition     = startswith(var.github_oidc_subject_prefix, "repo:")
    error_message = "github_oidc_subject_prefix must start with repo:."
  }
}

variable "github_branch" {
  type        = string
  description = "Trusted Git branch for the GitHub plan identity."
  default     = "main"
}

variable "github_apply_environment" {
  type        = string
  description = "Protected GitHub environment used for apply."
  default     = "dev"
}

variable "github_destroy_environment" {
  type        = string
  description = "Protected GitHub environment used for destroy."
  default     = "dev-destroy"
}
