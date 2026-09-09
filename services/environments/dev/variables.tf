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

variable "account_name" {
  description = "Name of the existing Cosmos DB Account"
  type        = string
}

variable "database_name" {
  description = "Name of the existing Cosmos DB Database"
  type        = string
}

variable "container_name" {
  description = "Name of the new Cosmos DB SQL Vector Container"
  type        = string
}
