# Headscale control plane — a small public Instance in the hub Project.
# This is the ONE intentional public endpoint: the mesh coordination server +
# DERP relay. Everything else (Kapsule API ACL, internal Traefik LB, RDB, Object
# Storage) stays private and is reached over the mesh. Caddy terminates TLS
# (auto-ACME) in front of headscale. Identical role to the Azure headscale-vm.

variable "name" {
  type    = string
  default = "headscale"
}
variable "fqdn" {
  type        = string
  default     = ""
  description = "Public DNS name for the control plane. Empty (default) => derive a sslip.io name from the control-plane public IP (no domain to own; Caddy still gets a real Let's Encrypt cert because sslip.io resolves publicly)."
}
variable "ssh_public_key" {
  type        = string
  description = "SSH public key for break-glass admin access."
}
variable "allowed_ssh_cidr" {
  type        = string
  default     = "0.0.0.0/0" # tighten to your office/VPN egress
  description = "Source CIDR allowed to SSH (22)."
}
variable "instance_type" {
  type    = string
  default = "PLAY2-PICO"
}
variable "headscale_version" {
  type    = string
  default = "0.29.0"
}
variable "tags" {
  type    = list(string)
  default = []
}

resource "scaleway_instance_ip" "this" {
  tags = var.tags
}

# sslip.io: "<dashed-ip>.sslip.io" resolves to the IP, so Caddy can get a real
# ACME cert with no owned domain. Override via var.fqdn for a real domain.
locals {
  fqdn = var.fqdn != "" ? var.fqdn : "${replace(scaleway_instance_ip.this.address, ".", "-")}.sslip.io"
}

resource "scaleway_instance_security_group" "this" {
  name                    = "sg-${var.name}"
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  tags                    = var.tags

  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 443
  }
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 80 # ACME HTTP-01 (Caddy)
  }
  inbound_rule {
    action   = "accept"
    protocol = "UDP"
    port     = 3478 # DERP STUN
  }
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 22
    ip_range = var.allowed_ssh_cidr
  }
}

resource "scaleway_instance_server" "this" {
  name              = "vm-${var.name}"
  type              = var.instance_type
  image             = "ubuntu_jammy"
  ip_id             = scaleway_instance_ip.this.id
  security_group_id = scaleway_instance_security_group.this.id
  tags              = var.tags

  # Public-only: NO Private Network. Attaching it to a PN whose Public Gateway
  # pushes a default route breaks inbound to the VM's own public IP (asymmetric
  # routing). Headscale is the single public endpoint; it needs no PN.

  user_data = {
    cloud-init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      fqdn              = local.fqdn
      headscale_version = var.headscale_version
      ssh_public_key    = var.ssh_public_key
    })
  }
}

output "public_ip" { value = scaleway_instance_ip.this.address }
output "fqdn" { value = local.fqdn }
output "server_url" { value = "https://${local.fqdn}" }
