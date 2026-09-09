data "azurerm_cosmosdb_account" "this" {
  name                = var.cosmos_account_name
  resource_group_name = var.resource_group_name
}

# existing cosno db validation
data "azurerm_cosmosdb_sql_database" "this" {
  name                = var.cosmos_database_name
  resource_group_name = var.resource_group_name
  account_name        = var.cosmos_account_name
}

resource "azapi_resource" "vector_container" {
  type      = var.azapi_container_type
  name      = var.cosmos_container_name
  parent_id = data.azurerm_cosmosdb_sql_database.this.id
  
  schema_validation_enabled = false
  
  body = templatefile("${path.module}/vector_policy.json.tftpl", {
    dimensions_value = var.vector_dimensions
    container_name   = var.cosmos_container_name
  })
}