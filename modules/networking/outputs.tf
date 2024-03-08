output "subnet_id" {
  value = {
    for k in var.env : k => {
      vpc_id   = google_compute_network.net-vpc[k].id,
      backend  = google_compute_subnetwork.net-subnet-be[k].id
      frontend = google_compute_subnetwork.net-subnet-fe[k].id
    }
  }
}

output "dns_zone" {
  value = {
    for k in var.env : k => {
      name     = google_dns_managed_zone.net-dns-zone[k].name
      dns_name = google_dns_managed_zone.net-dns-zone[k].dns_name
    }
  }
}
output "name_servers" {
  value = {
    for k in var.env : k => google_dns_managed_zone.net-dns-zone[k].name_servers
  }
}
