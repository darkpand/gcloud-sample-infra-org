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

variable "network_projects" {
  description = "Network project numbers"
  type        = map(map(string))
}

variable "frontend_projects" {
  description = "Frontend project numbers"
  type        = map(map(string))
}

variable "subnet_id" {
  description = "VPC and subnet ids"
  type        = map(map(string))
}

variable "dns_zone" {
  description = "DNS zone info"
  type        = map(map(string))
}

#variable "user-data" {
#  description = "content of user-data for image template"
#  type        = any
#}
variable "be_ip" {
  type = map(string)
}
