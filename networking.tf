locals {
  net_project_services = [
    "compute.googleapis.com"
  ]
}

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

resource "google_compute_network" "example-net-vpc" {
  project                 = google_project.example-net-proj.name
  name                    = "example-net-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
  depends_on = [
    google_project_service.example-net-services
  ]
}
resource "google_compute_shared_vpc_host_project" "example-net-host-project" {
  project = google_project.example-net-proj.name
}

resource "google_compute_subnetwork" "example-net-subnet" {
  project       = google_project.example-net-proj.name
  for_each      = var.subnets
  name          = each.key
  region        = var.region
  ip_cidr_range = each.value
  network       = google_compute_network.example-net-vpc.id
}
