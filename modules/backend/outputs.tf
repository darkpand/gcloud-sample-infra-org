output "backend_ip" {
  value = { for k in var.env : k => google_compute_forwarding_rule.backend-forwarding-rule[k].ip_address }
}
