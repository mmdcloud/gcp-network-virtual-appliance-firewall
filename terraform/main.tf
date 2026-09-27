# --------------------------------------------------------------------------
# Data resource blocks
# --------------------------------------------------------------------------
data "google_project" "project" {}

data "google_compute_image" "ubuntu_2404" {
  family  = var.image_family
  project = var.image_project
}

# --------------------------------------------------------------------------
# Workload Configuration
# --------------------------------------------------------------------------
module "workload_vpc" {
  source                          = "./modules/vpc"
  vpc_name                        = var.workload_vpc_name
  delete_default_routes_on_create = false
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  subnets = [
    {
      name                     = var.workload_subnet_name
      region                   = var.region
      purpose                  = "PRIVATE"
      role                     = "ACTIVE"
      private_ip_google_access = true
      ip_cidr_range            = var.workload_subnet_cidr
    },
    {
      name                     = var.workload_lb_subnet_name
      region                   = var.region
      purpose                  = "PRIVATE"
      role                     = "ACTIVE"
      private_ip_google_access = true
      ip_cidr_range            = var.workload_lb_subnet_cidr
    }
  ]
  firewall_data = [
    # {
    #   name        = "workload-vpc-firewall-http"
    #   target_tags = [var.producer_instance_tag]
    #   source_ranges = concat(
    #     [var.proxy_only_subnet_cidr],  # proxy-only subnet (Envoy -> backend)
    #     var.health_check_source_ranges # GCP health check probe ranges
    #   )
    #   allow_list = [
    #     {
    #       protocol = "tcp"
    #       ports    = [var.http_port]
    #     }
    #   ]
    # },
    # {
    #   name          = "workload-vpc-firewall-ssh"
    #   target_tags   = [var.producer_instance_tag]
    #   source_ranges = var.iap_ssh_source_ranges
    #   allow_list = [
    #     {
    #       protocol = "tcp"
    #       ports    = [var.ssh_port]
    #     }
    #   ]
    # }
  ]
}

module "workload_cloud_nat" {
  source = "./modules/cloud-nat"

  project_id = var.project_id
  region     = var.region

  create_router = true
  router        = var.workload_router_name
  network       = module.workload_vpc.self_link
  type          = "PUBLIC"
  name          = var.workload_router_nat_name

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetworks = [
    {
      name                     = module.workload_vpc.subnets_by_name[var.workload_subnet_name].self_link
      source_ip_ranges_to_nat  = ["ALL_IP_RANGES"]
      secondary_ip_range_names = []
    }
  ]

  log_config_enable = true
  log_config_filter = "ALL"
}

module "workload_instance_template" {
  source = "./modules/instance-template"

  region     = var.region
  project_id = data.google_project.project.project_id

  name_prefix       = var.workload_instance_template_name_prefix
  machine_type      = var.workload_instance_template_machine_type
  source_image      = data.google_compute_image.ubuntu_2404.self_link
  boot_disk_size_gb = var.workload_boot_disk_size_gb
  boot_disk_type    = var.workload_boot_disk_type

  network          = module.workload_vpc.self_link
  subnetwork       = module.workload_vpc.subnets_by_name[var.workload_subnet_name].self_link
  assign_public_ip = false
  network_tags     = [var.producer_instance_tag]

  create_service_account = true
  service_account_roles  = var.service_account_roles

  startup_script = var.startup_script

  labels = var.common_labels
}

module "workload_mig" {
  source = "./modules/mig"

  project_id = var.project_id
  name       = var.workload_mig_name
  region     = var.region

  instance_template = module.workload_instance_template.self_link_unique

  named_ports = [
    { name = var.workload_mig_named_port_name, port = var.workload_mig_named_port_number }
  ]

  health_check = {
    type         = var.workload_mig_health_check_type
    port         = var.workload_mig_health_check_port
    request_path = var.workload_mig_health_check_request_path
  }

  autoscaling_enabled = true
  autoscaler_name     = "mig-autoscaler"
  min_replicas        = var.workload_mig_autoscaling_min_replicas
  max_replicas        = var.workload_mig_autoscaling_max_replicas

  labels = var.common_labels
}

module "workload_lb" {
  source             = "./modules/load-balancer"
  project_id         = var.project_id
  name               = var.workload_lb_name
  load_balancer_type = var.workload_lb_type
  region             = var.region
  network            = module.workload_vpc.self_link
  subnetwork         = module.workload_vpc.subnets_by_name[var.workload_lb_subnet_name].self_link

  create_proxy_only_subnet = true
  proxy_only_subnet_cidr   = var.workload_proxy_only_subnet_cidr

