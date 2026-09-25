variable "project_id" {
  description = "Project in which to create the load balancer resources."
  type        = string
}

variable "name" {
  description = "Base name used to prefix all resources created by this module."
  type        = string
}

############################################
# EXTERNAL vs INTERNAL
############################################
variable "load_balancer_type" {
  description = "EXTERNAL creates a global external HTTP(S) LB. INTERNAL creates a regional internal HTTP(S) LB."
  type        = string
  default     = "EXTERNAL"

  validation {
    condition     = contains(["EXTERNAL", "INTERNAL"], var.load_balancer_type)
    error_message = "load_balancer_type must be either \"EXTERNAL\" or \"INTERNAL\"."
  }
}

variable "region" {
  description = "Region for regional resources. Required when load_balancer_type = INTERNAL."
  type        = string
  default     = null
}

variable "network" {
  description = "VPC network (self link or name) the internal LB attaches to. Required when load_balancer_type = INTERNAL."
  type        = string
  default     = null
}

variable "subnetwork" {
  description = "Subnetwork (self link or name) used for the internal forwarding rule and internal static address. Required when load_balancer_type = INTERNAL."
  type        = string
  default     = null
}

variable "allow_global_access" {
  description = "Allow clients from any region to reach an INTERNAL load balancer's forwarding rule. Ignored for EXTERNAL."
  type        = bool
  default     = false
}

variable "create_proxy_only_subnet" {
  description = "Whether to create the regional proxy-only subnet (purpose = REGIONAL_MANAGED_PROXY) required by INTERNAL L7 LBs. Set to false if one already exists in the network/region."
  type        = bool
  default     = false
}

variable "proxy_only_subnet_cidr" {
  description = "CIDR range for the proxy-only subnet, when create_proxy_only_subnet = true."
  type        = string
  default     = null
}

############################################
# Static IP
############################################
variable "create_static_ip" {
  description = "Whether to reserve a static IP for the load balancer. If false, var.reserved_ip_address is used instead."
  type        = bool
  default     = true
}

variable "reserved_ip_address" {
  description = "A pre-existing IP address to use when create_static_ip = false."
  type        = string
  default     = null
}

variable "enable_ipv6" {
  description = "Reserve and serve traffic on an IPv6 address in addition to IPv4. EXTERNAL only."
  type        = bool
  default     = false
}

############################################
# Backends
############################################
variable "backends" {
  description = "Map of backend services to create, keyed by an arbitrary short name."
  type = map(object({
    description         = optional(string, "")
    protocol            = string
    port_name           = optional(string, "http")
    timeout_sec         = optional(number, 30)
    is_default          = optional(bool, false)
    enable_cdn          = optional(bool, false)
    log_sample_rate     = optional(number, 1.0)
    host_patterns       = optional(list(string), [])
    path_patterns       = optional(list(string), [])
    health_check_id     = optional(string)
    manage_health_check = optional(bool, true)
    is_serverless_neg   = optional(bool, false)

    iap_config = optional(list(object({
      enabled              = bool
      oauth2_client_id     = optional(string)
      oauth2_client_secret = optional(string)
    })), [])

    groups = list(object({
      group                        = string
      balancing_mode               = optional(string, "UTILIZATION")
      capacity_scaler              = optional(number, 1.0)
      max_connections              = optional(number, null)
      max_connections_per_endpoint = optional(number, null)
      max_connections_per_instance = optional(number, null)
      max_rate                     = optional(number, null)
      max_rate_per_endpoint        = optional(number, null)
      max_rate_per_instance        = optional(number, null)
      preference                   = optional(string, null)
      max_utilization              = optional(number, 0.8)
    }))

    health_check = optional(object({
      check_interval_sec  = optional(number, 10)
      timeout_sec         = optional(number, 5)
      healthy_threshold   = optional(number, 2)
      unhealthy_threshold = optional(number, 2)
      port                = optional(number, 80)
      request_path        = optional(string, "/")
    }), {})
  }))

  default = {}

  # validation {
  #   condition     = length([for k, v in var.backends : k if v.is_default]) == 1
  #   error_message = "Exactly one backend in var.backends must have is_default = true."
  # }
}

