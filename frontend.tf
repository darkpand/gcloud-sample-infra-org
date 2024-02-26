locals {
  frontend_project_services = [
    "compute.googleapis.com",
    "certificatemanager.googleapis.com"
  ]
  app_fqdn = "app-${var.prefix}.${trim(google_dns_managed_zone.example-zone.dns_name, ".")}"
}

# Create the FE project and activate some APIs
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

# Connect to the Shared VPC in the network project
resource "google_compute_shared_vpc_service_project" "example-frontend-service-project" {
  host_project    = google_project.example-net-proj.name
  service_project = google_project.example-frontend-proj.name
}

# Create an SA for the MIG instances
resource "google_service_account" "example-frontend-mig-sa" {
  project      = google_project.example-frontend-proj.name
  account_id   = "${var.prefix}-fe-mig-sa"
  display_name = "Frontend MIG SA"
}

# Instance template: here we define all the options of the instances in the MIG.
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
  # here we use a template to generate the cloud-init. It :
  # creates the haproxy config file in the stateful partition (dir haproxy/) 
  # creates the systemd unit that launches the haproxy docker and mounts the haproxy/ dir inside of it
  metadata = {
    user-data = templatefile(
      "cloud-init/frontend.tpl",
      { be_ip = google_compute_forwarding_rule.example-backend-forwarding-rule.ip_address }
    )
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
    email  = google_service_account.example-frontend-mig-sa.email
    scopes = ["cloud-platform"]
  }
  lifecycle { create_before_destroy = true }
}

# Create the instance group manager, that replaces/add/remove instances from the MIG when triggered
# (from health checks, the autoscaler, or external factors like instance deletion)
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

# Check if an http request for / on port 80 gives a 2xx code
# it's best practice to change the path with a specific one configured on the server
resource "google_compute_health_check" "example-frontend-healthcheck" {
  project = google_project.example-frontend-proj.name
  name    = "haproxy-fe-hc"
  http_health_check {
    port               = 80
    port_specification = "USE_FIXED_PORT"
    request_path       = "/"
  }
}

# the autoscaler decides the desired instance count based on its policies, in this case
# a simple metric of 90% cpu usage, and triggers the instance group manager
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

# Load Balancer Section

# Reserve a fixed public IP
resource "google_compute_global_address" "example-frontend-external-address" {
  project      = google_project.example-frontend-proj.name
  name         = "haproxy-fe-extaddr"
  address_type = "EXTERNAL"
  description  = "FE MIG External Load Balancer address"
}

# The urlmap is used to route traffic based on urls and headers;
# to rewrite urls and headers; to generate redirects; and more.
resource "google_compute_url_map" "example-frontend-urlmap" {
  project         = google_project.example-frontend-proj.name
  name            = "haproxy-fe-urlmap"
  default_service = google_compute_backend_service.example-frontend-service.id
}

# This is a L7 load balancer so it has a proxy component
resource "google_compute_target_http_proxy" "example-frontend-http-proxy" {
  project = google_project.example-frontend-proj.name
  name    = "haproxy-fe-http-proxy"
  url_map = google_compute_url_map.example-frontend-urlmap.id
}

resource "google_compute_target_https_proxy" "example-frontend-https-proxy" {
  project         = google_project.example-frontend-proj.name
  name            = "haproxy-fe-https-proxy"
  url_map         = google_compute_url_map.example-frontend-urlmap.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.example-certmap.id}"
}

# The backend service, to attach the MIG to the balancer
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

# Forwarding rule is the front component of the GLB
resource "google_compute_global_forwarding_rule" "example-frontend-forwarding-rule-http" {
  project               = google_project.example-frontend-proj.name
  name                  = "haproxy-fe-fwrule-http"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  ip_address            = google_compute_global_address.example-frontend-external-address.id
  target                = google_compute_target_http_proxy.example-frontend-http-proxy.id
}
resource "google_compute_global_forwarding_rule" "example-frontend-forwarding-rule-https" {
  project               = google_project.example-frontend-proj.name
  name                  = "haproxy-fe-fwrule-https"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  ip_address            = google_compute_global_address.example-frontend-external-address.id
  target                = google_compute_target_https_proxy.example-frontend-https-proxy.id
}

# Certificate Manager Section

# Create a certificate map, used by the https proxy
resource "google_certificate_manager_certificate_map" "example-certmap" {
  project     = google_project.example-frontend-proj.name
  name        = "example-certmap"
  description = "Certificate map for ${local.app_fqdn}"
}

# add a certificate entry to the map using...
resource "google_certificate_manager_certificate_map_entry" "example-certmap-entry" {
  project      = google_project.example-frontend-proj.name
  name         = "example-certmap-entry"
  description  = "Cert Manager map entry for ${local.app_fqdn}"
  map          = google_certificate_manager_certificate_map.example-certmap.name
  certificates = [google_certificate_manager_certificate.example-certmap-certificate.id]
  matcher      = "PRIMARY"
}

# ...this certificate. Authorize it using...
resource "google_certificate_manager_certificate" "example-certmap-certificate" {
  project     = google_project.example-frontend-proj.name
  name        = "example-certmap-certificate"
  description = "Cert Manager certificate for ${local.app_fqdn}"
  scope       = "DEFAULT"
  managed {
    domains            = [local.app_fqdn]
    dns_authorizations = [google_certificate_manager_dns_authorization.example-dns-auth.id]
  }
}

# ...this dns authorization
resource "google_certificate_manager_dns_authorization" "example-dns-auth" {
  project     = google_project.example-frontend-proj.name
  name        = "example-dns-auth"
  description = "Cert Manager authorization for ${local.app_fqdn}"
  domain      = local.app_fqdn
}

# The dns record for dns auth. We put the entry on the same project as the dns zone, because
# Cloud DNS is a bit grumpy about cross-project dns.
resource "google_dns_record_set" "example-dns-auth-entry" {
  project      = google_project.example-net-proj.name
  name         = google_certificate_manager_dns_authorization.example-dns-auth.dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.example-dns-auth.dns_resource_record[0].type
  rrdatas      = [google_certificate_manager_dns_authorization.example-dns-auth.dns_resource_record[0].data]
  managed_zone = google_dns_managed_zone.example-zone.name
  ttl          = 300
}

# The dns record for our app.
resource "google_dns_record_set" "example-dns-app-entry" {
  project      = google_project.example-net-proj.name
  name         = "app-${var.prefix}.${google_dns_managed_zone.example-zone.dns_name}"
  managed_zone = google_dns_managed_zone.example-zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.example-frontend-external-address.address]
}
