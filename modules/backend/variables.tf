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

variable "backend_projects" {
  description = "Backend project numbers"
  type        = map(map(string))
}

variable "subnet_id" {
  description = "VPC and subnet ids"
  type        = map(map(string))
}

variable "user-data" {
  description = "content of user-data for image template"
  type        = any
}
