locals {
  is_external = var.load_balancer_type == "EXTERNAL"
  is_internal = var.load_balancer_type == "INTERNAL"
}

############################################
# Guardrails for INTERNAL-only constraints
# (Terraform 1.9+ `check` blocks can be evaluated at plan time)
############################################
check "internal_lb_requires_network_context" {
  assert {
    condition     = local.is_external || (var.region != null && var.network != null && var.subnetwork != null)
    error_message = "load_balancer_type = INTERNAL requires var.region, var.network, and var.subnetwork to be set."
  }
}

check "internal_lb_no_cloud_armor" {
  assert {
    condition     = local.is_external || !var.enable_cloud_armor
    error_message = "Cloud Armor is not supported by this module for INTERNAL (regional) load balancers. Set enable_cloud_armor = false."
  }
}

check "internal_lb_no_ipv6" {
  assert {
    condition     = local.is_external || !var.enable_ipv6
    error_message = "enable_ipv6 is only supported for load_balancer_type = EXTERNAL."
  }
}

check "internal_lb_no_managed_cert" {
  assert {
    condition     = local.is_external || !var.managed_ssl_certificate
    error_message = "Google-managed SSL certificates are only supported for EXTERNAL. For INTERNAL, pre-create google_compute_region_ssl_certificate resources and pass their ids via var.ssl_certificate_ids."
  }
}

check "internal_lb_no_cdn" {
  assert {
    condition     = local.is_external || alltrue([for k, v in var.backends : !v.enable_cdn])
    error_message = "Cloud CDN is not supported for INTERNAL (regional) load balancers. Set enable_cdn = false on every backend."
  }
}

############################################
# Static IP(s)
############################################
resource "google_compute_global_address" "ipv4" {
  count = local.is_external && var.create_static_ip ? 1 : 0

  project      = var.project_id
  name         = "${var.name}-ipv4"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"
}

resource "google_compute_global_address" "ipv6" {
  count = local.is_external && var.create_static_ip && var.enable_ipv6 ? 1 : 0

  project      = var.project_id
  name         = "${var.name}-ipv6"
  ip_version   = "IPV6"
  address_type = "EXTERNAL"
}

resource "google_compute_address" "internal_ipv4" {
  count = local.is_internal && var.create_static_ip ? 1 : 0

  project      = var.project_id
  name         = "${var.name}-ipv4"
  region       = var.region
  subnetwork   = var.subnetwork
  address_type = "INTERNAL"
  purpose      = "SHARED_LOADBALANCER_VIP"
}

locals {
  lb_ipv4_address = local.is_external ? (
    var.create_static_ip ? google_compute_global_address.ipv4[0].address : var.reserved_ip_address
    ) : (
    var.create_static_ip ? google_compute_address.internal_ipv4[0].address : var.reserved_ip_address
  )
}

