# This module creates the folders, the projects, and activates the
# project services.
module "infrastructure" {
  source          = "./modules/infrastructure"
  organization    = var.organization
  billing_account = var.billing_account
  region          = var.region
  app             = var.app
  env             = var.env
}

# The google provider makes an asyncronous system call to activate APIs,
# so it exits with success when the APIs are often still inactive.
# So, terraform goes on creating other resources and fails.
# As a workaround, we use this resource that sleeps for some time, and
# set the other modules to depend on it. In this time hopefully the APIs
# have time to fully activate.
# 300s is a tad conservative, internet says that 120s are ok, change it at your risk.
resource "time_sleep" "wait_api" {
  depends_on      = [module.infrastructure]
  create_duration = "300s"
}

# This module creates for every env:
# - the VPC and its subnets, and shares it with the service projects
# - some firewall rules (80/tcp from all, 22/tcp from IAP ranges)
# - the cloud router and NAT gateway
# - the DNS zone
module "networking" {
  source            = "./modules/networking"
  organization      = var.organization
  region            = var.region
  app               = var.app
  env               = var.env
  subnets           = var.subnets
  network_projects  = module.infrastructure.network_projects
  backend_projects  = module.infrastructure.backend_projects
  frontend_projects = module.infrastructure.frontend_projects
  depends_on        = [time_sleep.wait_api]
}

# This module creates for every env:
# - The backend MIG and autoscaling
# - an apache docker on every instance
# - a TCP Internal Load Balancer
module "backend" {
  source           = "./modules/backend"
  region           = var.region
  app              = var.app
  env              = var.env
  network_projects = module.infrastructure.network_projects
  backend_projects = module.infrastructure.backend_projects
  subnet_id        = module.networking.subnet_id
  user-data        = file("cloud-init/backend.init")
  depends_on       = [time_sleep.wait_api]
}

# Generate the user data from a template. Ugly? yes.
# Less ugly than the other solutions? Also
# We work by successive approximations to at least decent code.
locals {
  frontend-user-data = {
    for k in var.env : k => templatefile(
      "cloud-init/frontend.tpl",
      { be_ip = module.backend.backend_ip[k] }
    )
  }
}

# This module creates for every env:
# - the frontend MIG and autoscaling
# - an haproxy docker on every instance, uses the ILB from the backend
#   project as backend
# - a Global HTTP/HTTPS load balancer 
# - an HTTPS certificate using Certificate Manager, validated using DNS 
module "frontend" {
  source            = "./modules/frontend"
  region            = var.region
  app               = var.app
  env               = var.env
  network_projects  = module.infrastructure.network_projects
  frontend_projects = module.infrastructure.frontend_projects
  subnet_id         = module.networking.subnet_id
  dns_zone          = module.networking.dns_zone
  be_ip             = module.backend.backend_ip
  user-data         = local.frontend-user-data
  depends_on        = [time_sleep.wait_api]
}
