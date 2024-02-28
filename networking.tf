locals {
  net_api = [
    "compute.googleapis.com",
    "dns.googleapis.com"
  ]

  net-proj-services = {
    for tuple in setproduct(var.env, local.net_api) :
    "${tuple[0]}-${regex("^[a-z]*", tuple[1])}" =>
    { env = tuple[0], service = tuple[1] }
  }
}

#Create the Network project and activate some APIs
resource "google_project" "net-proj" {
  for_each        = toset(var.env)
  name            = "${var.app}-${each.key}-net"
  project_id      = "${var.app}-${each.key}-net"
  folder_id       = google_folder.networking-env-folder[each.key].name
  billing_account = var.billing_account
}

resource "google_project_service" "net-proj-services" {
  for_each = local.net-proj-services
  project  = google_project.net-proj[each.value.env].id
  service  = each.value.service
}

# networkuser role to default compute SA of FE and BE projects, so
# it can create vm on the shared subnets 
# This for BE
resource "google_project_iam_member" "net-netuser-be-iam" {
  for_each = toset(var.env)
  project  = google_project.net-proj[each.key].id
  role     = "roles/compute.networkUser"
  member   = "serviceAccount:${google_project.backend-proj[each.key].number}@cloudservices.gserviceaccount.com"
}

# This for FE
resource "google_project_iam_member" "net-netuser-fe-iam" {
  for_each = toset(var.env)
  project  = google_project.net-proj[each.key].id
  role     = "roles/compute.networkUser"
  member   = "serviceAccount:${google_project.frontend-proj[each.key].number}@cloudservices.gserviceaccount.com"
}

# Create the VPC
resource "google_compute_network" "net-vpc" {
  for_each                = toset(var.env)
  project                 = google_project.net-proj[each.key].name
  name                    = "${var.app}-${each.key}-net-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
  depends_on = [
    google_project_service.net-proj-services
  ]
}

# Define this project as the Host project, so we will share the VPC 
# with the Service projects
resource "google_compute_shared_vpc_host_project" "net-host-project" {
  for_each = toset(var.env)
  project  = google_project.net-proj[each.key].name
}

# Create BE subnets
resource "google_compute_subnetwork" "net-subnet-be" {
  for_each      = toset(var.env)
  project       = google_project.net-proj[each.key].name
  name          = "${var.app}-${each.key}-subnet-be"
  region        = var.region
  ip_cidr_range = var.subnets[each.key].backend
  network       = google_compute_network.net-vpc[each.key].name
}

# Create FE subnets
resource "google_compute_subnetwork" "net-subnet-fe" {
  for_each      = toset(var.env)
  project       = google_project.net-proj[each.key].name
  name          = "${var.app}-${each.key}-subnet-fe"
  region        = var.region
  ip_cidr_range = var.subnets[each.key].frontend
  network       = google_compute_network.net-vpc[each.key].name
}

# Enable traffic to port 80 for resources with "http" tag
resource "google_compute_firewall" "net-firewall-http" {
  for_each = toset(var.env)
  project  = google_project.net-proj[each.key].name
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
  project  = google_project.net-proj[each.key].name
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
  project  = google_project.net-proj[each.key].name
  name     = "net-${each.key}-cloud-router"
  network  = google_compute_network.net-vpc[each.key].name
  region   = var.region
}

# Attach a Cloud NAT to the Cloud Router
resource "google_compute_router_nat" "net-cloud-nat" {
  for_each                           = toset(var.env)
  project                            = google_project.net-proj[each.key].name
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
  project     = google_project.net-proj[each.key].name
  name        = "${each.key}-${var.app}-zone"
  dns_name    = "${each.key}.${var.app}.gcp.${var.organization.domain}."
  description = "DNS zone for app ${var.app} - ${each.key} env"
}
