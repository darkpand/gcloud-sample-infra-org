locals {
  frontend_api = [
    "compute.googleapis.com",
    "certificatemanager.googleapis.com"
  ]
  frontend-proj-services = {
    for tuple in setproduct(var.env, local.frontend_api) :
    "${tuple[0]}-${regex("^[a-z]*", tuple[1])}" =>
    { env = tuple[0], service = tuple[1] }
  }
  app_fqdn = "app.${trim(google_dns_managed_zone.net-dns-zone["dev"].dns_name, ".")}"

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

# Connect to the Shared VPC in the network project
resource "google_compute_shared_vpc_service_project" "frontend-service-project" {
  for_each        = toset(var.env)
  host_project    = google_project.net-proj[each.key].name
  service_project = google_project.frontend-proj[each.key].name
}

# Create an SA for the MIG instances
resource "google_service_account" "frontend-mig-sa" {
  for_each     = toset(var.env)
  project      = google_project.frontend-proj[each.key].name
  account_id   = "${var.app}-${each.key}-fe-mig-sa"
  display_name = "Frontend MIG SA - ${each.key} env"
}

# Instance template: here we define all the options of the instances in the MIG.
resource "google_compute_instance_template" "frontend-instance-template" {
  for_each    = toset(var.env)
  project     = google_project.frontend-proj[each.key].name
  name_prefix = "${var.app}-${each.key}-haproxy-fe-"
  region      = var.region
  network_interface {
    network            = google_compute_network.net-vpc[each.key].id
    subnetwork         = google_compute_subnetwork.net-subnet-fe[each.key].id
    subnetwork_project = google_project.net-proj[each.key].name
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
      { be_ip = google_compute_forwarding_rule.backend-forwarding-rule[each.key].ip_address }
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
    email  = google_service_account.frontend-mig-sa[each.key].email
    scopes = ["cloud-platform"]
  }
  lifecycle { create_before_destroy = true }
}

# Create the instance group manager, that replaces/add/remove instances from the MIG when triggered
# (from health checks, the autoscaler, or external factors like instance deletion)
resource "google_compute_region_instance_group_manager" "frontend-instance-group-manager" {
  for_each           = toset(var.env)
  project            = google_project.frontend-proj[each.key].name
  name               = "haproxy-fe"
  region             = var.region
  base_instance_name = "haproxy-fe"
  version {
    instance_template = google_compute_instance_template.frontend-instance-template[each.key].id
    name              = google_compute_instance_template.frontend-instance-template[each.key].name
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
    health_check      = google_compute_health_check.frontend-healthcheck[each.key].id
    initial_delay_sec = 120
  }
}

# Check if an http request for / on port 80 gives a 2xx code
# it's best practice to change the path with a specific one configured on the server
resource "google_compute_health_check" "frontend-healthcheck" {
  for_each = toset(var.env)
  project  = google_project.frontend-proj[each.key].name
  name     = "haproxy-fe-hc"
  http_health_check {
    port               = 80
    port_specification = "USE_FIXED_PORT"
    request_path       = "/"
  }
}

# the autoscaler decides the desired instance count based on its policies, in this case
# a simple metric of 90% cpu usage, and triggers the instance group manager
resource "google_compute_region_autoscaler" "frontend-autoscaler" {
  for_each = toset(var.env)
  project  = google_project.frontend-proj[each.key].name
  region   = var.region
  name     = "haproxy-fe"
  target   = google_compute_region_instance_group_manager.frontend-instance-group-manager[each.key].id
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
resource "google_compute_global_address" "frontend-external-address" {
  for_each     = toset(var.env)
  project      = google_project.frontend-proj[each.key].name
  name         = "haproxy-fe-extaddr"
  address_type = "EXTERNAL"
  description  = "FE MIG External Load Balancer address - ${each.key} env"
}

# The urlmap is used to route traffic based on urls and headers;
# to rewrite urls and headers; to generate redirects; and more.
resource "google_compute_url_map" "frontend-urlmap" {
  for_each        = toset(var.env)
  project         = google_project.frontend-proj[each.key].name
  name            = "haproxy-fe-urlmap"
  default_service = google_compute_backend_service.frontend-service[each.key].id
}

# This is a L7 load balancer so it has a proxy component
resource "google_compute_target_http_proxy" "frontend-http-proxy" {
  for_each = toset(var.env)
  project  = google_project.frontend-proj[each.key].name
  name     = "haproxy-fe-http-proxy"
  url_map  = google_compute_url_map.frontend-urlmap[each.key].id
}

resource "google_compute_target_https_proxy" "frontend-https-proxy" {
  for_each        = toset(var.env)
  project         = google_project.frontend-proj[each.key].name
  name            = "haproxy-fe-https-proxy"
  url_map         = google_compute_url_map.frontend-urlmap[each.key].id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.frontend-certmap[each.key].id}"
}

# The backend service, to attach the MIG to the balancer
resource "google_compute_backend_service" "frontend-service" {
  for_each              = toset(var.env)
  project               = google_project.frontend-proj[each.key].name
  name                  = "haproxy-fe"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.frontend-healthcheck[each.key].self_link]
  protocol              = "HTTP"
  backend {
    group = google_compute_region_instance_group_manager.frontend-instance-group-manager[each.key].instance_group
  }
}

