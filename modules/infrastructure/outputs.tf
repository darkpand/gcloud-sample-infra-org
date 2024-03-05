output "network_projects" {
  value = {
    for k in var.env : k => {
      number = google_project.net-proj[k].number,
      name   = google_project.net-proj[k].name,
      id     = google_project.net-proj[k].id
    }
  }
}

output "backend_projects" {
  value = {
    for k in var.env : k => {
      number = google_project.backend-proj[k].number,
      name   = google_project.backend-proj[k].name,
      id     = google_project.backend-proj[k].id
    }
  }
}
output "frontend_projects" {
  value = {
    for k in var.env : k => {
      number = google_project.frontend-proj[k].number,
      name   = google_project.frontend-proj[k].name,
      id     = google_project.frontend-proj[k].id
    }
  }
}
