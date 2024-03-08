variable "region" {
  description = "Region to host resources"
  type        = string
  default     = "europe-west1"
}

variable "app" {
  description = "Prefix for all the resources that need differentiation"
  type        = string
  default     = "demoapp"
}

# Here we're creating only a dev environment, if you didn't ask google
# to raise your billable projects quota. I've put some commented examples
# if you want to create more than one env.
variable "env" {
  description = "List all of the environments inside the app"
  type        = list(string)
  #default     = ["dev", "prod"]
  default     = ["dev"]
}
variable "subnets" {
  description = "Map of subnet names and CIDR"
  type        = map(map(string))
  default = {
    dev = {
      backend  = "172.16.0.0/24"
      frontend = "172.16.1.0/24"
    }
    #prod = {
    #  backend  = "172.16.2.0/24"
    #  frontend = "172.16.3.0/24"
    #}
  }
}

