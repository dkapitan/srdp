# Egress Public Gateway — the Scaleway analogue of the Azure Firewall.
#
# Kapsule nodes sit on a Private Network with no public IPs; a Public Gateway
# attached to that PN provides SNAT so they can reach the internet (pull images,
# OS updates, OIDC, etc.). This is L3/L4 NAT only.
#
# DIVERGENCE FROM AZURE: Scaleway has no managed L7 egress firewall (no FQDN
# allow-lists like Azure Firewall application rules). For coarse network-level
# control, attach a scaleway_vpc_acl to the VPC (see envs). FQDN-level egress
# filtering, if required, must run in-cluster (e.g. a forward proxy). Tracked in
# docs/BACKLOG.md.

variable "name_prefix" { type = string }
variable "private_network_id" { type = string }
variable "enable_smtp" {
  type        = bool
  default     = false
  description = "Scaleway blocks SMTP by default on gateways; leave off unless needed."
}
variable "tags" {
  type    = list(string)
  default = []
}

resource "scaleway_vpc_public_gateway_ip" "this" {
  tags = var.tags
}

resource "scaleway_vpc_public_gateway" "this" {
  name            = "pgw-${var.name_prefix}"
  type            = "VPC-GW-S"
  ip_id           = scaleway_vpc_public_gateway_ip.this.id
  enable_smtp     = var.enable_smtp
  bastion_enabled = false
  tags            = var.tags
}

# Attach the gateway to the Private Network and hand out a default route +
# DHCP/DNS to the PN (dynamic NAT for outbound traffic).
resource "scaleway_vpc_gateway_network" "this" {
  gateway_id         = scaleway_vpc_public_gateway.this.id
  private_network_id = var.private_network_id
  enable_masquerade  = true # SNAT: PN -> gateway public IP
  ipam_config {
    push_default_route = true
  }
}

# The gateway's PRIVATE (PN) IP — the default-route next hop for PN members.
# A PN-only mesh-router installs this explicitly (DHCP delivery is unreliable on a
# fresh boot), so the env passes it to modules/mesh-router as gateway_ip.
data "scaleway_ipam_ip" "gateway" {
  resource {
    id   = scaleway_vpc_gateway_network.this.id
    type = "vpc_gateway_network"
  }
  type = "ipv4"
}

output "gateway_id" { value = scaleway_vpc_public_gateway.this.id }
output "public_ip" { value = scaleway_vpc_public_gateway_ip.this.address }
output "gateway_pn_ip" { value = data.scaleway_ipam_ip.gateway.address }