############################################
# Proxy-only subnet (required once per region/network for INTERNAL L7 LBs)
############################################
resource "google_compute_subnetwork" "proxy_only" {
  count = local.is_internal && var.create_proxy_only_subnet ? 1 : 0

  project       = var.project_id
  name          = "${var.name}-proxy-only"
  region        = var.region
  network       = var.network
  ip_cidr_range = var.proxy_only_subnet_cidr
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

############################################
# Per-backend health checks
############################################
resource "google_compute_health_check" "this" {
  for_each = local.is_external ? {
    for k, v in var.backends : k => v if v.manage_health_check && !v.is_serverless_neg
  } : {}

  project             = var.project_id
  name                = "${var.name}-${each.key}-hc"
  check_interval_sec  = each.value.health_check.check_interval_sec
  timeout_sec         = each.value.health_check.timeout_sec
  healthy_threshold   = each.value.health_check.healthy_threshold
  unhealthy_threshold = each.value.health_check.unhealthy_threshold

  dynamic "http_health_check" {
    for_each = contains(["HTTPS", "HTTP2"], each.value.protocol) ? [] : [1]
    content {
      port         = each.value.health_check.port
      request_path = each.value.health_check.request_path
    }
  }

  dynamic "https_health_check" {
    for_each = contains(["HTTPS", "HTTP2"], each.value.protocol) ? [1] : []
    content {
      port         = each.value.health_check.port
      request_path = each.value.health_check.request_path
    }
  }
}

resource "google_compute_region_health_check" "this" {
  for_each = local.is_internal ? {
    for k, v in var.backends : k => v if v.manage_health_check && !v.is_serverless_neg
  } : {}

  project             = var.project_id
  region              = var.region
  name                = "${var.name}-${each.key}-hc"
  check_interval_sec  = each.value.health_check.check_interval_sec
  timeout_sec         = each.value.health_check.timeout_sec
  healthy_threshold   = each.value.health_check.healthy_threshold
  unhealthy_threshold = each.value.health_check.unhealthy_threshold

  dynamic "http_health_check" {
    for_each = contains(["HTTPS", "HTTP2"], each.value.protocol) ? [] : [1]
    content {
      port         = each.value.health_check.port
      request_path = each.value.health_check.request_path
    }
  }

  dynamic "https_health_check" {
    for_each = contains(["HTTPS", "HTTP2"], each.value.protocol) ? [1] : []
    content {
      port         = each.value.health_check.port
      request_path = each.value.health_check.request_path
    }
  }

}

locals {
  health_check_ids = {
    for k, v in var.backends :
    k => coalesce(
      v.health_check_id,
      try(google_compute_health_check.this[k].id, null),
      try(google_compute_region_health_check.this[k].id, null)
    )
    if !v.is_serverless_neg
  }
}

############################################
# Cloud Armor security policy (EXTERNAL only)
############################################
resource "google_compute_security_policy" "this" {
  count = local.is_external && var.enable_cloud_armor ? 1 : 0

  project     = var.project_id
  name        = "${var.name}-armor-policy"
  description = "Cloud Armor policy for ${var.name}: WAF preconfigured rules, rate limiting, allow/deny lists."

  rule {
    action      = var.cloud_armor_default_action
    priority    = 2147483647
    description = "Default rule"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  dynamic "rule" {
    for_each = length(var.cloud_armor_allowlist_ip_ranges) > 0 ? [1] : []
    content {
      action      = "allow"
      priority    = 1000
      description = "Explicit allowlist"
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = var.cloud_armor_allowlist_ip_ranges
        }
      }
    }
  }

  dynamic "rule" {
    for_each = length(var.cloud_armor_denylist_ip_ranges) > 0 ? [1] : []
    content {
      action      = "deny(403)"
      priority    = 1100
      description = "Explicit denylist"
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = var.cloud_armor_denylist_ip_ranges
        }
      }
    }
  }

  dynamic "rule" {
    for_each = { for idx, rule_id in var.cloud_armor_preconfigured_rules : idx => rule_id }
    content {
      action      = "deny(403)"
      priority    = 1200 + tonumber(rule.key)
      description = "Preconfigured WAF rule: ${rule.value}"
      match {
        expr {
          expression = "evaluatePreconfiguredExpr('${rule.value}')"
        }
      }
    }
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }

  rule {
    action      = "rate_based_ban"
    priority    = 2000
    description = "Rate limit per client IP; ban offenders that exceed 5x the threshold"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.cloud_armor_rate_limit_threshold_count
        interval_sec = var.cloud_armor_rate_limit_interval_sec
      }
      ban_duration_sec = var.cloud_armor_rate_limit_ban_duration_sec
      ban_threshold {
        count        = var.cloud_armor_rate_limit_threshold_count * 5
        interval_sec = var.cloud_armor_rate_limit_interval_sec
      }
    }
  }
}

############################################
# Backend services
############################################
resource "google_compute_backend_bucket" "this" {
  for_each = var.backend_buckets

  project     = var.project_id
  name        = "${var.name}-${each.key}-backend-bucket"
  description = each.value.description
  bucket_name = each.value.bucket_name
  enable_cdn  = each.value.enable_cdn

  dynamic "cdn_policy" {
    for_each = each.value.enable_cdn ? [1] : []
    content {
      cache_mode        = each.value.cdn_policy.cache_mode
      default_ttl       = each.value.cdn_policy.default_ttl
      client_ttl        = each.value.cdn_policy.client_ttl
      max_ttl           = each.value.cdn_policy.max_ttl
      negative_caching  = each.value.cdn_policy.negative_caching
      serve_while_stale = each.value.cdn_policy.serve_while_stale
    }
  }
}

