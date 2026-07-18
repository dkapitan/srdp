# HUB. project_id, prefix, region, zone come from .env via the Justfile.

# Hub Private Network subnet. Keep distinct from every spoke's pn_vpc_cidr.
pn_subnet_cidr = "10.0.1.0/24"

# Headscale mesh control plane (public). Empty => sslip.io name derived from its
# public IP (no owned domain needed). Set a real FQDN only if you own one.
headscale_fqdn = ""

# SSH public key for break-glass access to the Headscale VM.
headscale_ssh_public_key   = "ssh-ed25519 AAAA_REPLACE_WITH_YOUR_PUBLIC_KEY ops@example.com"
headscale_allowed_ssh_cidr = "203.0.113.0/24" # REPLACE with your egress IP/VPN CIDR (this is a non-routable placeholder)
