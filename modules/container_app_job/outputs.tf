output "job_id" {
  description = "The ID of the Container App Job"
  value       = azurerm_container_app_job.this.id
}

output "job_name" {
  description = "The Name of the Container App Job"
  value       = azurerm_container_app_job.this.name
}