resource "google_compute_backend_service" "serverless" {
  for_each = local.is_external ? { for k, v in var.backends : k => v if v.is_serverless_neg } : {}

  project     = var.project_id
  name        = "${var.name}-${each.key}-backend"
  description = each.value.description
  protocol    = each.value.protocol
  port_name   = each.value.port_name
  timeout_sec = each.value.timeout_sec

  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = var.enable_cloud_armor ? google_compute_security_policy.this[0].id : null

  enable_cdn = each.value.enable_cdn

  dynamic "iap" {
    for_each = length(each.value.iap_config) > 0 ? each.value.iap_config : []
    content {
      enabled              = iap.value.enabled
      oauth2_client_id     = iap.value.oauth2_client_id
      oauth2_client_secret = iap.value.oauth2_client_secret
    }
  }

  dynamic "cdn_policy" {
    for_each = each.value.enable_cdn ? [1] : []
    content {
      cache_mode        = "CACHE_ALL_STATIC"
      default_ttl       = 3600
      client_ttl        = 3600
      max_ttl           = 86400
      negative_caching  = true
      serve_while_stale = 86400
    }
  }

  dynamic "backend" {
    for_each = each.value.groups
    content {
      group                        = backend.value.group
      balancing_mode               = backend.value.balancing_mode
      capacity_scaler              = backend.value.capacity_scaler
      max_connections              = backend.value.max_connections
      max_connections_per_endpoint = backend.value.max_connections_per_endpoint
      max_connections_per_instance = backend.value.max_connections_per_instance
      max_rate                     = backend.value.max_rate
      max_rate_per_endpoint        = backend.value.max_rate_per_endpoint
      max_rate_per_instance        = backend.value.max_rate_per_instance
      preference                   = backend.value.preference
      max_utilization              = backend.value.balancing_mode == "UTILIZATION" ? backend.value.max_utilization : null
    }
  }

  dynamic "log_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable      = true
      sample_rate = each.value.log_sample_rate
    }
  }
  # NOTE: health_checks intentionally omitted — not allowed for Serverless NEG backends
}


resource "google_compute_backend_service" "this" {
  for_each = local.is_external ? { for k, v in var.backends : k => v if !v.is_serverless_neg } : {}

  project     = var.project_id
  name        = "${var.name}-${each.key}-backend"
  description = each.value.description
  protocol    = each.value.protocol
  port_name   = each.value.port_name
  timeout_sec = each.value.timeout_sec

  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [local.health_check_ids[each.key]]
  security_policy       = var.enable_cloud_armor ? google_compute_security_policy.this[0].id : null

  enable_cdn = each.value.enable_cdn

  dynamic "iap" {
    for_each = length(each.value.iap_config) > 0 ? each.value.iap_config : []
    content {
      enabled              = iap.value.enabled
      oauth2_client_id     = iap.value.oauth2_client_id
      oauth2_client_secret = iap.value.oauth2_client_secret
    }
  }

  dynamic "cdn_policy" {
    for_each = each.value.enable_cdn ? [1] : []
    content {
      cache_mode        = "CACHE_ALL_STATIC"
      default_ttl       = 3600
      client_ttl        = 3600
      max_ttl           = 86400
      negative_caching  = true
      serve_while_stale = 86400
    }
  }

  dynamic "backend" {
    for_each = each.value.groups
    content {
      group                        = backend.value.group
      balancing_mode               = backend.value.balancing_mode
      capacity_scaler              = backend.value.capacity_scaler
      max_connections              = backend.value.max_connections
      max_connections_per_endpoint = backend.value.max_connections_per_endpoint
      max_connections_per_instance = backend.value.max_connections_per_instance
      max_rate                     = backend.value.max_rate
      max_rate_per_endpoint        = backend.value.max_rate_per_endpoint
      max_rate_per_instance        = backend.value.max_rate_per_instance
      preference                   = backend.value.preference
      max_utilization              = backend.value.balancing_mode == "UTILIZATION" ? backend.value.max_utilization : null
    }
  }

  dynamic "log_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable      = true
      sample_rate = each.value.log_sample_rate
    }
  }
}

