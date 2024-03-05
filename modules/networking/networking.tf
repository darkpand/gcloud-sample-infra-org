# networkuser role to default compute SA of FE and BE projects, so
# it can create vm on the shared subnets 
# This for BE
resource "google_project_iam_member" "net-netuser-be-iam" {
  for_each = toset(var.env)
  project  = var.network_projects[each.key].id
  role     = "roles/compute.networkUser"
  member   = "serviceAccount:${var.backend_projects[each.key].number}@cloudservices.gserviceaccount.com"
}

# This for FE
resource "google_project_iam_member" "net-netuser-fe-iam" {
  for_each = toset(var.env)
  project  = var.network_projects[each.key].id
  role     = "roles/compute.networkUser"
  member   = "serviceAccount:${var.frontend_projects[each.key].number}@cloudservices.gserviceaccount.com"
}

# Define this project as the Host project, so we will share the VPC 
# with the Service projects
resource "google_compute_shared_vpc_host_project" "net-host-project" {
  for_each = toset(var.env)
  project  = var.network_projects[each.key].name
}

# Connect to the Shared VPC in the network project
resource "google_compute_shared_vpc_service_project" "backend-service-project" {
  for_each        = toset(var.env)
  host_project    = var.network_projects[each.key].name
  service_project = var.backend_projects[each.key].name
  depends_on      = [google_compute_shared_vpc_host_project.net-host-project]
}

# Connect to the Shared VPC in the network project
resource "google_compute_shared_vpc_service_project" "frontend-service-project" {
  for_each        = toset(var.env)
  host_project    = var.network_projects[each.key].name
  service_project = var.frontend_projects[each.key].name
  depends_on      = [google_compute_shared_vpc_host_project.net-host-project]
}

# Create the VPC
resource "google_compute_network" "net-vpc" {
  for_each                = toset(var.env)
  project                 = var.network_projects[each.key].name
  name                    = "${var.app}-${each.key}-net-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

# Create BE subnets
resource "google_compute_subnetwork" "net-subnet-be" {
  for_each      = toset(var.env)
  project       = var.network_projects[each.key].name
  name          = "${var.app}-${each.key}-subnet-be"
  region        = var.region
  ip_cidr_range = var.subnets[each.key].backend
  network       = google_compute_network.net-vpc[each.key].name
}

# Create FE subnets
resource "google_compute_subnetwork" "net-subnet-fe" {
  for_each      = toset(var.env)
  project       = var.network_projects[each.key].name
  name          = "${var.app}-${each.key}-subnet-fe"
  region        = var.region
  ip_cidr_range = var.subnets[each.key].frontend
  network       = google_compute_network.net-vpc[each.key].name
}

# Enable traffic to port 80 for resources with "http" tag
resource "google_compute_firewall" "net-firewall-http" {
  for_each = toset(var.env)
  project  = var.network_projects[each.key].name
  name     = "net-${each.key}-firewall-http"
  network  = google_compute_network.net-vpc[each.key].name
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http"]
}

# Enable ssh traffic from IAP ranges
resource "google_compute_firewall" "net-firewall-sshiap" {
  for_each = toset(var.env)
  project  = var.network_projects[each.key].name
  name     = "net-${each.key}-firewall-sshiap"
  network  = google_compute_network.net-vpc[each.key].name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
}

# Create a Cloud Router and attach it to the VPC
resource "google_compute_router" "net-cloud-router" {
  for_each = toset(var.env)
  project  = var.network_projects[each.key].name
  name     = "net-${each.key}-cloud-router"
  network  = google_compute_network.net-vpc[each.key].name
  region   = var.region
}

# Attach a Cloud NAT to the Cloud Router
resource "google_compute_router_nat" "net-cloud-nat" {
  for_each                           = toset(var.env)
  project                            = var.network_projects[each.key].name
  name                               = "net-${each.key}-cloud-nat"
  router                             = google_compute_router.net-cloud-router[each.key].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_dns_managed_zone" "net-dns-zone" {
  for_each    = toset(var.env)
  project     = var.network_projects[each.key].name
  name        = "${each.key}-${var.app}-zone"
  dns_name    = "${each.key}.${var.app}.gcp.${var.organization.domain}."
  description = "DNS zone for app ${var.app} - ${each.key} env"
}
