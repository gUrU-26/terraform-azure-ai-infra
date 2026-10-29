variable "tenant_id" {
  description = "The Tenant ID for Azure authentication"
  type        = string
}

variable "subscription_id" {
  description = "The Subscription ID for Azure authentication"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group of the existing Cosmos DB Account"
  type        = string
}

variable "cosmos_account_name" {
  description = "Name of the existing Cosmos DB Account"
  type        = string
}

variable "cosmos_database_name" {
  description = "Name of the existing Cosmos DB Database"
  type        = string
}

variable "cosmos_container_name" {
  description = "Name of the new Cosmos DB SQL Vector Container"
  type        = string
}

variable "azapi_container_type" {
  description = "The ARM resource type and API version for the Cosmos DB container"
  type        = string
}


variable "location" {
  description = "Azure Region"
  type        = string
}

variable "backup_type" {
  description = "Cosmos DB backup type (e.g., Continuous or Periodic)"
  type        = string
  default     = "Continuous"
}

variable "public_network_access_enabled" {
  description = "Enable public network access for Cosmos DB"
  type        = bool
  default     = true
}

variable "local_authentication_disabled" {
  description = "Disable local authentication for Cosmos DB"
  type        = bool
  default     = false
}

variable "consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Session"
}