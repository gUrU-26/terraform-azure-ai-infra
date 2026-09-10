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