# Regional backend service for INTERNAL_MANAGED (internal HTTP(S) LB).
# Note: enable_cdn / cdn_policy / security_policy are deliberately omitted —
# neither Cloud CDN nor this module's Cloud Armor policy applies to internal LBs.
resource "google_compute_region_backend_service" "serverless" {
  for_each = local.is_internal ? { for k, v in var.backends : k => v if v.is_serverless_neg } : {}

  project     = var.project_id
  region      = var.region
  name        = "${var.name}-${each.key}-backend"
  description = each.value.description
  protocol    = each.value.protocol
  port_name   = each.value.port_name
  timeout_sec = each.value.timeout_sec

  load_balancing_scheme = "INTERNAL_MANAGED"

  dynamic "iap" {
    for_each = length(each.value.iap_config) > 0 ? each.value.iap_config : []
    content {
      enabled              = iap.value.enabled
      oauth2_client_id     = iap.value.oauth2_client_id
      oauth2_client_secret = iap.value.oauth2_client_secret
    }
  }

  dynamic "backend" {
    for_each = each.value.groups
    content {
      group                        = backend.value.group
      balancing_mode               = backend.value.balancing_mode
      capacity_scaler              = backend.value.capacity_scaler
      max_connections              = backend.value.max_connections
      max_connections_per_endpoint = backend.value.max_connections_per_endpoint
      max_connections_per_instance = backend.value.max_connections_per_instance
      max_rate                     = backend.value.max_rate
      max_rate_per_endpoint        = backend.value.max_rate_per_endpoint
      max_rate_per_instance        = backend.value.max_rate_per_instance
      max_utilization              = backend.value.balancing_mode == "UTILIZATION" ? backend.value.max_utilization : null
    }
  }

  dynamic "log_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable      = true
      sample_rate = each.value.log_sample_rate
    }
  }
}

resource "google_compute_region_backend_service" "this" {
  for_each = local.is_internal ? { for k, v in var.backends : k => v if !v.is_serverless_neg } : {}

  project     = var.project_id
  region      = var.region
  name        = "${var.name}-${each.key}-backend"
  description = each.value.description
  protocol    = each.value.protocol
  port_name   = each.value.port_name
  timeout_sec = each.value.timeout_sec

  load_balancing_scheme = "INTERNAL_MANAGED"
  health_checks         = each.value.is_serverless_neg ? [] : [local.health_check_ids[each.key]]

  dynamic "iap" {
    for_each = length(each.value.iap_config) > 0 ? each.value.iap_config : []
    content {
      enabled              = iap.value.enabled
      oauth2_client_id     = iap.value.oauth2_client_id
      oauth2_client_secret = iap.value.oauth2_client_secret
    }
  }

  dynamic "backend" {
    for_each = each.value.groups
    content {
      group                        = backend.value.group
      balancing_mode               = backend.value.balancing_mode
      capacity_scaler              = backend.value.capacity_scaler
      max_connections              = backend.value.max_connections
      max_connections_per_endpoint = backend.value.max_connections_per_endpoint
      max_connections_per_instance = backend.value.max_connections_per_instance
      max_rate                     = backend.value.max_rate
      max_rate_per_endpoint        = backend.value.max_rate_per_endpoint
      max_rate_per_instance        = backend.value.max_rate_per_instance
      max_utilization              = backend.value.balancing_mode == "UTILIZATION" ? backend.value.max_utilization : null
    }
  }

  dynamic "log_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable      = true
      sample_rate = each.value.log_sample_rate
    }
  }
}

############################################
# URL map (path/host routing)
############################################
locals {
  # Unified view of both backend flavors so the url_map doesn't care whether
  # a given routing key is a backend_service or a backend_bucket.
  backend_meta = merge(
    { for k, v in var.backends : k => {
      is_default    = v.is_default
      host_patterns = v.host_patterns
      path_patterns = v.path_patterns
      }
    },
    { for k, v in var.backend_buckets : k => {
      is_default    = v.is_default
      host_patterns = v.host_patterns
      path_patterns = v.path_patterns
      }
    }
  )

  # Resolves a routing key to the right resource's id, regardless of whether
  # it's backed by google_compute_backend_service or google_compute_backend_bucket.
  service_ids = merge(
    { for k, v in google_compute_backend_service.this : k => v.id },
    { for k, v in google_compute_backend_service.serverless : k => v.id },
    { for k, v in google_compute_region_backend_service.this : k => v.id },
    { for k, v in google_compute_region_backend_service.serverless : k => v.id },
    { for k, v in google_compute_backend_bucket.this : k => v.id }
  )

  default_backend_key = one([for k, v in local.backend_meta : k if v.is_default])

  # host_rule/path_matcher entries only for non-default backends with explicit
  # host or path patterns configured.
  routed_backends = {
    for k, v in local.backend_meta :
    k => v if !v.is_default && (length(v.host_patterns) > 0 || length(v.path_patterns) > 0)
  }

  backend_key_overlap = setintersection(toset(keys(var.backends)), toset(keys(var.backend_buckets)))
}

