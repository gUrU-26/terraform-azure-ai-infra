module "cosmos_db_account" {
  source              = "../../../modules/cosmos_db_account"
  account_name        = var.cosmos_account_name
  database_name       = var.cosmos_database_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Production settings
  backup_type                   = var.backup_type
  public_network_access_enabled = var.public_network_access_enabled
  local_authentication_disabled = var.local_authentication_disabled
  consistency_level             = var.consistency_level
}

module "cosmos_vector_container" {
  source                = "../../../modules/cosmos_db_container"
  resource_group_name   = var.resource_group_name
  cosmos_account_name   = var.cosmos_account_name
  cosmos_database_name  = var.cosmos_database_name
  cosmos_database_id    = module.cosmos_db_account.database_id
  cosmos_container_name = var.cosmos_container_name
  azapi_container_type  = var.azapi_container_type
}