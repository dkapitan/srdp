# Hub VPC + Private Network (connectivity Project). Hosts the shared egress
# Public Gateway, the Headscale mesh control plane, and is the peering target for
# every spoke VPC (via scaleway_vpc_connector, created from the spokes).
#
# Scaleway note: a VPC is regional and per-Project. `enable_routing` lets the
# VPC route between its own Private Networks and is required before VPC
# connectors (cross-VPC peering) can carry traffic.

variable "name_prefix" { type = string }
variable "pn_subnet_cidr" {
  type        = string
  default     = "10.0.1.0/24"
  description = "Hub Private Network subnet (Headscale + gateway live here)."
}
variable "tags" {
  type    = list(string)
  default = []
}

resource "scaleway_vpc" "this" {
  name           = "vpc-${var.name_prefix}"
  enable_routing = true # required for inter-PN routing + VPC connectors
  tags           = var.tags
}

resource "scaleway_vpc_private_network" "this" {
  name   = "pn-${var.name_prefix}"
  vpc_id = scaleway_vpc.this.id
  tags   = var.tags

  ipv4_subnet {
    subnet = var.pn_subnet_cidr
  }
}

output "vpc_id" { value = scaleway_vpc.this.id }
output "vpc_name" { value = scaleway_vpc.this.name }
output "private_network_id" { value = scaleway_vpc_private_network.this.id }
output "pn_subnet_cidr" { value = var.pn_subnet_cidr }
