# Instance Group section

# Create an SA for the MIG instances
resource "google_service_account" "backend-mig-sa" {
  for_each     = toset(var.env)
  project      = var.backend_projects[each.key].name
  account_id   = "${var.app}-${each.key}-be-mig-sa"
  display_name = "Backend MIG SA - ${each.key} env"
}

# Instance template: here we define all the options of the instances in the MIG.
resource "google_compute_instance_template" "backend-instance-template" {
  for_each    = toset(var.env)
  project     = var.backend_projects[each.key].name
  name_prefix = "${var.app}-${each.key}-httpd-be-"
  region      = var.region
  network_interface {
    network            = var.subnet_id[each.key].vpc_id
    subnetwork         = var.subnet_id[each.key].backend
    subnetwork_project = var.network_projects[each.key].name
  }
  labels = {
    "mig-name" = "httpd-be"
  }
  machine_type = "e2-micro"
  # here we take the cloud-init from a file. It creates the systemd unit that launches the apache docker
  metadata = {
    user-data              = var.user-data
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
    email  = google_service_account.backend-mig-sa[each.key].email
    scopes = ["cloud-platform"]
  }
  lifecycle { create_before_destroy = true }
}

# Create the instance group manager, that replaces/add/remove instances from the MIG when triggered
# (from health checks, the autoscaler, or external factors like instance deletion)
resource "google_compute_region_instance_group_manager" "backend-instance-group-manager" {
  for_each           = toset(var.env)
  project            = var.backend_projects[each.key].name
  name               = "httpd-be"
  region             = var.region
  base_instance_name = "httpd-be"
  version {
    instance_template = google_compute_instance_template.backend-instance-template[each.key].id
    name              = google_compute_instance_template.backend-instance-template[each.key].name
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
    health_check      = google_compute_health_check.backend-healthcheck[each.key].id
    initial_delay_sec = 120
  }
}

# Check if an http request for / on port 80 gives a 2xx code
# it's best practice to change the path with a specific one configured on the server
resource "google_compute_health_check" "backend-healthcheck" {
  for_each = toset(var.env)
  project  = var.backend_projects[each.key].name
  name     = "httpd-be-hc"
  http_health_check {
    port               = 80
    port_specification = "USE_FIXED_PORT"
    request_path       = "/"
  }
}

# the autoscaler decides the desired instance count based on its policies, in this case
# a simple metric of 90% cpu usage, and triggers the instance group manager
resource "google_compute_region_autoscaler" "backend-autoscaler" {
  for_each = toset(var.env)
  project  = var.backend_projects[each.key].name
  region   = var.region
  name     = "httpd-be"
  target   = google_compute_region_instance_group_manager.backend-instance-group-manager[each.key].id
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
resource "google_compute_region_backend_service" "backend-service" {
  for_each              = toset(var.env)
  project               = var.backend_projects[each.key].name
  name                  = "httpd-be"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_health_check.backend-healthcheck[each.key].self_link]
  network               = var.subnet_id[each.key].vpc_id
  protocol              = "TCP"
  failover_policy {
    drop_traffic_if_unhealthy = true
  }
  backend {
    group = google_compute_region_instance_group_manager.backend-instance-group-manager[each.key].instance_group
  }
}

# Forwarding rule is the front component of the ILB
resource "google_compute_forwarding_rule" "backend-forwarding-rule" {
  for_each              = toset(var.env)
  project               = var.backend_projects[each.key].name
  name                  = "httpd-be-fwrule"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  network               = var.subnet_id[each.key].vpc_id
  subnetwork            = var.subnet_id[each.key].backend
  ip_protocol           = "TCP"
  ports                 = [80]
  backend_service       = google_compute_region_backend_service.backend-service[each.key].self_link
}

