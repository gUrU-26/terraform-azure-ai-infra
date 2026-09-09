data "azurerm_cosmosdb_account" "this" {
  name                = var.account_name
  resource_group_name = var.resource_group_name
}

resource "azapi_resource" "vector_container" {
  type      = "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15"
  name      = var.container_name
  parent_id = "${data.azurerm_cosmosdb_account.this.id}/sqlDatabases/${var.database_name}"
  
  schema_validation_enabled = false
  
  body = templatefile("${path.module}/vector_policy.json.tftpl", {
    dimensions_value = var.vector_dimensions
    container_name   = var.container_name
  })
}
