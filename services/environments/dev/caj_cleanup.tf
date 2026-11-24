data "azurerm_container_app_environment" "cae" {
  name                = var.cae_name
  resource_group_name = var.cae_resource_group_name
}
data "azurerm_user_assigned_identity" "acrpull_uami" {
  name                = var.acrpull_uami_name
  resource_group_name = var.uami_resource_group_name
}

module "container_app_job" {
  source                       = "../../../modules/container_app_job"
  container_app_job_name       = var.caj_name
  location                     = var.caj_location
  resource_group_name          = var.caj_resource_group_name
  container_app_environment_id = data.azurerm_container_app_environment.cae.id
  workload_profile_name        = var.caj_workload_profile_name
  replica_timeout_in_seconds   = var.caj_cleanup_replica_timeout
  replica_retry_limit          = var.caj_cleanup_replica_rlimit

  # identity_type = "UserAssigned"
  # identity_ids  = [data.azurerm_user_assigned_identity.acrpull_uami.id]
  # identity_type = null
  # identity_ids  = []


  registries = [
    {
      server = var.acr_login_server
      # identity = data.azurerm_user_assigned_identity.acrpull_uami.id
      identity = "system-environment"
    }
  ]

  trigger_type    = var.caj_cleanup_trigger_type
  cron_expression = var.caj_cleanup_cron_expression

  containers = var.caj_containers

  tags = {
    Environment = "dev"
    CreatedBy   = "Terraform@123"
    Project     = "Boardworks-AI"
  }
}
