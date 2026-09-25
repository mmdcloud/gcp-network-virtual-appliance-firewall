resource "google_compute_network" "vpc" {
  name                                      = var.vpc_name
  description                               = var.description
  delete_default_routes_on_create           = var.delete_default_routes_on_create
  auto_create_subnetworks                   = var.auto_create_subnetworks
  routing_mode                              = var.routing_mode
  bgp_always_compare_med                    = var.bgp_always_compare_med
  bgp_best_path_selection_mode              = var.bgp_best_path_selection_mode
  bgp_inter_region_cost                     = var.bgp_inter_region_cost
  enable_ula_internal_ipv6                  = var.enable_ula_internal_ipv6
  internal_ipv6_range                       = var.internal_ipv6_range
  network_profile                           = var.network_profile
  mtu                                       = var.mtu
  network_firewall_policy_enforcement_order = var.network_firewall_policy_enforcement_order
}

resource "google_compute_subnetwork" "subnets" {
  count                            = length(var.subnets)
  name                             = var.subnets[count.index].name
  description                      = var.subnets[count.index].description
  ip_cidr_range                    = var.subnets[count.index].ip_cidr_range
  region                           = var.subnets[count.index].region
  network                          = google_compute_network.vpc.id
  private_ip_google_access         = var.subnets[count.index].private_ip_google_access
  purpose                          = var.subnets[count.index].purpose
  role                             = var.subnets[count.index].role
  external_ipv6_prefix             = var.subnets[count.index].external_ipv6_prefix
  ip_collection                    = var.subnets[count.index].ip_collection
  ipv6_access_type                 = var.subnets[count.index].ipv6_access_type
  private_ipv6_google_access       = var.subnets[count.index].private_ipv6_google_access
  stack_type                       = var.subnets[count.index].stack_type
  send_secondary_ip_range_if_empty = var.subnets[count.index].send_secondary_ip_range_if_empty
  reserved_internal_range          = var.subnets[count.index].reserved_internal_range

  dynamic "log_config" {
    for_each = try(var.subnets[count.index].log_config != null ? [var.subnets[count.index].log_config] : [], [])
    content {
      aggregation_interval = log_config.value.aggregation_interval
      filter_expr          = log_config.value.filter_expr
      flow_sampling        = log_config.value.flow_sampling
      metadata             = log_config.value.metadata
      metadata_fields      = log_config.value.metadata_fields
    }
  }

  dynamic "secondary_ip_range" {
    for_each = var.subnets[count.index].secondary_ip_range
    content {
      ip_cidr_range           = secondary_ip_range.value.ip_cidr_range
      range_name              = secondary_ip_range.value.range_name
      reserved_internal_range = secondary_ip_range.value.reserved_internal_range
    }
  }
}

resource "google_compute_firewall" "firewall" {
  count                   = length(var.firewall_data)
  name                    = var.firewall_data[count.index].name
  description             = var.firewall_data[count.index].description
  network                 = google_compute_network.vpc.id
  source_tags             = var.firewall_data[count.index].source_tags
  direction               = var.firewall_data[count.index].direction
  target_tags             = var.firewall_data[count.index].target_tags
  source_ranges           = var.firewall_data[count.index].source_ranges
  destination_ranges      = var.firewall_data[count.index].destination_ranges
  source_service_accounts = var.firewall_data[count.index].source_service_accounts
  target_service_accounts = var.firewall_data[count.index].target_service_accounts
  priority                = var.firewall_data[count.index].priority
  disabled                = var.firewall_data[count.index].disabled

  dynamic "allow" {
    for_each = var.firewall_data[count.index].allow_list
    content {
      protocol = allow.value["protocol"]
      ports    = allow.value["ports"]
    }
  }

  dynamic "deny" {
    for_each = var.firewall_data[count.index].deny_list
    content {
      protocol = deny.value["protocol"]
      ports    = deny.value["ports"]
    }
  }

  dynamic "log_config" {
    for_each = var.firewall_data[count.index].log_config != null ? [var.firewall_data[count.index].log_config] : []
    content {
      metadata = log_config.value.metadata
    }
  }
}