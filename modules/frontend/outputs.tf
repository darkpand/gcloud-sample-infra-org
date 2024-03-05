output "external_address" {
  value = { for k in var.env : k => google_compute_global_address.frontend-external-address[k].address }
}
