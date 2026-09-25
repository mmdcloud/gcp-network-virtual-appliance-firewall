variable "hub_name" {
  type        = string
  description = "Name of the Network Connectivity Center hub."
}

variable "hub_description" {
  type        = string
  description = "Description of the hub."
  default     = ""
}

variable "hub_labels" {
  type        = map(string)
  description = "Labels to apply to the hub."
  default     = {}
}

variable "hub_policy_mode" {
  type        = string
  description = "Policy mode for the hub"
  default     = "PRESET"
}

variable "export_psc" {
  type        = bool
  description = "Labels to apply to the hub."
  default     = false
}

# Each spoke supports exactly ONE of the linked_* blocks below (GCP requires
# exactly one link type per spoke). All are optional at the variable level so
# a single spokes list can mix VPC spokes, VPN spokes, interconnect spokes,
# router-appliance spokes, and producer-VPC spokes.
variable "spokes" {
  description = "List of spokes to attach to the hub. Set exactly one linked_* object per spoke."
  type = list(object({
    spoke_name  = string
    location    = string
    description = optional(string)
    labels      = optional(map(string), {})

    # Standard VPC network spoke (this is what Private NAT / Inter-VPC NAT uses)
    linked_vpc_network = optional(object({
      uri                    = string
      exclude_export_ranges  = optional(list(string))
      include_export_ranges  = optional(list(string))
    }))

    # Producer VPC spoke - for Private Services Access peering (e.g. Cloud SQL),
    # NOT related to Private NAT / Inter-VPC NAT.
    linked_producer_vpc_network = optional(object({
      network                = string
      peering                = string
      exclude_export_ranges  = optional(list(string))
      include_export_ranges  = optional(list(string))
    }))

    linked_vpn_tunnels = optional(object({
      uris                        = list(string)
      site_to_site_data_transfer  = bool
      vpc_network                 = optional(string)
      include_import_ranges       = optional(list(string))
    }))

    linked_interconnect_attachments = optional(object({
      uris                        = list(string)
      site_to_site_data_transfer  = bool
      vpc_network                 = optional(string)
      include_import_ranges       = optional(list(string))
    }))

    linked_router_appliance_instances = optional(object({
      instances = list(object({
        virtual_machine = string
        ip_address      = string
      }))
      site_to_site_data_transfer = bool
      vpc_network                = optional(string)
      include_import_ranges      = optional(list(string))
    }))
  }))

  validation {
    condition = alltrue([
      for s in var.spokes : (
        length(compact([
          s.linked_vpc_network != null ? "x" : "",
          s.linked_producer_vpc_network != null ? "x" : "",
          s.linked_vpn_tunnels != null ? "x" : "",
          s.linked_interconnect_attachments != null ? "x" : "",
          s.linked_router_appliance_instances != null ? "x" : "",
        ])) == 1
      )
    ])
    error_message = "Each spoke in var.spokes must set exactly one linked_* object (linked_vpc_network, linked_producer_vpc_network, linked_vpn_tunnels, linked_interconnect_attachments, or linked_router_appliance_instances)."
  }
}