resource "google_compute_url_map" "this" {
  count = local.is_external ? 1 : 0

  project         = var.project_id
  name            = "${var.name}-url-map"
  default_service = local.service_ids[local.default_backend_key]

  dynamic "host_rule" {
    for_each = local.routed_backends
    content {
      hosts        = length(host_rule.value.host_patterns) > 0 ? host_rule.value.host_patterns : ["*"]
      path_matcher = "${host_rule.key}-matcher"
    }
  }

  dynamic "path_matcher" {
    for_each = local.routed_backends
    content {
      name            = "${path_matcher.key}-matcher"
      default_service = local.service_ids[path_matcher.key]

      dynamic "path_rule" {
        for_each = length(path_matcher.value.path_patterns) > 0 ? [1] : []
        content {
          paths   = path_matcher.value.path_patterns
          service = local.service_ids[path_matcher.key]
        }
      }
    }
  }
}

resource "google_compute_region_url_map" "this" {
  count = local.is_internal ? 1 : 0

  project         = var.project_id
  region          = var.region
  name            = "${var.name}-url-map"
  default_service = local.service_ids[local.default_backend_key]

  dynamic "host_rule" {
    for_each = local.routed_backends
    content {
      hosts        = length(host_rule.value.host_patterns) > 0 ? host_rule.value.host_patterns : ["*"]
      path_matcher = "${host_rule.key}-matcher"
    }
  }

  dynamic "path_matcher" {
    for_each = local.routed_backends
    content {
      name            = "${path_matcher.key}-matcher"
      default_service = local.service_ids[path_matcher.key]

      dynamic "path_rule" {
        for_each = length(path_matcher.value.path_patterns) > 0 ? [1] : []
        content {
          paths   = path_matcher.value.path_patterns
          service = local.service_ids[path_matcher.key]
        }
      }
    }
  }
}

locals {
  url_map_id = local.is_external ? google_compute_url_map.this[0].id : google_compute_region_url_map.this[0].id
}

