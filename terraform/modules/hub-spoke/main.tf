resource "google_network_connectivity_hub" "hub" {
  name        = var.hub_name
  description = var.hub_description
  export_psc  = var.export_psc
  policy_mode = var.hub_policy_mode
  labels      = merge({ name = var.hub_name }, var.hub_labels)
}

resource "google_network_connectivity_spoke" "spokes" {
  for_each = { for s in var.spokes : s.spoke_name => s }

  name        = each.value.spoke_name
  location    = each.value.location
  hub         = google_network_connectivity_hub.hub.id
  description = try(each.value.description, null)
  labels      = try(each.value.labels, null)

  dynamic "linked_vpc_network" {
    for_each = each.value.linked_vpc_network != null ? [each.value.linked_vpc_network] : []
    content {
      uri                   = linked_vpc_network.value.uri
      exclude_export_ranges = try(linked_vpc_network.value.exclude_export_ranges, null)
      include_export_ranges = try(linked_vpc_network.value.include_export_ranges, null)
    }
  }

  dynamic "linked_producer_vpc_network" {
    for_each = each.value.linked_producer_vpc_network != null ? [each.value.linked_producer_vpc_network] : []
    content {
      network               = linked_producer_vpc_network.value.network
      peering               = linked_producer_vpc_network.value.peering
      exclude_export_ranges = try(linked_producer_vpc_network.value.exclude_export_ranges, null)
      include_export_ranges = try(linked_producer_vpc_network.value.include_export_ranges, null)
    }
  }

  dynamic "linked_vpn_tunnels" {
    for_each = each.value.linked_vpn_tunnels != null ? [each.value.linked_vpn_tunnels] : []
    content {
      uris                       = linked_vpn_tunnels.value.uris
      site_to_site_data_transfer = linked_vpn_tunnels.value.site_to_site_data_transfer
      include_import_ranges      = try(linked_vpn_tunnels.value.include_import_ranges, null)
    }
  }

  dynamic "linked_interconnect_attachments" {
    for_each = each.value.linked_interconnect_attachments != null ? [each.value.linked_interconnect_attachments] : []
    content {
      uris                       = linked_interconnect_attachments.value.uris
      site_to_site_data_transfer = linked_interconnect_attachments.value.site_to_site_data_transfer
      include_import_ranges      = try(linked_interconnect_attachments.value.include_import_ranges, null)
    }
  }

  dynamic "linked_router_appliance_instances" {
    for_each = each.value.linked_router_appliance_instances != null ? [each.value.linked_router_appliance_instances] : []
    content {
      dynamic "instances" {
        for_each = linked_router_appliance_instances.value.instances
        content {
          virtual_machine = instances.value.virtual_machine
          ip_address      = instances.value.ip_address
        }
      }
      site_to_site_data_transfer = linked_router_appliance_instances.value.site_to_site_data_transfer
      include_import_ranges      = try(linked_router_appliance_instances.value.include_import_ranges, null)
    }
  }
}