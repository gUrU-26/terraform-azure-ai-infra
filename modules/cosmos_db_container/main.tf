

resource "azapi_resource" "vector_container" {
  type      = var.azapi_container_type
  name      = var.cosmos_container_name
  parent_id = var.cosmos_database_id

  schema_validation_enabled = false

  body = templatefile("${path.module}/vector_policy.json.tftpl", {
    dimensions_value = var.vector_dimensions
    container_name   = var.cosmos_container_name
  })
}