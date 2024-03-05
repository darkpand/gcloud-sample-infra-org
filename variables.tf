variable "region" {
  description = "Region to host resources"
  type        = string
  default     = "europe-west1"
}

variable "app" {
  description = "Prefix for all the resources that need differentiation"
  type        = string
  default     = "darkpand04"
}

variable "env" {
  description = "List all of the environments inside the app"
  type        = list(string)
  default     = ["t10"]
}
variable "subnets" {
  description = "Map of subnet names and CIDR"
  type        = map(map(string))
  default = {
    t10 = {
      backend  = "172.16.0.0/24"
      frontend = "172.16.1.0/24"
    }
    taa = {
      backend  = "172.16.2.0/24"
      frontend = "172.16.3.0/24"
    }
  }
}

