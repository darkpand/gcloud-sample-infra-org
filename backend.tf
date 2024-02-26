locals {
  backend_project_services = [
    "compute.googleapis.com"
  ]
}

# Create the BE project and activate some APIs
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

# Connect to the Shared VPC in the network project
resource "google_compute_shared_vpc_service_project" "example-backend-service-project" {
  host_project    = google_project.example-net-proj.name
  service_project = google_project.example-backend-proj.name
}

# Instance Group section

# Create an SA for the MIG instances
resource "google_service_account" "example-backend-mig-sa" {
  project      = google_project.example-backend-proj.name
  account_id   = "${var.prefix}-be-mig-sa"
  display_name = "Backend MIG SA"
}

# Instance template: here we define all the options of the instances in the MIG.
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
  # here we take the cloud-init from a file. It creates the systemd unit that launches the apache docker
  metadata = {
    user-data              = file("cloud-init/backend.init")
    google-logging-enabled = true
    enable-oslogin         = true
  }
  tags = [
    "http"
  ]
  # we use Container Optimized OS from Google
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

# Create the instance group manager, that replaces/add/remove instances from the MIG when triggered
# (from health checks, the autoscaler, or external factors like instance deletion)
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
    max_surge_fixed       = 3
    max_unavailable_fixed = 0

  }
  auto_healing_policies {
    health_check      = google_compute_health_check.example-backend-healthcheck.id
    initial_delay_sec = 120
  }
}

# Check if an http request for / on port 80 gives a 2xx code
# it's best practice to change the path with a specific one configured on the server
resource "google_compute_health_check" "example-backend-healthcheck" {
  project = google_project.example-backend-proj.name
  name    = "httpd-be-hc"
  http_health_check {
    port               = 80
    port_specification = "USE_FIXED_PORT"
    request_path       = "/"
  }
}

# the autoscaler decides the desired instance count based on its policies, in this case
# a simple metric of 90% cpu usage, and triggers the instance group manager
resource "google_compute_region_autoscaler" "example-backend-autoscaler" {
  project = google_project.example-backend-proj.name
  region  = var.region
  name    = "httpd-be"
  target  = google_compute_region_instance_group_manager.example-backend-instance-group-manager.id
  autoscaling_policy {
    max_replicas    = 10
    min_replicas    = 1
    cooldown_period = 60
    cpu_utilization {
      target = 0.9
    }
  }
}

# Load Balancer Section

# The backend service, to attach the MIG to the balancer
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

# Forwarding rule is the front component of the ILB
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

