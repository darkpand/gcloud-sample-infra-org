variable "region" {
  description = "Region to host resources"
  type        = string
  default     = "europe-west1"
}

variable "app" {
  description = "Prefix for all the resources that need differentiation"
  type        = string
  default     = "darkpand02"
}

variable "env" {
  description = "List all of the environments inside the app"
  type        = list(string)
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
  }
}

