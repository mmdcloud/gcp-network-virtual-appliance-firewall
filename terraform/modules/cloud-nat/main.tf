resource "random_string" "name_suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  # intermediate locals
  default_name = "cloud-nat-${random_string.name_suffix.result}"
  # locals for google_compute_router_nat
  nat_ip_allocate_option = var.type == "PRIVATE" ? null : coalesce(var.nat_ip_allocate_option, "AUTO_ONLY")

  name                   = var.name != "" ? var.name : local.default_name
  router                 = var.create_router ? google_compute_router.router[0].name : var.router
}

resource "google_compute_router" "router" {
  count   = var.create_router ? 1 : 0
  name    = var.router
  project = var.project_id
  region  = var.region
  network = var.network

  dynamic "bgp" {
    for_each = var.router_asn != null ? [{
      asn                = var.router_asn
      keepalive_interval = var.router_keepalive_interval
    }] : []
    content {
      asn                = bgp.value.asn
      keepalive_interval = bgp.value.keepalive_interval
    }
  }
}

resource "google_compute_router_nat" "main" {
  project                             = var.project_id
  region                              = var.region
  name                                = local.name
  router                              = local.router
  nat_ip_allocate_option              = local.nat_ip_allocate_option
  nat_ips                             = var.nat_ips
  type                                = var.type
  drain_nat_ips                       = var.drain_nat_ips
  source_subnetwork_ip_ranges_to_nat  = var.source_subnetwork_ip_ranges_to_nat
  min_ports_per_vm                    = var.min_ports_per_vm
  max_ports_per_vm                    = var.enable_dynamic_port_allocation ? var.max_ports_per_vm : null
  udp_idle_timeout_sec                = var.udp_idle_timeout_sec
  icmp_idle_timeout_sec               = var.icmp_idle_timeout_sec
  tcp_established_idle_timeout_sec    = var.tcp_established_idle_timeout_sec
  tcp_transitory_idle_timeout_sec     = var.tcp_transitory_idle_timeout_sec
  tcp_time_wait_timeout_sec           = var.tcp_time_wait_timeout_sec
  enable_endpoint_independent_mapping = var.enable_endpoint_independent_mapping
  enable_dynamic_port_allocation      = var.enable_dynamic_port_allocation

  dynamic "subnetwork" {
    for_each = var.subnetworks
    content {
      name                     = subnetwork.value.name
      source_ip_ranges_to_nat  = subnetwork.value.source_ip_ranges_to_nat
      secondary_ip_range_names = contains(subnetwork.value.source_ip_ranges_to_nat, "LIST_OF_SECONDARY_IP_RANGES") ? subnetwork.value.secondary_ip_range_names : []
    }
  }

  dynamic "log_config" {
    for_each = var.log_config_enable == true ? [{
      enable = var.log_config_enable
      filter = var.log_config_filter
    }] : []

    content {
      enable = log_config.value.enable
      filter = log_config.value.filter
    }
  }

  dynamic "rules" {
    for_each = var.rules
    content {
      rule_number = rules.value.rule_number
      description = rules.value.description
      match       = rules.value.match
      action {
        source_nat_active_ips    = rules.value.action.source_nat_active_ips
        source_nat_drain_ips     = rules.value.action.source_nat_drain_ips
        source_nat_active_ranges = rules.value.action.source_nat_active_ranges
        source_nat_drain_ranges  = rules.value.action.source_nat_drain_ranges
      }
    }
  }
}