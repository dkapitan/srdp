variable "gcp_project_id" {
  type        = string
  description = "The GCP Project ID to deploy resources into."
}

variable "gcp_region" {
  type        = string
  description = "The GCP region to deploy resources into."
  default     = "europe-west4"
}

variable "gcp_zone" {
  type        = string
  description = "The GCP zone for the VM."
  default     = "europe-west4-a"
}

variable "instance_name" {
  type        = string
  description = "The name for the Compute Engine VM."
  default     = "srdp-main"
}