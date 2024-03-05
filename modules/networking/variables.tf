variable "organization" {
  description = "Organization details."
  type = object({
    customer_id = string
    domain      = string
    id          = number
  })
}

variable "region" {
  description = "Region to host resources"
  type        = string
  default     = "europe-west1"
}

variable "app" {
  description = "App name"
  type        = string
}

variable "env" {
  description = "List all of the environments inside the app"
  type        = list(string)
}

variable "subnets" {
  description = "Map of subnet names and CIDR"
  type        = map(map(string))
}

variable "network_projects" {
  description = "Network project numbers"
  type        = map(map(string))
}

variable "backend_projects" {
  description = "Backend project numbers"
  type        = map(map(string))
}

variable "frontend_projects" {
  description = "Frontend project numbers"
  type        = map(map(string))
}
