output "account_id" {
  description = "The ID of the Cosmos DB Account"
  value       = azurerm_cosmosdb_account.this.id
}

output "account_endpoint" {
  description = "The Endpoint of the Cosmos DB Account"
  value       = azurerm_cosmosdb_account.this.endpoint
}

output "database_id" {
  description = "The ID of the Cosmos DB SQL Database"
  value       = azurerm_cosmosdb_sql_database.this.id
}
