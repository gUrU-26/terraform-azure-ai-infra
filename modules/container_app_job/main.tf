resource "azurerm_container_app_job" "this" {
  name                         = var.container_app_job_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  workload_profile_name        = var.workload_profile_name
  replica_timeout_in_seconds   = var.replica_timeout_in_seconds
  replica_retry_limit          = var.replica_retry_limit

  dynamic "identity" {
    for_each = var.identity_type != null ? [1] : []
    content {
      type         = var.identity_type
      identity_ids = var.identity_type == "SystemAssigned" ? null : var.identity_ids
    }
  }

  dynamic "secret" {
    for_each = var.secrets
    content {
      name  = secret.value.name
      value = secret.value.value
    }
  }

  dynamic "registry" {
    for_each = var.registries
    content {
      server               = registry.value.server
      username             = registry.value.username
      password_secret_name = registry.value.password_secret_name
      identity             = registry.value.identity
    }
  }

  dynamic "schedule_trigger_config" {
    for_each = var.trigger_type == "Schedule" ? [1] : []
    content {
      cron_expression = var.cron_expression
    }
  }
  dynamic "manual_trigger_config" {
    for_each = var.trigger_type == "Manual" ? [1] : []
    content {}
  }

  template {
    dynamic "container" {
      for_each = var.containers
      content {
        name    = container.value.name
        image   = container.value.image
        cpu     = container.value.cpu
        memory  = container.value.memory
        command = try(container.value.command, null)
        args    = try(container.value.args, null)

        dynamic "env" {
          for_each = try(container.value.environment_variables, {}) != null ? container.value.environment_variables : {}
          content {
            name  = env.key
            value = env.value
          }
        }
        dynamic "liveness_probe" {
          for_each = try(container.value.liveness_probe, null) != null ? [container.value.liveness_probe] : []
          content {
            transport               = liveness_probe.value.transport # "HTTP", "HTTPS", or "TCP"
            port                    = liveness_probe.value.port
            path                    = try(liveness_probe.value.path, null)
            initial_delay           = try(liveness_probe.value.initial_delay, 1)
            interval_seconds        = try(liveness_probe.value.interval_seconds, 10)
            timeout                 = try(liveness_probe.value.timeout, 1)
            failure_count_threshold = try(liveness_probe.value.failure_count_threshold, 3)
          }
        }
        dynamic "startup_probe" {
          for_each = try(container.value.startup_probe, null) != null ? [container.value.startup_probe] : []
          content {
            transport               = startup_probe.value.transport
            port                    = startup_probe.value.port
            path                    = try(startup_probe.value.path, null)
            initial_delay           = try(startup_probe.value.initial_delay, 1)
            interval_seconds        = try(startup_probe.value.interval_seconds, 10)
            timeout                 = try(startup_probe.value.timeout, 1)
            failure_count_threshold = try(startup_probe.value.failure_count_threshold, 3)
          }
        }
      }
    }
  }
  tags = var.tags
}
