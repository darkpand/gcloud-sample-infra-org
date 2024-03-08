output "external_address" {
  value = { for k in var.env : k => google_compute_global_address.frontend-external-address[k].address }
}

output "app_name" {
  value = { for k in var.env : k => google_dns_record_set.dns-app-entry[k].name }
}
