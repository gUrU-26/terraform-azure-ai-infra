variable "cosmos_container_name" {
  description = "Name of the Cosmos DB No SQL Container"
  type        = string
}

variable "cosmos_database_name" {
  description = "Name of the Cosmos DB Database"
  type        = string
}

variable "cosmos_account_name" {
  description = "Name of the Cosmos DB Account"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Resource Group for the Cosmos DB Account"
  type        = string
}

variable "azapi_container_type" {
  description = "The ARM resource type and API version for the Cosmos DB container"
  type        = string
  default     = "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15"
}

variable "vector_dimensions" {
  description = "Dimensions of the vector embeddings"
  type        = number
  default     = 1536
}