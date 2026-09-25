############################################
# Core / naming
############################################

variable "project_id" {
  description = "GCP project ID to deploy resources into."
  type        = string
}

variable "name" {
  description = "Base name used for the instance template, MIG, health check, and autoscaler. Must be lowercase RFC1035 compliant."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid RFC1035 label: lowercase letters, numbers, hyphens; must start with a letter."
  }
}

variable "hostname" {
  description = "Hostname prefix for instances"
  type        = string
  default     = "default"
}

variable "region" {
  description = "Region for the regional Managed Instance Group, autoscaler, and health check."
  type        = string
}

variable "distribution_zones" {
  description = "Optional list of zones (within var.region) to explicitly constrain the MIG's zonal distribution policy. Leave empty to let GCP distribute across all zones in the region."
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels applied to the instance template and, where supported, the MIG."
  type        = map(string)
  default     = {}
}

############################################
# Managed Instance Group configuration
############################################

variable "target_size" {
  description = "Initial number of instances. Ignored (managed by autoscaler) once autoscaling is enabled and has run once, but still required at creation."
  type        = number
  default     = 2
}

variable "description" {
  description = "Description of instance template"
  type        = string
  default     = null
}

variable "instance_template" {
  type = string
}

variable "named_ports" {
  description = "Named ports exposed by the MIG, consumed by load balancer backend services."
  type = list(object({
    name = string
    port = number
  }))
  default = []
}

variable "update_policy" {
  description = "Rolling update policy for the MIG."
  type = object({
    type                    = optional(string, "PROACTIVE") # PROACTIVE or OPPORTUNISTIC
    minimal_action          = optional(string, "REPLACE")   # REPLACE or RESTART
    max_surge_fixed         = optional(number, 3)
    max_surge_percent       = optional(number, null)
    max_unavailable_fixed   = optional(number, 0)
    max_unavailable_percent = optional(number, null)
    replacement_method      = optional(string, "SUBSTITUTE") # SUBSTITUTE or RECREATE
  })
  default = {}
}

variable "health_check_initial_delay_sec" {
  description = "Grace period before the MIG's auto-healing policy considers a failed health check (avoids flapping during boot)."
  type        = number
  default     = 300
}

############################################
# Health check
############################################

variable "health_check" {
  description = "Health check configuration used both for auto-healing and (optionally) load balancer backends."
  type = object({
    type                = optional(string, "HTTP") # HTTP, HTTPS, TCP, SSL, HTTP2, GRPC
    port                = optional(number, 80)
    request_path        = optional(string, "/")
    check_interval_sec  = optional(number, 10)
    timeout_sec         = optional(number, 5)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 3)
  })
  default = {}
}

############################################
# Autoscaling
############################################
variable "autoscaler_name" {
  type        = string
  description = "Autoscaler name. When variable is empty, name will be derived from var.hostname."
  default     = ""
}

variable "autoscaling_enabled" {
  description = "Creates an autoscaler for the managed instance group"
  default     = "false"
  type        = string
}

variable "max_replicas" {
  description = "The maximum number of instances that the autoscaler can scale up to. This is required when creating or updating an autoscaler. The maximum number of replicas should not be lower than minimal number of replicas."
  default     = 10
  type        = number
}

variable "min_replicas" {
  description = "The minimum number of replicas that the autoscaler can scale down to. This cannot be less than 0."
  default     = 2
  type        = number
}

variable "cooldown_period" {
  description = "The number of seconds that the autoscaler should wait before it starts collecting information from a new instance."
  default     = 60
  type        = number
}

variable "autoscaling_mode" {
  description = "Operating mode of the autoscaling policy. If omitted, the default value is ON. https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_autoscaler#mode"
  type        = string
  default     = null
}

variable "autoscaling_cpu" {
  description = "Autoscaling, cpu utilization policy block as single element array. https://www.terraform.io/docs/providers/google/r/compute_autoscaler#cpu_utilization"
  type = list(object({
    target            = number
    predictive_method = string
  }))
  default = []
}

variable "autoscaling_metric" {
  description = "Autoscaling, metric policy block as single element array. https://www.terraform.io/docs/providers/google/r/compute_autoscaler#metric"
  type = list(object({
    name   = string
    target = number
    type   = string
  }))
  default = []
}

variable "autoscaling_lb" {
  description = "Autoscaling, load balancing utilization policy block as single element array. https://www.terraform.io/docs/providers/google/r/compute_autoscaler#load_balancing_utilization"
  type        = list(map(number))
  default     = []
}

variable "scaling_schedules" {
  description = "Autoscaling, scaling schedule block. https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_autoscaler#scaling_schedules"
  type = list(object({
    disabled              = bool
    duration_sec          = number
    min_required_replicas = number
    name                  = string
    schedule              = string
    time_zone             = string
  }))
  default = []
}

variable "autoscaling_scale_in_control" {
  description = "Autoscaling, scale-in control block. https://www.terraform.io/docs/providers/google/r/compute_autoscaler#scale_in_control"
  type = object({
    fixed_replicas   = number
    percent_replicas = number
    time_window_sec  = number
  })
  default = {
    fixed_replicas   = null
    percent_replicas = null
    time_window_sec  = null
  }
}

variable "distribution_policy_target_shape" {
  type    = string
  default = null
}

variable "list_managed_instances_results" {
  type    = string
  default = null
}

variable "wait_for_instances" {
  type    = bool
  default = false
}

variable "wait_for_instances_status" {
  type    = string
  default = "STABLE"
}

variable "target_pools" {
  type    = set(string)
  default = []
}

variable "target_stopped_size" {
  type    = number
  default = 0
}

variable "target_suspended_size" {
  type    = number
  default = 0
}

variable "stateful_disk" {
  type = set(object({
    delete_rule = string
    device_name = string
  }))
  default = []
}

variable "stateful_external_ip" {
  type = list(object({
    delete_rule    = string
    interface_name = string
  }))
  default = []
}

variable "stateful_internal_ip" {
  type = list(object({
    delete_rule    = string
    interface_name = string
  }))
  default = []
}

variable "instance_lifecycle_policy" {
  type = object({
    default_action_on_failure = string
    force_update_on_repair    = string
  })
  default = null
}

variable "all_instances_config" {
  type = object({
    labels   = map(string)
    metadata = map(string)
  })
  default = null
}

variable "instance_flexibility_policy" {
  type = object({
    instance_selections = set(object({
      name          = string
      rank          = number
      machine_types = set(string)
    }))
  })
  default = null
}