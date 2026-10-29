variable "account_name" {
  description = "Name of the Cosmos DB account"
  type        = string
}

variable "database_name" {
  description = "Name of the Cosmos DB SQL Database"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group where the Cosmos DB will be deployed"
  type        = string
}

variable "location" {
  description = "Azure Region for the Cosmos DB"
  type        = string
}

variable "public_network_access_enabled" {
  description = "Whether public network access is allowed for this Cosmos DB account. Set to false for strict production using private endpoints."
  type        = bool
  default     = true
}

variable "local_authentication_disabled" {
  description = "Whether local authentication (using account keys) is disabled. Recommended true for production using Azure AD."
  type        = bool
  default     = false
}

variable "enable_serverless" {
  description = "Enable Serverless capacity mode instead of Provisioned."
  type        = bool
  default     = false
}

variable "consistency_level" {
  description = "Consistency policy level (e.g., Session, BoundedStaleness, Strong, ConsistentPrefix, Eventual)"
  type        = string
  default     = "Session"
}

variable "max_interval_in_seconds" {
  description = "Max interval in seconds for BoundedStaleness"
  type        = number
  default     = 5
}

variable "max_staleness_prefix" {
  description = "Max staleness prefix for BoundedStaleness"
  type        = number
  default     = 100
}

variable "zone_redundant" {
  description = "Enable Availability Zone redundancy for the default region."
  type        = bool
  default     = false
}

variable "backup_type" {
  description = "Type of backup: Periodic or Continuous. Continuous is recommended for production (PITR)."
  type        = string
  default     = "Continuous"
}

variable "backup_interval_in_minutes" {
  description = "Interval in minutes for Periodic backups"
  type        = number
  default     = 240
}

variable "backup_retention_in_hours" {
  description = "Retention in hours for Periodic backups"
  type        = number
  default     = 8
}

variable "backup_storage_redundancy" {
  description = "Storage redundancy for Periodic backups (Geo, Local, Zone)"
  type        = string
  default     = "Local"
}

variable "tags" {
  description = "Tags to apply to the Cosmos DB account"
  type        = map(string)
  default     = {}
}
