locals {
  net_project_services = [
    "compute.googleapis.com",
    "dns.googleapis.com"
  ]
  network_users = [
    google_project.example-backend-proj.number,
    google_project.example-frontend-proj.number
  ]
}

#Create the Network project and activate some APIs
resource "google_project" "example-net-proj" {
  name            = "${var.prefix}-example-net"
  project_id      = "${var.prefix}-example-net"
  folder_id       = google_folder.networking-folder.name
  billing_account = var.billing_account
}

resource "google_project_service" "example-net-services" {
  for_each = toset(local.net_project_services)
  project  = google_project.example-net-proj.id
  service  = each.key
}

# networkuser role to default compute SA of FE and BE projects, so
# it can create vm on the shared subnets 
resource "google_project_iam_member" "example-net-users-iam" {
  for_each = toset(local.network_users)
  project  = google_project.example-net-proj.id
  role     = "roles/compute.networkUser"
  member   = "serviceAccount:${each.key}@cloudservices.gserviceaccount.com"
}

# Create the VPC
resource "google_compute_network" "example-net-vpc" {
  project                 = google_project.example-net-proj.name
  name                    = "example-net-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
  depends_on = [
    google_project_service.example-net-services
  ]
}

# Define this project as the Host project, so we will share the VPC 
# with the Service projects
resource "google_compute_shared_vpc_host_project" "example-net-host-project" {
  project = google_project.example-net-proj.name
}

# Create some subnets
resource "google_compute_subnetwork" "example-net-subnet" {
  for_each      = var.subnets
  project       = google_project.example-net-proj.name
  name          = each.key
  region        = var.region
  ip_cidr_range = each.value
  network       = google_compute_network.example-net-vpc.id
}

# Enable traffic to port 80 for resources with "http" tag
resource "google_compute_firewall" "example-net-firewall-http" {
  project = google_project.example-net-proj.name
  name    = "example-net-firewall-http"
  network = google_compute_network.example-net-vpc.name
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http"]
}

# Enable ssh traffic from IAP ranges
resource "google_compute_firewall" "example-net-firewall-sshiap" {
  project = google_project.example-net-proj.name
  name    = "example-net-firewall-sshiap"
  network = google_compute_network.example-net-vpc.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
}

# Create a Cloud Router and attach it to the VPC
resource "google_compute_router" "example-net-router" {
  project = google_project.example-net-proj.name
  name    = "cloud-router"
  network = google_compute_network.example-net-vpc.name
  region  = var.region
}

# Attach a Cloud NAT to the Cloud Router
resource "google_compute_router_nat" "example-net-nat" {
  project                            = google_project.example-net-proj.name
  name                               = "example-net-nat"
  router                             = google_compute_router.example-net-router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_dns_managed_zone" "example-zone" {
  project     = google_project.example-net-proj.name
  name        = "example-zone"
  dns_name    = "example.gcp.${var.organization.domain}."
  description = "Example DNS zone"
}
