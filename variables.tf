variable "prefix" {
  description = "Prefix for all the resources that need differentiation"
  type        = string
  default     = "darkpand01"
}

variable "region" {
  description = "Region to host resources"
  type        = string
  default     = "europe-west1"
}

variable "subnets" {
  description = "Map of subnet names and CIDR"
  type        = map(string)
  default = {
    example-backend  = "172.16.0.0/24"
    example-frontend = "172.16.1.0/24"
  }
}

