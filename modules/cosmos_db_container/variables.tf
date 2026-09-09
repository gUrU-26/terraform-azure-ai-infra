variable "container_name" {
  description = "Name of the Cosmos DB No SQL Container"
  type        = string
}

variable "database_name" {
  description = "Name of the Cosmos DB Database"
  type        = string
}

variable "account_name" {
  description = "Name of the Cosmos DB Account"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Resource Group for the Cosmos DB Account"
  type        = string
}

variable "vector_dimensions" {
  description = "Dimensions of the vector embeddings"
  type        = number
  default     = 1536
}
