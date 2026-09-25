############################################
# Core
############################################

variable "project_id" {
  description = "GCP project ID where the instance template will be created."
  type        = string
}

variable "region" {
  description = "Region used to derive a default zone/subnetwork if not explicitly set."
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix for the instance template name. A random suffix is appended so templates can be recreated (create_before_destroy) without name collisions -- required for zero-downtime MIG rolling updates."
  type        = string
}

variable "description" {
  description = "Description applied to the instance template."
  type        = string
  default     = "Managed by Terraform."
}

############################################
# Machine configuration
############################################

variable "machine_type" {
  description = "GCE machine type, e.g. e2-standard-4, n2-standard-8."
  type        = string
  default     = "e2-standard-2"
}

variable "min_cpu_platform" {
  description = "Minimum CPU platform. Leave null to let GCP choose."
  type        = string
  default     = null
}

############################################
# Boot disk / image
############################################

variable "source_image" {
  description = "Source image family or image, e.g. projects/debian-cloud/global/images/family/debian-12."
  type        = string
  default     = "projects/debian-cloud/global/images/family/debian-12"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB."
  type        = number
  default     = 50
}

variable "boot_disk_type" {
  description = "Boot disk type: pd-ssd, pd-balanced, pd-standard, pd-extreme, hyperdisk-balanced."
  type        = string
  default     = "pd-balanced"

  validation {
    condition     = contains(["pd-ssd", "pd-balanced", "pd-standard", "pd-extreme", "hyperdisk-balanced"], var.boot_disk_type)
    error_message = "boot_disk_type must be one of: pd-ssd, pd-balanced, pd-standard, pd-extreme, hyperdisk-balanced."
  }
}

variable "boot_disk_kms_key_self_link" {
  description = "Optional CMEK key self-link to encrypt the boot disk. Leave null for Google-managed encryption."
  type        = string
  default     = null
}

variable "additional_disks" {
  description = "Additional (non-boot) disks to attach."
  type = list(object({
    device_name          = string
    disk_size_gb         = number
    disk_type            = optional(string, "pd-balanced")
    auto_delete          = optional(bool, true)
    disk_type_persistent = optional(bool, true) # true = persistent disk, false = local-ssd/scratch
  }))
  default = []
}

############################################
# Networking
############################################

variable "network" {
  description = "VPC network self-link or name. Ignored if subnetwork is set and network is derivable from it."
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subnetwork self-link or name. Recommended over network for VPCs with custom subnets."
  type        = string
  default     = null
}

variable "subnetwork_project" {
  description = "Project that owns the subnetwork, if different from project_id (Shared VPC)."
  type        = string
  default     = null
}

variable "assign_public_ip" {
  description = "Whether to assign an ephemeral public IP via access_config. Keep false for private/production workloads behind a NAT or LB."
  type        = bool
  default     = false
}

variable "network_tags" {
  description = "Network tags for firewall targeting."
  type        = list(string)
  default     = []
}

variable "enable_nested_virtualization" {
  description = "Enable nested virtualization (advanced_machine_features)."
  type        = bool
  default     = false
}

variable "threads_per_core" {
  description = "Threads per core override, for SMT control. Leave null for default."
  type        = number
  default     = null
}

############################################
# Service account / IAM
############################################

variable "service_account_email" {
  description = "Email of the service account attached to instances. If null, a dedicated service account is created by this module (recommended over the default Compute Engine SA)."
  type        = string
  default     = null
}

variable "create_service_account" {
  description = "If true and service_account_email is null, create a dedicated least-privilege service account for this template."
  type        = bool
  default     = true
}

variable "service_account_scopes" {
  description = "OAuth scopes for the attached service account. Prefer IAM roles on the SA over broad scopes; cloud-platform is the recommended scope when using fine-grained IAM."
  type        = list(string)
  default     = ["https://www.googleapis.com/auth/cloud-platform"]
}

variable "service_account_roles" {
  description = "IAM roles to grant the dedicated service account when create_service_account is true, e.g. [\"roles/logging.logWriter\", \"roles/monitoring.metricWriter\"]."
  type        = list(string)
  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
  ]
}

############################################
# Metadata / startup
############################################

variable "metadata" {
  description = "Arbitrary instance metadata key/value pairs."
  type        = map(string)
  default     = {}
}

variable "startup_script" {
  description = "Startup script content (bash). Leave null to omit."
  type        = string
  default     = null
}

variable "block_project_ssh_keys" {
  description = "If true, blocks project-wide SSH keys, requiring per-instance keys via metadata."
  type        = bool
  default     = false
}

variable "enable_os_login" {
  description = "Enable OS Login for centralized SSH access control via IAM (recommended for production)."
  type        = bool
  default     = true
}

variable "serial_port_enable" {
  description = "Enable serial port access. Keep false in production unless actively debugging."
  type        = bool
  default     = false
}

############################################
# Shielded VM / Confidential Compute
############################################

variable "enable_shielded_vm" {
  description = "Enable Shielded VM features (secure boot, vTPM, integrity monitoring). Strongly recommended for production."
  type        = bool
  default     = true
}

variable "shielded_secure_boot" {
  type    = bool
  default = true
}

variable "shielded_vtpm" {
  type    = bool
  default = true
}

variable "shielded_integrity_monitoring" {
  type    = bool
  default = true
}

variable "enable_confidential_compute" {
  description = "Enable Confidential VM. Requires a compatible machine_type (N2D/C2D/N2 confidential-capable) and on_host_maintenance = TERMINATE."
  type        = bool
  default     = false
}

############################################
# Scheduling
############################################

variable "preemptible" {
  description = "Use a legacy preemptible instance (max 24h, low cost)."
  type        = bool
  default     = false
}

variable "spot" {
  description = "Use a Spot VM (successor to preemptible, configurable eviction policy)."
  type        = bool
  default     = false
}

variable "spot_instance_termination_action" {
  description = "Action on Spot VM preemption: STOP or DELETE."
  type        = string
  default     = "STOP"

  validation {
    condition     = contains(["STOP", "DELETE"], var.spot_instance_termination_action)
    error_message = "spot_instance_termination_action must be STOP or DELETE."
  }
}

variable "automatic_restart" {
  description = "Restart instance on host failure. Must be false when preemptible or spot is true."
  type        = bool
  default     = true
}

variable "on_host_maintenance" {
  description = "MIGRATE or TERMINATE. Must be TERMINATE for preemptible/spot/GPU/confidential-compute instances."
  type        = string
  default     = "MIGRATE"

  validation {
    condition     = contains(["MIGRATE", "TERMINATE"], var.on_host_maintenance)
    error_message = "on_host_maintenance must be MIGRATE or TERMINATE."
  }
}

############################################
# Labels
############################################

variable "labels" {
  description = "Labels applied to the instance template and resulting instances."
  type        = map(string)
  default     = {}
}

variable "guest_accelerator" {
  description = "Additional (non-boot) disks to attach."
  type = list(object({
    count = number
    type  = string
  }))
  default = []
}

variable "reservation_affinity" {
  description = "Additional (non-boot) disks to attach."
  type = object({
    type = string
    specific_reservation = object({
      key    = string
      values = list(string)
    })
  })
  default = null
}

variable "network_performance_config" {
  description = "Additional (non-boot) disks to attach."
  type = object({
    total_egress_bandwidth_tier = string
  })
  default = null
}

variable "instance_description" {
  type    = string
  default = ""
}
variable "key_revocation_action_type" {
  type    = string
  default = ""
}
variable "resource_policies" {
  type    = list(string)
  default = []
}
variable "resource_manager_tags" {
  type    = map(string)
  default = {}
}
