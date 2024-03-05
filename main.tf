module "infrastructure" {
  source          = "./modules/infrastructure"
  organization    = var.organization
  billing_account = var.billing_account
  region          = var.region
  app             = var.app
  env             = var.env
}

resource "time_sleep" "wait_api" {
  depends_on      = [module.infrastructure]
  create_duration = "300s"
}

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
  #user-data = templatefile(
  #  "cloud-init/frontend.tpl",
  #  { be_ip = module.backend.backend_ip[each.key] }
  #)
  depends_on = [time_sleep.wait_api]
}
