# Mesh subnet-router on a VM in the spoke Private Network (replaces the Flux pod).
#
# Why a VM, not a k8s pod: the router must work BEFORE the cluster is usable and
# survive a broken cluster (real break-glass). It advertises:
#   - the PN CIDR        -> reach RDB, the internal Traefik LB, node IPs over mesh
#   - the Kapsule API /32 -> reach the (public, ACL'd) API over mesh; the request
#                            egresses via the spoke Public Gateway, whose IP is
#                            allowlisted in scaleway_k8s_acl. So kubectl works on
#                            the tailnet without pinning your roaming laptop IP.
#
# NO public IP by default (full isolation, like the Kapsule nodes): the Public
# Gateway pushes a default route via DHCP, so egress + Headscale registration +
# subnet-routed kubectl all go out the gateway, SNAT'd to the gateway's public IP
# (the IP that is allow-listed in scaleway_k8s_acl). A single default route means
# no asymmetric-routing trap. A VM that is BOTH on the gateway'd PN AND has its
# own public IP gets two fighting default routes and breaks (inbound + egress) —
# the same problem that forced Headscale to be public-ONLY. Leave public_ip_id
# empty unless you have a specific reason and have handled the route conflict.

variable "name" {
  type    = string
  default = "mesh-router"
}
variable "private_network_id" { type = string }
variable "public_ip_id" {
  type        = string
  default     = ""
  description = "Optional ID of a scaleway_instance_ip to attach. Leave empty (default) for a private, gateway-egress router (recommended). Attaching a public IP to a VM on a gateway'd PN causes a default-route conflict — see the header comment."
}
variable "pn_cidr" {
  type        = string
  description = "Spoke PN CIDR advertised into the tailnet."
}
variable "apiserver_url" {
  type        = string
  description = "Kapsule API URL; its host is resolved at boot and advertised as a /32."
}
variable "headscale_url" {
  type        = string
  description = "Headscale control-plane URL, e.g. https://mesh.example.com."
}
variable "headscale_authkey" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Headscale pre-auth key. Empty = install tailscale but don't register yet (register once Headscale has a real FQDN + key)."
}
variable "ssh_public_key" { type = string }
variable "gateway_ip" {
  type        = string
  default     = ""
  description = "Public Gateway's PN IP (the spoke's default-route next hop). A PN-only instance does NOT reliably auto-install the gateway default route (Scaleway configures the primary NIC as if it expects public DHCP), so we install it explicitly. Empty = rely on DHCP (only works when the PN is a secondary NIC, i.e. alongside a public IP)."
}
variable "instance_type" {
  type    = string
  default = "PLAY2-MICRO" # cost-optimized family (has default quota)
}
variable "tags" {
  type    = list(string)
  default = []
}

resource "scaleway_instance_security_group" "this" {
  name                    = "sg-${var.name}"
  inbound_default_policy  = "drop" # no inbound needed; tailscale is outbound + DERP-relayed
  outbound_default_policy = "accept"
  tags                    = var.tags
}

resource "scaleway_instance_server" "this" {
  name  = "vm-${var.name}"
  type  = var.instance_type
  image = "ubuntu_jammy"
  # Private by default: no public IP. The gateway's DHCP-pushed default route
  # gives egress (Headscale registration, image pulls) and is the SNAT path for
  # subnet-routed kubectl traffic. enable_dynamic_ip stays false so Scaleway does
  # not hand out an ephemeral public IP (which would re-introduce the dual-default
  # route conflict). Set public_ip_id only if you deliberately want a public IP.
  ip_id             = var.public_ip_id != "" ? var.public_ip_id : null
  enable_dynamic_ip = false
  security_group_id = scaleway_instance_security_group.this.id
  tags              = var.tags

  private_network {
    pn_id = var.private_network_id
  }

  user_data = {
    cloud-init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      ssh_public_key    = var.ssh_public_key
      pn_cidr           = var.pn_cidr
      apiserver_url     = var.apiserver_url
      headscale_url     = var.headscale_url
      headscale_authkey = var.headscale_authkey
      hostname          = var.name
      gateway_ip        = var.gateway_ip
    })
  }
}

output "server_id" { value = scaleway_instance_server.this.id }
