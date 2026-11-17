variable "container_app_job_name" {
  description = "Name of the Container App Job"
  type        = string
}

variable "location" {
  description = "Container App Job deployed Location"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group Name for CAJ"
  type        = string
}

variable "container_app_environment_id" {
  description = "CAE id"
  type        = string
}

variable "replica_timeout_in_seconds" {
  description = "Max. execution duration per replica in seconds"
  type        = number
  default     = 1800
}

variable "replica_retry_limit" {
  description = "Number of retries for failed replicas"
  type        = number
  default     = 1
}

variable "secrets" {
  description = "List of secrets to mount in the job"
  type = list(object({
    name  = string
    value = string
  }))
  default   = []
  sensitive = true
}

variable "registries" {
  description = "List of private container registries configuration"
  type = list(object({
    server               = string
    username             = optional(string)
    password_secret_name = optional(string)
    identity             = optional(string)
  }))
  default = []
}

variable "trigger_type" {
  description = "Type of trigger"
  type        = string
  default     = "Manual"
}

variable "cron_expression" {
  description = "Cron Expression for the scheduled jobs"
  type        = string
  default     = "* * * * *"
}

variable "containers" {
  description = "List of containers to run in the job"
  type = list(object({
    name                  = string
    image                 = string
    cpu                   = number
    memory                = string
    command               = optional(list(string))
    args                  = optional(list(string))
    environment_variables = optional(map(string), {})
  }))
}

variable "tags" {
  description = "Resource Tag"
  type        = map(string)
  default     = {}
}

variable "identity_type" {
  description = "Type of Managed Identity ('SystemAssigned', 'UserAssigned', or null)"
  type        = string
  default     = null
}

variable "identity_ids" {
  description = "List of User Assigned Managed Identity IDs"
  type        = list(string)
  default     = []
}

variable "workload_profile_name" {
  description = "The workload profile name for the job (e.g. 'Consumption', 'Dedicated-D4')"
  type        = string
  default     = "Consumption"
}
