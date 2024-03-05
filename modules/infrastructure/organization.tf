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
  backend_api = [
    "compute.googleapis.com"
  ]
  backend-proj-services = {
    for tuple in setproduct(var.env, local.backend_api) :
    "${tuple[0]}-${regex("^[a-z]*", tuple[1])}" =>
    { env = tuple[0], service = tuple[1] }
  }
  frontend_api = [
    "compute.googleapis.com",
    "certificatemanager.googleapis.com"
  ]
  frontend-proj-services = {
    for tuple in setproduct(var.env, local.frontend_api) :
    "${tuple[0]}-${regex("^[a-z]*", tuple[1])}" =>
    { env = tuple[0], service = tuple[1] }
  }
}

# Create the main folder...
resource "google_folder" "app-folder" {
  display_name = var.app
  parent       = "organizations/${var.organization.id}"
}

# ...and some folders inside it.
resource "google_folder" "networking-folder" {
  display_name = "networking"
  parent       = google_folder.app-folder.name
}

resource "google_folder" "networking-env-folder" {
  for_each     = toset(var.env)
  display_name = each.key
  parent       = google_folder.networking-folder.name
}

resource "google_folder" "backend-folder" {
  display_name = "backend"
  parent       = google_folder.app-folder.name
}

resource "google_folder" "backend-env-folder" {
  for_each     = toset(var.env)
  display_name = each.key
  parent       = google_folder.backend-folder.name
}

resource "google_folder" "frontend-folder" {
  display_name = "frontend"
  parent       = google_folder.app-folder.name
}

resource "google_folder" "frontend-env-folder" {
  for_each     = toset(var.env)
  display_name = each.key
  parent       = google_folder.frontend-folder.name
}

#Create the Network projects and activate some APIs
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

# Create the BE projects and activate some APIs
resource "google_project" "backend-proj" {
  for_each        = toset(var.env)
  name            = "${var.app}-${each.key}-backend"
  project_id      = "${var.app}-${each.key}-backend"
  folder_id       = google_folder.backend-env-folder[each.key].name
  billing_account = var.billing_account
}

resource "google_project_service" "backend-proj-services" {
  for_each = local.backend-proj-services
  project  = google_project.backend-proj[each.value.env].id
  service  = each.value.service
}

# Create the FE project and activate some APIs
resource "google_project" "frontend-proj" {
  for_each        = toset(var.env)
  name            = "${var.app}-${each.key}-frontend"
  project_id      = "${var.app}-${each.key}-frontend"
  folder_id       = google_folder.frontend-env-folder[each.key].name
  billing_account = var.billing_account
}

resource "google_project_service" "frontend-proj-services" {
  for_each = local.frontend-proj-services
  project  = google_project.frontend-proj[each.value.env].id
  service  = each.value.service
}

