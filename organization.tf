resource "google_folder" "example-folder" {
  display_name = "Example"
  parent       = "organizations/${var.organization.id}"
}

resource "google_folder" "networking-folder" {
  display_name = "Networking"
  parent       = google_folder.example-folder.name
}

resource "google_folder" "frontend-folder" {
  display_name = "Frontend"
  parent       = google_folder.example-folder.name
}

resource "google_folder" "backend-folder" {
  display_name = "Backend"
  parent       = google_folder.example-folder.name
}
