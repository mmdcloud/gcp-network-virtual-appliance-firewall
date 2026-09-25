output "template_id" {
  description = "Fully qualified resource ID of the instance template."
  value       = google_compute_instance_template.this.id
}

output "self_link" {
  description = "Self-link of the instance template. Use this in a MIG, and it will always point to the current version because self_link_unique also exists if you need pinning."
  value       = google_compute_instance_template.this.self_link
}

output "self_link_unique" {
  description = "Self-link including the unique instance template ID, guaranteed to refer to this exact template version."
  value       = google_compute_instance_template.this.self_link_unique
}

output "name" {
  description = "Generated name of the instance template (includes random suffix)."
  value       = google_compute_instance_template.this.name
}

output "service_account_email" {
  description = "Email of the service account attached to instances created from this template."
  value       = local.resolved_service_account_email
}