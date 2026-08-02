variable "name_prefix" {
  type        = string
  description = "Lowercase prefix used in the state backend resource names."
  default     = "tndstate"

  validation {
    condition     = can(regex("^[a-z0-9]{4,12}$", var.name_prefix))
    error_message = "name_prefix must contain 4-12 lowercase letters or numbers."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the state backend."
  default     = "canadacentral"
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
  description = "ISO date after which this temporary backend must be removed."

  validation {
    condition     = can(regex("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", var.expires_on))
    error_message = "expires_on must use YYYY-MM-DD."
  }
}
