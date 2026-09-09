module "cosmos_vector_container" {
  # Notice the source path goes up three levels now: dev -> environment -> services -> modules
  source              = "../../../modules/cosmos_db_container"
  resource_group_name = var.resource_group_name
  account_name        = var.account_name
  database_name       = var.database_name
  container_name      = var.container_name
}