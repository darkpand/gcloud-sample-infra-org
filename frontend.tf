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

resource "google_service_account" "example-frontend-mig-sa" {
  project      = google_project.example-frontend-proj.name
  account_id   = "${var.prefix}-fe-mig-sa"
  display_name = "Frontend MIG SA"
}

resource "google_compute_instance_template" "example-frontend-instance-template" {
  project     = google_project.example-frontend-proj.name
  name_prefix = "${var.prefix}-haproxy-fe-"
  region      = var.region
  network_interface {
    network            = google_compute_network.example-net-vpc.id
    subnetwork         = google_compute_subnetwork.example-net-subnet["example-frontend"].id
    subnetwork_project = google_project.example-net-proj.name
  }
  labels = {
    "mig-name" = "haproxy-fe"
  }
  machine_type = "e2-micro"
  metadata = {
    user-data              = templatefile("cloud-init/frontend.tpl", { be_ip = google_compute_forwarding_rule.example-backend-forwarding-rule.ip_address })
    google-logging-enabled = true
    enable-oslogin         = true
  }
  tags = [
    "http"
  ]
  disk {
    auto_delete  = true
    boot         = true
    source_image = "projects/cos-cloud/global/images/family/cos-stable"
  }
  service_account {
    email  = google_service_account.example-frontend-mig-sa.email
    scopes = ["cloud-platform"]
  }
  lifecycle { create_before_destroy = true }
}

resource "google_compute_region_instance_group_manager" "example-frontend-instance-group-manager" {
  project            = google_project.example-frontend-proj.name
  name               = "haproxy-fe"
  region             = var.region
  base_instance_name = "haproxy-fe"
  version {
    instance_template = google_compute_instance_template.example-frontend-instance-template.id
    name              = google_compute_instance_template.example-frontend-instance-template.name
  }
  named_port {
    name = "http"
    port = 80
  }
  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3
    max_unavailable_fixed = 0

  }
  auto_healing_policies {
    health_check      = google_compute_health_check.example-frontend-healthcheck.id
    initial_delay_sec = 120
  }
}

resource "google_compute_health_check" "example-frontend-healthcheck" {
  project = google_project.example-frontend-proj.name
  name    = "haproxy-fe-hc"
  http_health_check {
    port               = 80
    port_specification = "USE_FIXED_PORT"
    request_path       = "/"
  }
}

resource "google_compute_region_autoscaler" "example-frontend-autoscaler" {
  project = google_project.example-frontend-proj.name
  region  = var.region
  name    = "haproxy-fe"
  target  = google_compute_region_instance_group_manager.example-frontend-instance-group-manager.id
  autoscaling_policy {
    max_replicas    = 10
    min_replicas    = 1
    cooldown_period = 60
    cpu_utilization {
      target = 0.9
    }
  }
}

resource "google_compute_global_address" "example-frontend-external-address" {
  project      = google_project.example-frontend-proj.name
  name         = "haproxy-fe-extaddr"
  address_type = "EXTERNAL"
  description  = "FE MIG External Load Balancer address"
}

resource "google_compute_url_map" "example-frontend-urlmap" {
  project         = google_project.example-frontend-proj.name
  name            = "haproxy-fe-urlmap"
  default_service = google_compute_backend_service.example-frontend-service.id
}

resource "google_compute_target_http_proxy" "example-frontend-http-proxy" {
  project = google_project.example-frontend-proj.name
  name    = "haproxy-fe-http-proxy"
  url_map = google_compute_url_map.example-frontend-urlmap.id
}


resource "google_compute_backend_service" "example-frontend-service" {
  project               = google_project.example-frontend-proj.name
  name                  = "haproxy-fe"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.example-frontend-healthcheck.self_link]
  protocol              = "HTTP"
  backend {
    group = google_compute_region_instance_group_manager.example-frontend-instance-group-manager.instance_group
  }
}

resource "google_compute_global_forwarding_rule" "example-frontend-forwarding-rule" {
  project               = google_project.example-frontend-proj.name
  name                  = "haproxy-fe-fwrule"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  ip_address            = google_compute_global_address.example-frontend-external-address.id
  target                = google_compute_target_http_proxy.example-frontend-http-proxy.id
}