# Forwarding rule is the front component of the GLB
resource "google_compute_global_forwarding_rule" "frontend-forwarding-rule-http" {
  for_each              = toset(var.env)
  project               = google_project.frontend-proj[each.key].name
  name                  = "haproxy-fe-fwrule-http"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  ip_address            = google_compute_global_address.frontend-external-address[each.key].id
  target                = google_compute_target_http_proxy.frontend-http-proxy[each.key].id
}
resource "google_compute_global_forwarding_rule" "frontend-forwarding-rule-https" {
  for_each              = toset(var.env)
  project               = google_project.frontend-proj[each.key].name
  name                  = "haproxy-fe-fwrule-https"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  ip_address            = google_compute_global_address.frontend-external-address[each.key].id
  target                = google_compute_target_https_proxy.frontend-https-proxy[each.key].id
}

# Certificate Manager Section

# Create a certificate map, used by the https proxy
resource "google_certificate_manager_certificate_map" "frontend-certmap" {
  for_each    = toset(var.env)
  project     = google_project.frontend-proj[each.key].name
  name        = "fe-certmap"
  description = "Certificate map for ${local.app_fqdn}"
}

# add a certificate entry to the map using...
resource "google_certificate_manager_certificate_map_entry" "frontend-certmap-entry" {
  for_each     = toset(var.env)
  project      = google_project.frontend-proj[each.key].name
  name         = "certmap-entry"
  description  = "Cert Manager map entry for ${local.app_fqdn}"
  map          = google_certificate_manager_certificate_map.frontend-certmap[each.key].name
  certificates = [google_certificate_manager_certificate.frontend-certmap-certificate[each.key].id]
  matcher      = "PRIMARY"
}

# ...this certificate. Authorize it using...
resource "google_certificate_manager_certificate" "frontend-certmap-certificate" {
  for_each    = toset(var.env)
  project     = google_project.frontend-proj[each.key].name
  name        = "fe-certmap-certificate"
  description = "Cert Manager certificate for ${local.app_fqdn}"
  scope       = "DEFAULT"
  managed {
    domains            = [local.app_fqdn]
    dns_authorizations = [google_certificate_manager_dns_authorization.frontend-dns-auth[each.key].id]
  }
}

# ...this dns authorization
resource "google_certificate_manager_dns_authorization" "frontend-dns-auth" {
  for_each    = toset(var.env)
  project     = google_project.frontend-proj[each.key].name
  name        = "fe-dns-auth"
  description = "Cert Manager authorization for ${local.app_fqdn}"
  domain      = local.app_fqdn
}

# The dns record for dns auth. We put the entry on the same project as the dns zone, because
# Cloud DNS is a bit grumpy about cross-project dns.
resource "google_dns_record_set" "dns-auth-entry" {
  for_each     = toset(var.env)
  project      = google_project.net-proj[each.key].name
  name         = google_certificate_manager_dns_authorization.frontend-dns-auth[each.key].dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.frontend-dns-auth[each.key].dns_resource_record[0].type
  rrdatas      = [google_certificate_manager_dns_authorization.frontend-dns-auth[each.key].dns_resource_record[0].data]
  managed_zone = google_dns_managed_zone.net-dns-zone[each.key].name
  ttl          = 300
}

# The dns record for our app.
resource "google_dns_record_set" "dns-app-entry" {
  for_each     = toset(var.env)
  project      = google_project.net-proj[each.key].name
  name         = "app.${google_dns_managed_zone.net-dns-zone[each.key].dns_name}"
  managed_zone = google_dns_managed_zone.net-dns-zone[each.key].name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.frontend-external-address[each.key].address]
}
