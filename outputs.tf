output "dns_name" {
  value = {
    for k in var.env : k => [
      for i in setproduct([module.networking.dns_zone[k].dns_name], module.networking.name_servers[k]) :
      replace(join(" NS ", i), ".${var.organization.domain}.", "")
    ]
  }
}

output "app_name" {
  value = module.frontend.app_name
}
