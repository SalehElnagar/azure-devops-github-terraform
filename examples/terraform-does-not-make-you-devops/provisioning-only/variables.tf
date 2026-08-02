variable "name_prefix" {
  type        = string
  description = "Lowercase prefix used in Azure resource names."
  default     = "tndticket"
}

variable "location" {
  type        = string
  description = "Azure region for the temporary demonstration."
  default     = "canadacentral"
}

variable "owner" {
  type        = string
  description = "Operational owner recorded in Azure tags."
}

variable "expires_on" {
  type        = string
  description = "ISO date after which the temporary deployment must be removed."
}
