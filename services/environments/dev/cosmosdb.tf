module "cosmos_vector_container" {
  source              = "../../../modules/cosmos_db_container"
  resource_group_name = var.resource_group_name
  cosmos_account_name  = var.cosmos_account_name
  cosmos_database_name = var.cosmos_database_name
  cosmos_container_name= var.cosmos_container_name
  azapi_container_type = var.azapi_container_type
}