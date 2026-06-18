# Spoke VPC + Private Network. Peers to the hub VPC via a VPC connector and
# routes egress through its own Public Gateway (egress-gateway module, wired at
# env level). Kapsule, RDB and the CI runner all attach to this one PN.

variable "name_prefix" { type = string }
variable "pn_subnet_cidr" {
  type        = string
  description = "Spoke Private Network subnet (nodes, RDB private endpoint, runner)."
}
variable "tags" {
  type    = list(string)
  default = []
}

resource "scaleway_vpc" "this" {
  name           = "vpc-${var.name_prefix}"
  enable_routing = true
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
