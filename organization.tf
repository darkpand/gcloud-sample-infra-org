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