  backends = {
    lb = {
      is_default          = true
      protocol            = var.workload_lb_backend_protocol
      port_name           = var.workload_lb_backend_port_name
      health_check_id     = module.workload_mig.health_check_id
      manage_health_check = false
      groups = [
        {
          group           = module.workload_mig.instance_group_self_link
          balancing_mode  = var.workload_lb_balancing_mode
          capacity_scaler = var.workload_lb_capacity_scaler
          max_utilization = var.workload_lb_max_utilization
        }
      ]
    }
  }

  allow_global_access     = var.workload_lb_allow_global_access
  enable_ssl              = var.workload_lb_enable_ssl
  enable_http             = var.workload_lb_enable_http
  managed_ssl_certificate = var.workload_lb_managed_ssl_certificate
  enable_cloud_armor      = var.workload_lb_enable_cloud_armor
  depends_on              = [module.workload_mig]
}


# --------------------------------------------------------------------------
# NVA Configuration
# --------------------------------------------------------------------------
module "hub_vpc" {
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

module "nva_cloud_nat" {
  source = "./modules/cloud-nat"

  project_id = var.project_id
  region     = var.region

  create_router = true
  router        = var.nva_router_name
  network       = module.hub_vpc.self_link
  type          = "PUBLIC"
  name          = var.nva_router_nat_name

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetworks = [
    {
      name                     = module.hub_vpc.subnets_by_name[var.nva_mig_subnet_name].self_link
      source_ip_ranges_to_nat  = ["ALL_IP_RANGES"]
      secondary_ip_range_names = []
    }
  ]

  log_config_enable = true
  log_config_filter = "ALL"
}

module "nva_instance_template" {
  source = "./modules/instance-template"

  region     = var.region
  project_id = data.google_project.project.project_id

  name_prefix       = var.nva_instance_template_name_prefix
  machine_type      = var.nva_instance_template_machine_type
  source_image      = data.google_compute_image.ubuntu_2404.self_link
  boot_disk_size_gb = var.nva_boot_disk_size_gb
  boot_disk_type    = var.nva_boot_disk_type

  network          = module.hub_vpc.self_link
  subnetwork       = module.hub_vpc.subnets_by_name[var.nva_mig_subnet_name].self_link
  assign_public_ip = false
  network_tags     = [var.producer_instance_tag]

  create_service_account = true
  service_account_roles  = var.service_account_roles

  startup_script = var.startup_script

  labels = var.common_labels
}

module "nva_mig" {
  source = "./modules/mig"

  project_id = var.project_id
  name       = var.nva_mig_name
  region     = var.region

  instance_template = module.nva_instance_template.self_link_unique

  named_ports = [
    { name = var.nva_mig_named_port_name, port = var.nva_mig_named_port_number }
  ]

  health_check = {
    type         = var.nva_mig_health_check_type
    port         = var.nva_mig_health_check_port
    request_path = var.nva_mig_health_check_request_path
  }

  autoscaling_enabled = true
  autoscaler_name     = "mig-autoscaler"
  min_replicas        = var.nva_mig_autoscaling_min_replicas
  max_replicas        = var.nva_mig_autoscaling_max_replicas

  labels = var.common_labels
}

module "nva_lb" {
  source             = "./modules/load-balancer"
  project_id         = var.project_id
  name               = var.nva_lb_name
  load_balancer_type = var.nva_lb_type
  region             = var.region
  network            = module.hub_vpc.self_link
  subnetwork         = module.hub_vpc.subnets_by_name[var.nva_lb_subnet_name].self_link

  create_proxy_only_subnet = true
  proxy_only_subnet_cidr   = var.nva_proxy_only_subnet_cidr

  backends = {
    lb = {
      is_default          = true
      protocol            = var.nva_lb_backend_protocol
      port_name           = var.nva_lb_backend_port_name
      health_check_id     = module.nva_mig.health_check_id
      manage_health_check = false
      groups = [
        {
          group           = module.nva_mig.instance_group_self_link
          balancing_mode  = var.nva_lb_balancing_mode
          capacity_scaler = var.nva_lb_capacity_scaler
          max_utilization = var.nva_lb_max_utilization
        }
      ]
    }
  }

  allow_global_access     = var.nva_lb_allow_global_access
  enable_ssl              = var.nva_lb_enable_ssl
  enable_http             = var.nva_lb_enable_http
  managed_ssl_certificate = var.nva_lb_managed_ssl_certificate
  enable_cloud_armor      = var.nva_lb_enable_cloud_armor
  depends_on              = [module.nva_mig]
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
