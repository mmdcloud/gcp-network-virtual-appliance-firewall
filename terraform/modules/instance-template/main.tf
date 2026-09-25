resource "random_id" "suffix" {
  byte_length = 4

  keepers = {
    # Force a new suffix (and therefore a new template) whenever
    # anything that meaningfully changes the instance shape changes.
    machine_type = var.machine_type
    source_image = var.source_image
  }
}

resource "google_service_account" "this" {
  count = var.service_account_email == null && var.create_service_account ? 1 : 0

  project      = var.project_id
  account_id   = substr("${var.name_prefix}-sa", 0, 30)
  display_name = "Service account for ${var.name_prefix} instances"
}

resource "google_project_iam_member" "sa_roles" {
  for_each = var.service_account_email == null && var.create_service_account ? toset(var.service_account_roles) : []

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.this[0].email}"
}

locals {
  resolved_service_account_email = coalesce(
    var.service_account_email,
    try(google_service_account.this[0].email, null)
  )

  base_metadata = merge(
    var.metadata,
    var.startup_script != null ? { startup-script = var.startup_script } : {},
    { block-project-ssh-keys = var.block_project_ssh_keys ? "true" : "false" },
    { enable-oslogin = var.enable_os_login ? "TRUE" : "FALSE" },
    { serial-port-enable = var.serial_port_enable ? "TRUE" : "FALSE" },
  )
}

resource "google_compute_instance_template" "this" {
  project     = var.project_id
  name        = "${var.name_prefix}-${random_id.suffix.hex}"
  description = var.description

  machine_type     = var.machine_type
  min_cpu_platform = var.min_cpu_platform
  region           = var.region

  can_ip_forward = false
  tags           = var.network_tags
  labels         = var.labels

  disk {
    boot         = true
    source_image = var.source_image
    disk_size_gb = var.boot_disk_size_gb
    disk_type    = var.boot_disk_type
    auto_delete  = true

    dynamic "disk_encryption_key" {
      for_each = var.boot_disk_kms_key_self_link != null ? [1] : []
      content {
        kms_key_self_link = var.boot_disk_kms_key_self_link
      }
    }
  }

  dynamic "guest_accelerator" {
    for_each = var.guest_accelerator
    content {
      count = guest_accelerator.value.count
      type  = guest_accelerator.value.type
    }
  }

  instance_description       = var.instance_description
  key_revocation_action_type = var.key_revocation_action_type
  resource_policies          = var.resource_policies
  resource_manager_tags      = var.resource_manager_tags

  dynamic "reservation_affinity" {
    for_each = var.reservation_affinity != null ? [var.reservation_affinity] : []
    content {
      type = reservation_affinity.value.type
      dynamic "specific_reservation" {
        for_each = reservation_affinity.value.specific_reservation != null ? [reservation_affinity.value.specific_reservation] : []
        content {
          key    = specific_reservation.value.key
          values = specific_reservation.value.values
        }
      }
    }
  }

  dynamic "network_performance_config" {
    for_each = var.network_performance_config != null ? [var.network_performance_config] : []
    content {
      total_egress_bandwidth_tier = network_performance_config.value.total_egress_bandwidth_tier
    }
  }

  dynamic "disk" {
    for_each = var.additional_disks
    content {
      boot         = false
      device_name  = disk.value.device_name
      disk_size_gb = disk.value.disk_size_gb
      disk_type    = disk.value.disk_type_persistent ? disk.value.disk_type : null
      type         = disk.value.disk_type_persistent ? "PERSISTENT" : "SCRATCH"
      auto_delete  = disk.value.auto_delete
    }
  }

  network_interface {
    network            = var.subnetwork == null ? var.network : null
    subnetwork         = var.subnetwork
    subnetwork_project = var.subnetwork != null ? coalesce(var.subnetwork_project, var.project_id) : null

    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []
      content {
        # Ephemeral public IP.
      }
    }
  }

  metadata = local.base_metadata

  service_account {
    email  = local.resolved_service_account_email
    scopes = var.service_account_scopes
  }

  dynamic "shielded_instance_config" {
    for_each = var.enable_shielded_vm ? [1] : []
    content {
      enable_secure_boot          = var.shielded_secure_boot
      enable_vtpm                 = var.shielded_vtpm
      enable_integrity_monitoring = var.shielded_integrity_monitoring
    }
  }

  dynamic "confidential_instance_config" {
    for_each = var.enable_confidential_compute ? [1] : []
    content {
      enable_confidential_compute = true
    }
  }

  advanced_machine_features {
    enable_nested_virtualization = var.enable_nested_virtualization
    threads_per_core             = var.threads_per_core
  }

  scheduling {
    preemptible                 = var.preemptible
    automatic_restart           = (var.preemptible || var.spot) ? false : var.automatic_restart
    on_host_maintenance         = (var.preemptible || var.spot || var.enable_confidential_compute) ? "TERMINATE" : var.on_host_maintenance
    provisioning_model          = var.spot ? "SPOT" : "STANDARD"
    instance_termination_action = var.spot ? var.spot_instance_termination_action : null
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = !(var.preemptible && var.spot)
      error_message = "Set only one of preemptible or spot, not both."
    }

    precondition {
      condition     = !var.enable_confidential_compute || can(regex("^(n2d|n2|c2d)-", var.machine_type))
      error_message = "Confidential Compute requires an N2D, N2, or C2D machine type."
    }
  }
}