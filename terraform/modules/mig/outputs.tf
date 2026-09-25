output "instance_group_manager_id" {
  description = "ID of the regional Managed Instance Group."
  value       = google_compute_region_instance_group_manager.this.id
}

output "instance_group_self_link" {
  description = "Self link of the underlying (unmanaged view of the) instance group. Use this to attach the MIG to a load balancer backend service."
  value       = google_compute_region_instance_group_manager.this.instance_group
}

output "health_check_id" {
  description = "ID of the health check used for auto-healing (and reusable for LB backend services)."
  value       = google_compute_health_check.this.id
}

output "health_check_self_link" {
  description = "Self link of the health check."
  value       = google_compute_health_check.this.self_link
}

output "autoscaler_id" {
  description = "ID of the autoscaler, if enabled."
  value       = var.autoscaling_enabled ? google_compute_region_autoscaler.autoscaler[0].id : null
}