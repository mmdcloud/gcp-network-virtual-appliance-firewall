# --------------------------------------------------------------------------
# Data resource blocks
# --------------------------------------------------------------------------
data "google_project" "project" {}

data "google_compute_image" "ubuntu_2404" {
  family  = var.image_family
  project = var.image_project
}

# --------------------------------------------------------------------------
# VPC Configuration
# --------------------------------------------------------------------------
module "producer_vpc" {
  source                          = "./modules/vpc"
  vpc_name                        = var.producer_vpc_name
  delete_default_routes_on_create = false
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  subnets = [
    {
      name                     = var.mig_subnet_name
      region                   = var.producer_region
      purpose                  = "PRIVATE"
      role                     = "ACTIVE"
      private_ip_google_access = true
      ip_cidr_range            = var.mig_subnet_cidr
    },
    {
      name                     = var.lb_subnet_name
      region                   = var.producer_region
      purpose                  = "PRIVATE"
      role                     = "ACTIVE"
      private_ip_google_access = true
      ip_cidr_range            = var.lb_subnet_cidr
    }
  ]
  firewall_data = [
    {
      name        = "producer-vpc-firewall-http"
      target_tags = [var.producer_instance_tag]
      source_ranges = concat(
        [var.proxy_only_subnet_cidr],  # proxy-only subnet (Envoy -> backend)
        var.health_check_source_ranges # GCP health check probe ranges
      )
      allow_list = [
        {
          protocol = "tcp"
          ports    = [var.http_port]
        }
      ]
    },
    {
      name          = "producer-vpc-firewall-ssh"
      target_tags   = [var.producer_instance_tag]
      source_ranges = var.iap_ssh_source_ranges
      allow_list = [
        {
          protocol = "tcp"
          ports    = [var.ssh_port]
        }
      ]
    }
  ]
}

# --------------------------------------------------------------------------
# NAT Gateway and Cloud Router Configuration
# --------------------------------------------------------------------------
module "cloud_nat" {
  source = "./modules/cloud-nat"

  project_id = var.project_id
  region     = var.producer_region

  create_router = true
  router        = var.router_name
  network       = module.producer_vpc.self_link
  type          = "PUBLIC"
  name          = var.router_nat_name

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetworks = [
    {
      name                     = module.producer_vpc.subnets_by_name[var.mig_subnet_name].self_link
      source_ip_ranges_to_nat  = ["ALL_IP_RANGES"]
      secondary_ip_range_names = []
    }
  ]

  log_config_enable = true
  log_config_filter = "ALL"
}

# -----------------------------------------------------------------------------------------
# Instance template
# -----------------------------------------------------------------------------------------
module "instance_template" {
  source = "./modules/instance-template"

  region     = var.producer_region
  project_id = data.google_project.project.project_id

  name_prefix       = var.instance_template_name_prefix
  machine_type      = var.instance_template_machine_type
  source_image      = data.google_compute_image.ubuntu_2404.self_link
  boot_disk_size_gb = var.boot_disk_size_gb
  boot_disk_type    = var.boot_disk_type

  network          = module.producer_vpc.self_link
  subnetwork       = module.producer_vpc.subnets_by_name[var.mig_subnet_name].self_link
  assign_public_ip = false
  network_tags     = [var.producer_instance_tag]

  create_service_account = true
  service_account_roles  = var.service_account_roles

  startup_script = var.startup_script

  labels = var.common_labels
}

# -----------------------------------------------------------------------------------------
# MIG Configuration
# -----------------------------------------------------------------------------------------
module "mig" {
  source = "./modules/mig"

  project_id = var.project_id
  name       = var.mig_name
  region     = var.producer_region

  instance_template = module.instance_template.self_link_unique

  named_ports = [
    { name = var.mig_named_port_name, port = var.mig_named_port_number }
  ]

  health_check = {
    type         = var.mig_health_check_type
    port         = var.mig_health_check_port
    request_path = var.mig_health_check_request_path
  }

  autoscaling_enabled = true
  autoscaler_name     = "mig-autoscaler"
  min_replicas        = var.mig_autoscaling_min_replicas
  max_replicas        = var.mig_autoscaling_max_replicas

  labels = var.common_labels
}

# -----------------------------------------------------------------------------------------
# Load Balancer
# -----------------------------------------------------------------------------------------
module "lb" {
  source             = "./modules/load-balancer"
  project_id         = var.project_id
  name               = var.lb_name
  load_balancer_type = var.lb_type
  region             = var.producer_region
  network            = module.producer_vpc.self_link
  subnetwork         = module.producer_vpc.subnets_by_name[var.lb_subnet_name].self_link

  create_proxy_only_subnet = true
  proxy_only_subnet_cidr   = var.proxy_only_subnet_cidr

  backends = {
    lb = {
      is_default          = true
      protocol            = var.lb_backend_protocol
      port_name           = var.lb_backend_port_name
      health_check_id     = module.mig.health_check_id
      manage_health_check = false
      groups = [
        {
          group           = module.mig.instance_group_self_link
          balancing_mode  = var.lb_balancing_mode
          capacity_scaler = var.lb_capacity_scaler
          max_utilization = var.lb_max_utilization
        }
      ]
    }
  }

  allow_global_access     = var.lb_allow_global_access
  enable_ssl              = var.lb_enable_ssl
  enable_http             = var.lb_enable_http
  managed_ssl_certificate = var.lb_managed_ssl_certificate
  enable_cloud_armor      = var.lb_enable_cloud_armor
  depends_on              = [module.mig]
}

#---------------------------------------------------------------
# Hub-Spoke: all four VPCs attached as spokes to the same hub
#---------------------------------------------------------------
module "hub-spoke" {
  source          = "./modules/hub-spoke"
  hub_name        = var.hub_name
  hub_description = var.hub_description
  export_psc      = true
  spokes = [
    {
      spoke_name = "vpc1-spoke"
      location   = "global"
      linked_vpc_network = {
        uri = module.vpc1.self_link
      }
    }
  ]
}