variable "organization" {
  description = "Organization details."
  type = object({
    customer_id = string
    domain      = string
    id          = number
  })
}

variable "billing_account" {
  type = string
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
