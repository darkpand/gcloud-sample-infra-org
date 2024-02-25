locals {
  backend_project_services = [
    "compute.googleapis.com"
  ]
}

# inserire permesso compute.instances.create per 634873820391@cloudservices.gserviceaccount.com
resource "google_project" "example-backend-proj" {
  name            = "${var.prefix}-example-backend"
  project_id      = "${var.prefix}-example-backend"
  folder_id       = google_folder.backend-folder.name
  billing_account = var.billing_account
}

resource "google_project_service" "example-backend-services" {
  for_each = toset(local.backend_project_services)
  project  = google_project.example-backend-proj.id
  service  = each.key
}

resource "google_compute_shared_vpc_service_project" "example-backend-service-project" {
  host_project    = google_project.example-net-proj.name
  service_project = google_project.example-backend-proj.name
}

resource "google_service_account" "example-backend-mig-sa" {
  project      = google_project.example-backend-proj.name
  account_id   = "${var.prefix}-be-mig-sa"
  display_name = "Backend MIG SA"
}

resource "google_compute_instance_template" "example-backend-instance-template" {
  project     = google_project.example-backend-proj.name
  name_prefix = "${var.prefix}-httpd-be-"
  region      = var.region
  network_interface {
    network            = google_compute_network.example-net-vpc.id
    subnetwork         = google_compute_subnetwork.example-net-subnet["example-backend"].id
    subnetwork_project = google_project.example-net-proj.name
  }
  labels = {
    "mig-name" = "httpd-be"
  }
  machine_type = "e2-micro"
  metadata = {
    user-data              = file("cloud-init/backend.init")
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
    email  = google_service_account.example-backend-mig-sa.email
    scopes = ["cloud-platform"]
  }
  lifecycle { create_before_destroy = true }
}

resource "google_compute_region_instance_group_manager" "example-backend-instance-group-manager" {
  project            = google_project.example-backend-proj.name
  name               = "httpd-be"
  region             = var.region
  base_instance_name = "httpd-be"
  version {
    instance_template = google_compute_instance_template.example-backend-instance-template.id
    name              = google_compute_instance_template.example-backend-instance-template.name
  }
  named_port {
    name = "http"
    port = 80
  }
  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_unavailable_fixed = 3
  }
  auto_healing_policies {
    health_check      = google_compute_health_check.example-backend-healthcheck.id
    initial_delay_sec = 120
  }
}

resource "google_compute_health_check" "example-backend-healthcheck" {
  project = google_project.example-backend-proj.name
  name    = "httpd-be-hc"
  http_health_check {
    port_name          = "http"
    port_specification = "USE_NAMED_PORT"
    request_path       = "/"
  }
}

resource "google_compute_region_autoscaler" "example-backend-autoscaler" {
  project = google_project.example-backend-proj.name
  region  = var.region
  name    = "httpd-be"
  target  = google_compute_region_instance_group_manager.example-backend-instance-group-manager.id
  autoscaling_policy {
    max_replicas    = 5
    min_replicas    = 1
    cooldown_period = 60
    cpu_utilization {
      target = 0.5
    }
  }
}

resource "google_compute_region_backend_service" "example-backend-service" {
  project               = google_project.example-backend-proj.name
  name                  = "httpd-be"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_health_check.example-backend-healthcheck.self_link]
  network               = google_compute_network.example-net-vpc.id
  protocol              = "TCP"
  failover_policy {
    drop_traffic_if_unhealthy = true
  }
  backend {
    group = google_compute_region_instance_group_manager.example-backend-instance-group-manager.instance_group
  }
}

resource "google_compute_forwarding_rule" "example-backend-forwarding-rule" {
  project               = google_project.example-backend-proj.name
  name                  = "httpd-be-fwrule"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  network               = google_compute_network.example-net-vpc.id
  subnetwork            = google_compute_subnetwork.example-net-subnet["example-backend"].id
  ip_protocol           = "TCP"
  ports                 = [80]
  backend_service       = google_compute_region_backend_service.example-backend-service.self_link
}