variable "backend_buckets" {
  description = "Optional GCS-backed backend buckets (e.g. static-site origins), keyed the same way as var.backends."
  type = map(object({
    bucket_name   = string
    description   = optional(string, "")
    is_default    = optional(bool, false)
    enable_cdn    = optional(bool, true)
    host_patterns = optional(list(string), [])
    path_patterns = optional(list(string), [])
    cdn_policy = optional(object({
      cache_mode        = optional(string, "CACHE_ALL_STATIC")
      default_ttl       = optional(number, 3600)
      client_ttl        = optional(number, 3600)
      max_ttl           = optional(number, 86400)
      negative_caching  = optional(bool, true)
      serve_while_stale = optional(number, 86400)
    }), {})
  }))
  default = {}
}

############################################
# Listeners / SSL
############################################
variable "enable_http" {
  description = "Create a port-80 listener (either serving directly or redirecting to HTTPS, per var.https_redirect)."
  type        = bool
  default     = true
}

variable "enable_ssl" {
  description = "Create a port-443 (HTTPS) listener."
  type        = bool
  default     = false
}

variable "https_redirect" {
  description = "When enable_ssl = true, redirect all port-80 traffic to HTTPS instead of serving it directly."
  type        = bool
  default     = true
}

variable "managed_ssl_certificate" {
  description = "Provision a Google-managed SSL certificate for var.domains. EXTERNAL only — set false for INTERNAL and supply var.ssl_certificate_ids instead."
  type        = bool
  default     = true
}

variable "domains" {
  description = "Domains covered by the Google-managed SSL certificate, when managed_ssl_certificate = true."
  type        = list(string)
  default     = []
}

variable "ssl_certificate_ids" {
  description = "Pre-existing SSL certificate resource ids to attach to the HTTPS proxy, used when managed_ssl_certificate = false (required for INTERNAL)."
  type        = list(string)
  default     = []
}

variable "ssl_policy_profile" {
  description = "SSL policy profile: COMPATIBLE, MODERN, RESTRICTED, or CUSTOM."
  type        = string
  default     = "MODERN"
}

variable "ssl_policy_min_tls_version" {
  description = "Minimum TLS version for the SSL policy."
  type        = string
  default     = "TLS_1_2"
}

############################################
# Cloud Armor (EXTERNAL only)
############################################
variable "enable_cloud_armor" {
  description = "Attach a Cloud Armor security policy to each backend service. EXTERNAL only."
  type        = bool
  default     = false
}

variable "cloud_armor_default_action" {
  description = "Default action for the Cloud Armor policy's catch-all rule (e.g. \"allow\" or \"deny(403)\")."
  type        = string
  default     = "allow"
}

variable "cloud_armor_allowlist_ip_ranges" {
  description = "IP ranges to explicitly allow, evaluated before deny/WAF rules."
  type        = list(string)
  default     = []
}

variable "cloud_armor_denylist_ip_ranges" {
  description = "IP ranges to explicitly deny."
  type        = list(string)
  default     = []
}

variable "cloud_armor_preconfigured_rules" {
  description = "List of Cloud Armor preconfigured WAF expression names (e.g. \"sqli-v33-stable\") to enable as deny rules."
  type        = list(string)
  default     = []
}

variable "cloud_armor_rate_limit_threshold_count" {
  description = "Request count threshold per interval before rate limiting kicks in."
  type        = number
  default     = 100
}

variable "cloud_armor_rate_limit_interval_sec" {
  description = "Interval, in seconds, over which the rate limit threshold is measured."
  type        = number
  default     = 60
}

variable "cloud_armor_rate_limit_ban_duration_sec" {
  description = "How long, in seconds, an offending client IP is banned once it exceeds the ban threshold."
  type        = number
  default     = 300
}

############################################
# Logging / misc
############################################
variable "enable_logging" {
  description = "Enable backend service access logging."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels applied to forwarding rules."
  type        = map(string)
  default     = {}
}
