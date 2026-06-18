# Hub variables. project_id, prefix, region, zone are injected by the Justfile
# from .env; the rest are set in terraform.tfvars.

variable "project_id" {
  type        = string
  description = "HUB / connectivity Project id."
}

variable "prefix" {
  type        = string
  description = "Org/company short code (lowercase, alphanumeric) used in resource names."
}

variable "region" {
  type    = string
  default = "nl-ams"
}

variable "zone" {
  type        = string
  default     = "nl-ams-1"
  description = "Default AZ. RDB private networking requires the region's default AZ (nl-ams-1)."
}

variable "pn_subnet_cidr" {
  type        = string
  description = "Hub Private Network subnet (a /24 is plenty — only Headscale + the gateway live here). Must not overlap any spoke."
}

variable "headscale_fqdn" {
  type        = string
  default     = ""
  description = "Public DNS name for the Headscale control plane. Empty => derive a sslip.io name from its public IP (no owned domain needed)."
}

variable "headscale_ssh_public_key" {
  type        = string
  description = "SSH public key for break-glass access to the Headscale VM."
}

variable "headscale_allowed_ssh_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Source CIDR allowed to SSH (22) to the Headscale VM. Tighten to your egress IP."
}
