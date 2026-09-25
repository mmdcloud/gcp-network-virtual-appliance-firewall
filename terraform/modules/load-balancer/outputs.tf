output "lb_ip_address" {
  description = "The global external IPv4 address serving this load balancer. Point your DNS A record here."
  value       = local.lb_ipv4_address
}

output "lb_ipv6_address" {
  description = "The global external IPv6 address, if enable_ipv6 = true."
  value       = var.enable_ipv6 && var.create_static_ip ? google_compute_global_address.ipv6[0].address : null
}

output "backend_service_ids" {
  description = "Map of backend key to backend service ID."
  value       = { for k, v in google_compute_backend_service.this : k => v.id }
}

output "backend_service_names" {
  description = "Map of backend key to backend service name — needed for IAM bindings like google_iap_web_backend_service_iam_binding, which expects a name, not a self_link."
  value = merge(
    { for k, v in google_compute_backend_service.this : k => v.name },
    { for k, v in google_compute_backend_service.serverless : k => v.name },
    { for k, v in google_compute_region_backend_service.this : k => v.name },
    { for k, v in google_compute_region_backend_service.serverless : k => v.name }
  )
}

output "health_check_ids" {
  description = "Map of backend key to the health check ID actually in use (created here, or the caller-supplied one)."
  value       = local.health_check_ids
}

# output "managed_ssl_certificate_id" {
#   description = "ID of the Google-managed SSL certificate, if created."
#   value       = var.managed_ssl_certificate ? google_compute_managed_ssl_certificate.this[0].id : null
# }

output "security_policy_id" {
  description = "ID of the Cloud Armor security policy, if enabled."
  value       = var.enable_cloud_armor ? google_compute_security_policy.this[0].id : null
}

output "http_forwarding_rule_id" {
  description = "ID of the Cloud Armor security policy, if enabled."
  value       = try(google_compute_forwarding_rule.http[0].id, null)
}

output "global_http_forwarding_rule_id" {
  description = "ID of the Cloud Armor security policy, if enabled."
  value       = try(google_compute_global_forwarding_rule.http[0].id, null)
}

# output "https_forwarding_rule_id" {
#   description = "ID of the HTTPS (443) global forwarding rule."
#   value       = google_compute_global_forwarding_rule.https.id
# }

# output "http_forwarding_rule_id" {
#   description = "ID of the HTTP (80) redirect forwarding rule, if enabled."
#   value       = var.enable_http_redirect ? google_compute_global_forwarding_rule.http[0].id : null
# }
