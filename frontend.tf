locals {
  frontend_project_services = [
    "compute.googleapis.com"
  ]
}

resource "google_project" "example-frontend-proj" {
  name            = "${var.prefix}-example-frontend"
  project_id      = "${var.prefix}-example-frontend"
  folder_id       = google_folder.frontend-folder.name
  billing_account = var.billing_account
}

resource "google_project_service" "example-frontend-services" {
  for_each = toset(local.frontend_project_services)
  project  = google_project.example-frontend-proj.id
  service  = each.key
}

resource "google_compute_shared_vpc_service_project" "example-frontend-service-project" {
  host_project    = google_project.example-net-proj.name
  service_project = google_project.example-frontend-proj.name
}

