variable "cae_name" {
  description = "Name of the container app environment"
  type        = string
}
variable "cae_resource_group_name" {
  description = "Rg where CAE is located"
  type        = string
}

variable "acrpull_uami_name" {
  description = "Name of the UAMI for ACR pull"
  type        = string
}

variable "uami_resource_group_name" {
  description = "Rg of UAMI of acr pull"
  type        = string
}

variable "caj_name" {
  description = "Container APp Job name"
  type        = string
}

variable "caj_location" {
  description = "Region Location of the CAJ"
  type        = string
}

variable "caj_resource_group_name" {
  description = "RG of the caj"
  type        = string
}

variable "caj_workload_profile_name" {
  description = "Workload profile for the Container App Job"
  type        = string
  default     = "Consumption"
}

variable "caj_cleanup_replica_timeout" {
  description = "Execution timeout per replica in seconds"
  type        = number
  default     = 1800
}

variable "caj_cleanup_replica_rlimit" {
  description = "Retry limit for failed replica"
  type        = number
  default     = 1
}

variable "acr_login_server" {
  description = "ACR login server e.g. gemsacr.azurecr.io"
  type        = string
}

variable "caj_cleanup_trigger_type" {
  description = "Trigger type ('Schedule/Manual/Event-driven)"
  type        = string
  default     = "Manual"
}

variable "caj_cleanup_cron_expression" {
  description = "Cron expression for the schedule"
  type        = string
  default     = "0 2 * * *"
}

variable "caj_containers" {
  description = "List of containers to deploy in the job"
  type = list(object({
    name                  = string
    image                 = string
    cpu                   = number
    memory                = string
    command               = optional(list(string))
    args                  = optional(list(string))
    environment_variables = optional(map(string), {})

    liveness_probe = optional(object({
      transport               = string # "HTTP", "HTTPS", or "TCP"
      port                    = number
      path                    = optional(string, "/")
      initial_delay           = optional(number, 1)
      interval_seconds        = optional(number, 10)
      timeout                 = optional(number, 1)
      failure_count_threshold = optional(number, 3)
    }))
    startup_probe = optional(object({
      transport               = string
      port                    = number
      path                    = optional(string, "/")
      initial_delay           = optional(number, 1)
      interval_seconds        = optional(number, 10)
      timeout                 = optional(number, 1)
      failure_count_threshold = optional(number, 3)
    }))
  }))
}
