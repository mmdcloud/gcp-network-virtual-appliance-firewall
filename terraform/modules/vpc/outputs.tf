output "vpc_id" {
  description = "The ID of the VPC network."
  value       = google_compute_network.vpc.id
}

output "vpc_name" {
  description = "The name of the VPC network."
  value       = google_compute_network.vpc.name
}

output "self_link" {
  description = "The URI of the VPC network."
  value       = google_compute_network.vpc.self_link
}

output "vpc_gateway_ipv4" {
  description = "The gateway address for default routing out of the network."
  value       = google_compute_network.vpc.gateway_ipv4
}

output "vpc_internal_ipv6_range" {
  description = "The internal ULA IPv6 range assigned to the network, if enabled."
  value       = google_compute_network.vpc.internal_ipv6_range
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID."
  value       = { for s in google_compute_subnetwork.subnets : s.name => s.id }
}

output "subnet_self_links" {
  description = "Map of subnet name to subnet self_link."
  value       = { for s in google_compute_subnetwork.subnets : s.name => s.self_link }
}

output "subnets_by_name" {
  description = "Map of subnet name to subnet resource object, for lookup by name."
  value       = { for s in google_compute_subnetwork.subnets : s.name => s }
}

output "subnet_regions" {
  description = "Map of subnet name to region."
  value       = { for s in google_compute_subnetwork.subnets : s.name => s.region }
}

output "subnet_ip_cidr_ranges" {
  description = "Map of subnet name to primary IP CIDR range."
  value       = { for s in google_compute_subnetwork.subnets : s.name => s.ip_cidr_range }
}

output "subnet_secondary_ip_ranges" {
  description = "Map of subnet name to its list of secondary IP ranges."
  value       = { for s in google_compute_subnetwork.subnets : s.name => s.secondary_ip_range }
}

output "subnets" {
  description = "Full subnet resource objects, keyed by subnet name."
  value       = { for s in google_compute_subnetwork.subnets : s.name => s }
}

output "firewall_ids" {
  description = "Map of firewall rule name to firewall rule ID."
  value       = { for f in google_compute_firewall.firewall : f.name => f.id }
}

output "firewall_self_links" {
  description = "Map of firewall rule name to firewall rule self_link."
  value       = { for f in google_compute_firewall.firewall : f.name => f.self_link }
}