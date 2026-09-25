locals {
  autoscaling_scale_in_enabled = var.autoscaling_scale_in_control.fixed_replicas != null || var.autoscaling_scale_in_control.percent_replicas != null
}

resource "google_compute_health_check" "this" {
  project = var.project_id

  name                = "${var.name}-hc"
  check_interval_sec  = var.health_check.check_interval_sec
  timeout_sec         = var.health_check.timeout_sec
  healthy_threshold   = var.health_check.healthy_threshold
  unhealthy_threshold = var.health_check.unhealthy_threshold

  dynamic "http_health_check" {
    for_each = var.health_check.type == "HTTP" ? [1] : []
    content {
      port         = var.health_check.port
      request_path = var.health_check.request_path
    }
  }

  dynamic "https_health_check" {
    for_each = var.health_check.type == "HTTPS" ? [1] : []
    content {
      port         = var.health_check.port
      request_path = var.health_check.request_path
    }
  }

  dynamic "tcp_health_check" {
    for_each = var.health_check.type == "TCP" ? [1] : []
    content {
      port = var.health_check.port
    }
  }

  dynamic "ssl_health_check" {
    for_each = var.health_check.type == "SSL" ? [1] : []
    content {
      port = var.health_check.port
    }
  }

  dynamic "http2_health_check" {
    for_each = var.health_check.type == "HTTP2" ? [1] : []
    content {
      port         = var.health_check.port
      request_path = var.health_check.request_path
    }
  }

  dynamic "grpc_health_check" {
    for_each = var.health_check.type == "GRPC" ? [1] : []
    content {
      port = var.health_check.port
    }
  }
}

resource "google_compute_region_instance_group_manager" "this" {
  project = var.project_id

  name        = "${var.name}-mig"
  description = var.description
  region      = var.region

  base_instance_name = var.name
  target_size        = var.target_size

  distribution_policy_target_shape = var.distribution_policy_target_shape
  list_managed_instances_results   = var.list_managed_instances_results

  wait_for_instances        = var.wait_for_instances
  wait_for_instances_status = var.wait_for_instances_status

  target_pools          = var.target_pools
  target_stopped_size   = var.target_stopped_size
  target_suspended_size = var.target_suspended_size

  distribution_policy_zones = length(var.distribution_zones) > 0 ? var.distribution_zones : null

  dynamic "stateful_disk" {
    for_each = var.stateful_disk != null ? var.stateful_disk : []
    content {
      delete_rule = stateful_disk.value.delete_rule
      device_name = stateful_disk.value.device_name
    }
  }

  dynamic "stateful_external_ip" {
    for_each = length(var.stateful_external_ip) > 0 ? var.stateful_external_ip : []
    content {
      delete_rule    = stateful_external_ip.value.delete_rule
      interface_name = stateful_external_ip.value.interface_name
    }
  }

  dynamic "all_instances_config" {
    for_each = var.all_instances_config != null ? [var.all_instances_config] : []
    content {
      labels   = all_instances_config.value.labels
      metadata = all_instances_config.value.metadata
    }
  }

  dynamic "stateful_internal_ip" {
    for_each = length(var.stateful_internal_ip) > 0 ? var.stateful_internal_ip : []
    content {
      interface_name = stateful_internal_ip.value.interface_name
      delete_rule    = stateful_internal_ip.value.delete_rule
    }
  }

  dynamic "instance_flexibility_policy" {
    for_each = var.instance_flexibility_policy != null ? [var.instance_flexibility_policy] : []
    content {
      dynamic "instance_selections" {
        for_each = instance_flexibility_policy.value.instance_selections
        content {
          name          = instance_selections.value.name
          rank          = instance_selections.value.rank
          machine_types = instance_selections.value.machine_types
        }
      }
    }
  }

  dynamic "instance_lifecycle_policy" {
    for_each = var.instance_lifecycle_policy != null ? [var.instance_lifecycle_policy] : []
    content {
      default_action_on_failure = instance_lifecycle_policy.value.default_action_on_failure
      force_update_on_repair    = instance_lifecycle_policy.value.force_update_on_repair
    }
  }

  version {
    instance_template = var.instance_template
  }

  dynamic "named_port" {
    for_each = var.named_ports
    content {
      name = named_port.value.name
      port = named_port.value.port
    }
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.this.id
    initial_delay_sec = var.health_check_initial_delay_sec
  }

  dynamic "update_policy" {
    for_each = var.update_policy != null ? [var.update_policy] : []
    content {
      type                    = update_policy.value.type
      minimal_action          = update_policy.value.minimal_action
      max_surge_fixed         = update_policy.value.max_surge_percent == null ? update_policy.value.max_surge_fixed : null
      max_surge_percent       = update_policy.value.max_surge_percent
      max_unavailable_fixed   = update_policy.value.max_unavailable_percent == null ? update_policy.value.max_unavailable_fixed : null
      max_unavailable_percent = update_policy.value.max_unavailable_percent
      replacement_method      = update_policy.value.replacement_method
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      target_size, # let the autoscaler own this once enabled
    ]
  }
  depends_on = [google_compute_health_check.this]
}

resource "google_compute_region_autoscaler" "autoscaler" {
  provider = google
  count    = var.autoscaling_enabled ? 1 : 0
  name     = var.autoscaler_name == "" ? "${var.hostname}-autoscaler" : var.autoscaler_name
  project  = var.project_id
  region   = var.region

  target = google_compute_region_instance_group_manager.this.self_link

  autoscaling_policy {
    max_replicas    = var.max_replicas
    min_replicas    = var.min_replicas
    cooldown_period = var.cooldown_period
    mode            = var.autoscaling_mode
    dynamic "scale_in_control" {
      for_each = local.autoscaling_scale_in_enabled ? [var.autoscaling_scale_in_control] : []
      content {
        max_scaled_in_replicas {
          fixed   = lookup(scale_in_control.value, "fixed_replicas", null)
          percent = lookup(scale_in_control.value, "percent_replicas", null)
        }
        time_window_sec = lookup(scale_in_control.value, "time_window_sec", null)
      }
    }
    dynamic "cpu_utilization" {
      for_each = var.autoscaling_cpu
      content {
        target            = lookup(cpu_utilization.value, "target", null)
        predictive_method = lookup(cpu_utilization.value, "predictive_method", null)
      }
    }
    dynamic "metric" {
      for_each = var.autoscaling_metric
      content {
        name   = lookup(metric.value, "name", null)
        target = lookup(metric.value, "target", null)
        type   = lookup(metric.value, "type", null)
      }
    }
    dynamic "load_balancing_utilization" {
      for_each = var.autoscaling_lb
      content {
        target = lookup(load_balancing_utilization.value, "target", null)
      }
    }
    dynamic "scaling_schedules" {
      for_each = var.scaling_schedules
      content {
        disabled              = lookup(scaling_schedules.value, "disabled", null)
        duration_sec          = lookup(scaling_schedules.value, "duration_sec", null)
        min_required_replicas = lookup(scaling_schedules.value, "min_required_replicas", null)
        name                  = lookup(scaling_schedules.value, "name", null)
        schedule              = lookup(scaling_schedules.value, "schedule", null)
        time_zone             = lookup(scaling_schedules.value, "time_zone", null)
      }
    }
  }
}