# Redirect-only map: HTTP -> HTTPS.
resource "google_compute_url_map" "https_redirect" {
  count = local.is_external && var.enable_ssl && var.https_redirect ? 1 : 0

  project = var.project_id
  name    = "${var.name}-https-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_region_url_map" "https_redirect" {
  count = local.is_internal && var.enable_ssl && var.https_redirect ? 1 : 0

  project = var.project_id
  region  = var.region
  name    = "${var.name}-https-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

locals {
  http_url_map_id = local.is_external ? (
    var.enable_ssl && var.https_redirect ? google_compute_url_map.https_redirect[0].id : google_compute_url_map.this[0].id
    ) : (
    var.enable_ssl && var.https_redirect ? google_compute_region_url_map.https_redirect[0].id : google_compute_region_url_map.this[0].id
  )
}

############################################
# HTTP listener (port 80) — optional
############################################
resource "google_compute_target_http_proxy" "this" {
  count = local.is_external && var.enable_http ? 1 : 0

  project = var.project_id
  name    = "${var.name}-http-proxy"
  url_map = local.http_url_map_id
}

resource "google_compute_region_target_http_proxy" "this" {
  count = local.is_internal && var.enable_http ? 1 : 0

  project = var.project_id
  region  = var.region
  name    = "${var.name}-http-proxy"
  url_map = local.http_url_map_id
}

resource "google_compute_global_forwarding_rule" "http" {
  count = local.is_external && var.enable_http ? 1 : 0

  project               = var.project_id
  name                  = "${var.name}-http-fr"
  target                = google_compute_target_http_proxy.this[0].id
  port_range            = "80"
  ip_address            = local.lb_ipv4_address
  load_balancing_scheme = "EXTERNAL_MANAGED"
  labels                = var.labels
}

resource "google_compute_forwarding_rule" "http" {
  count = local.is_internal && var.enable_http ? 1 : 0

  project               = var.project_id
  region                = var.region
  name                  = "${var.name}-http-fr"
  network               = var.network
  subnetwork            = var.subnetwork
  target                = google_compute_region_target_http_proxy.this[0].id
  port_range            = "80"
  ip_address            = local.lb_ipv4_address
  load_balancing_scheme = "INTERNAL_MANAGED"
  allow_global_access   = var.allow_global_access
  labels                = var.labels
}

############################################
# Managed SSL certificate / SSL policy — optional (var.enable_ssl)
############################################
resource "google_compute_managed_ssl_certificate" "this" {
  count = local.is_external && var.enable_ssl && var.managed_ssl_certificate ? 1 : 0

  project = var.project_id
  name    = "${var.name}-cert"

  managed {
    domains = var.domains
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_ssl_policy" "this" {
  count = local.is_external && var.enable_ssl ? 1 : 0

  project         = var.project_id
  name            = "${var.name}-ssl-policy"
  profile         = var.ssl_policy_profile
  min_tls_version = var.ssl_policy_min_tls_version
}

resource "google_compute_region_ssl_policy" "this" {
  count = local.is_internal && var.enable_ssl ? 1 : 0

  project         = var.project_id
  region          = var.region
  name            = "${var.name}-ssl-policy"
  profile         = var.ssl_policy_profile
  min_tls_version = var.ssl_policy_min_tls_version
}

locals {
  ssl_certificate_ids = var.enable_ssl ? (
    local.is_external && var.managed_ssl_certificate ? [google_compute_managed_ssl_certificate.this[0].id] : var.ssl_certificate_ids
  ) : []

  ssl_policy_id = local.is_external ? try(google_compute_ssl_policy.this[0].id, null) : try(google_compute_region_ssl_policy.this[0].id, null)
}

############################################
# HTTPS proxy + forwarding rule (port 443) — optional (var.enable_ssl)
############################################
resource "google_compute_target_https_proxy" "this" {
  count = local.is_external && var.enable_ssl ? 1 : 0

  project          = var.project_id
  name             = "${var.name}-https-proxy"
  url_map          = local.url_map_id
  ssl_certificates = local.ssl_certificate_ids
  ssl_policy       = local.ssl_policy_id
}

resource "google_compute_region_target_https_proxy" "this" {
  count = local.is_internal && var.enable_ssl ? 1 : 0

  project          = var.project_id
  region           = var.region
  name             = "${var.name}-https-proxy"
  url_map          = local.url_map_id
  ssl_certificates = local.ssl_certificate_ids
  ssl_policy       = local.ssl_policy_id
}

resource "google_compute_global_forwarding_rule" "https" {
  count = local.is_external && var.enable_ssl ? 1 : 0

  project               = var.project_id
  name                  = "${var.name}-https-fr"
  target                = google_compute_target_https_proxy.this[0].id
  port_range            = "443"
  ip_address            = local.lb_ipv4_address
  load_balancing_scheme = "EXTERNAL_MANAGED"
  labels                = var.labels
}

resource "google_compute_global_forwarding_rule" "https_ipv6" {
  count = local.is_external && var.enable_ssl && var.enable_ipv6 ? 1 : 0

  project               = var.project_id
  name                  = "${var.name}-https-fr-ipv6"
  target                = google_compute_target_https_proxy.this[0].id
  port_range            = "443"
  ip_address            = var.create_static_ip ? google_compute_global_address.ipv6[0].address : null
  load_balancing_scheme = "EXTERNAL_MANAGED"
  labels                = var.labels
}

resource "google_compute_forwarding_rule" "https" {
  count = local.is_internal && var.enable_ssl ? 1 : 0

  project               = var.project_id
  region                = var.region
  name                  = "${var.name}-https-fr"
  network               = var.network
  subnetwork            = var.subnetwork
  target                = google_compute_region_target_https_proxy.this[0].id
  port_range            = "443"
  ip_address            = local.lb_ipv4_address
  load_balancing_scheme = "INTERNAL_MANAGED"
  allow_global_access   = var.allow_global_access
  labels                = var.labels
}

############################################
# Guardrail: don't allow a config with no listener at all
############################################
check "at_least_one_listener" {
  assert {
    condition     = var.enable_http || var.enable_ssl
    error_message = "Both var.enable_http and var.enable_ssl are false — the load balancer would have no forwarding rule to receive traffic on."
  }
}

check "backend_and_backend_bucket_keys_valid" {
  assert {
    condition     = length(local.backend_key_overlap) == 0
    error_message = "The following keys exist in both var.backends and var.backend_buckets: ${join(", ", local.backend_key_overlap)}. Each routing key must be backed by exactly one of a backend_service or a backend_bucket, not both."
  }
  assert {
    condition     = length([for k, v in local.backend_meta : k if v.is_default]) == 1
    error_message = "Exactly one entry across var.backends and var.backend_buckets must have is_default = true."
  }
}