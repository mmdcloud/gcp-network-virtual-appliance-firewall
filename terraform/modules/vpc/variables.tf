variable "vpc_name" {
  description = "The name of the VPC network."
  type        = string
}

variable "description" {
  description = "An optional description of the VPC network."
  type        = string
  default     = null
}

variable "delete_default_routes_on_create" {
  description = "If true, default routes (0.0.0.0/0) will be deleted immediately after the network is created."
  type        = bool
  default     = false
}

variable "auto_create_subnetworks" {
  description = "When true, the network is created in 'auto subnet mode', automatically creating a subnet in each region. When false, the network is created in 'custom subnet mode', allowing you to explicitly define subnets."
  type        = bool
  default     = false
}

variable "routing_mode" {
  description = "The network-wide routing mode to use. Accepted values are 'GLOBAL' or 'REGIONAL'."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["GLOBAL", "REGIONAL"], var.routing_mode)
    error_message = "routing_mode must be either 'GLOBAL' or 'REGIONAL'."
  }
}

variable "bgp_always_compare_med" {
  description = "Whether to enable comparing MED across routes with different Neighbor ASNs when using the STANDARD BGP best path selection algorithm."
  type        = bool
  default     = null
}

variable "bgp_best_path_selection_mode" {
  description = "The BGP best path selection algorithm to be employed. Accepted values are 'LEGACY' or 'STANDARD'."
  type        = string
  default     = null
}

variable "bgp_inter_region_cost" {
  description = "Choice of the behavior of inter-region cost and MED in the BGP best path selection algorithm. Accepted values are 'DEFAULT' or 'ADD_COST_TO_MED'."
  type        = string
  default     = null
}

variable "delete_bgp_always_compare_med" {
  description = "Whether to delete the 'bgp_always_compare_med' setting from the network."
  type        = bool
  default     = null
}

variable "enable_ula_internal_ipv6" {
  description = "Enable ULA internal ipv6 on this network. Enabling this feature will assign a /48 from google defined ULA prefix fd20::/20."
  type        = bool
  default     = false
}

variable "internal_ipv6_range" {
  description = "When enabling ula internal ipv6, caller optionally can specify the /48 range they want from the google defined ULA prefix fd20::/20."
  type        = string
  default     = null
}

variable "network_profile" {
  description = "A full or partial URL of the network profile to apply to this network."
  type        = string
  default     = null
}

variable "mtu" {
  description = "Maximum Transmission Unit in bytes. The minimum value for this field is 1300 and the maximum value is 8896."
  type        = number
  default     = null
}

variable "network_firewall_policy_enforcement_order" {
  description = "Set the order that Firewall Rules and Firewall Policies are evaluated. Accepted values are 'BEFORE_CLASSIC_FIREWALL' or 'AFTER_CLASSIC_FIREWALL'."
  type        = string
  default     = null
}

variable "subnets" {
  description = "A list of subnets to create within the VPC network."
  type = list(object({
    name                              = string
    description                       = optional(string)
    ip_cidr_range                     = string
    region                            = string
    private_ip_google_access          = optional(bool, false)
    purpose                           = optional(string)
    role                              = optional(string)
    allow_subnet_cidr_routes_overlap  = optional(bool)
    external_ipv6_prefix              = optional(string)
    ip_collection                     = optional(string)
    ipv6_access_type                  = optional(string)
    private_ipv6_google_access        = optional(string)
    stack_type                        = optional(string)
    send_secondary_ip_range_if_empty  = optional(bool)
    reserved_internal_range           = optional(string)
    resolve_subnet_mask               = optional(bool)

    log_config = optional(object({
      aggregation_interval = optional(string)
      filter_expr          = optional(string)
      flow_sampling        = optional(number)
      metadata              = optional(string)
      metadata_fields       = optional(list(string))
    }))

    secondary_ip_range = optional(list(object({
      ip_cidr_range           = string
      range_name               = string
      reserved_internal_range = optional(string)
    })), [])
  }))
  default = []
}

variable "firewall_data" {
  description = "A list of firewall rules to create within the VPC network."
  type = list(object({
    name                     = string
    description              = optional(string)
    direction                = optional(string, "INGRESS")
    source_tags              = optional(list(string))
    target_tags              = optional(list(string))
    source_ranges            = optional(list(string))
    destination_ranges       = optional(list(string))
    source_service_accounts  = optional(list(string))
    target_service_accounts  = optional(list(string))
    priority                 = optional(number, 1000)
    disabled                 = optional(bool, false)

    allow_list = optional(list(object({
      protocol = string
      ports    = optional(list(string))
    })), [])

    deny_list = optional(list(object({
      protocol = string
      ports    = optional(list(string))
    })), [])

    log_config = optional(object({
      metadata = string
    }))
  }))
  default = []
}