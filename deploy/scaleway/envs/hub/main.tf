# Hub / connectivity environment root.
#
# Applies FIRST — spokes peer to its VPC and register against its Headscale
# control plane. Holds the shared Container Registry. Environment-specific values
# come from terraform.tfvars; identity (project_id, prefix, region) is injected
# by the Justfile from .env.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    scaleway = { source = "scaleway/scaleway", version = "~> 2.71" }
    random   = { source = "hashicorp/random", version = "~> 3.6" }
  }
  # Partial config — injected via -backend-config (Justfile / CI). Object Storage
  # is S3-compatible, so the azurerm-equivalent here is the S3 backend.
  backend "s3" {}
}

# Credentials come from SCW_ACCESS_KEY / SCW_SECRET_KEY in the environment.
provider "scaleway" {
  project_id = var.project_id
  region     = var.region
  zone       = var.zone
}

locals {
  name_prefix = "${var.prefix}-hub"
  tags        = ["project=${var.prefix}-srdp", "environment=hub", "managed_by=terraform"]
}

module "hub_network" {
  source         = "../../modules/hub-network"
  name_prefix    = local.name_prefix
  pn_subnet_cidr = var.pn_subnet_cidr
  tags           = local.tags
}

# Shared container registry — created ONCE, here in the hub. All clusters pull
# from it (same-Project auto, cross-Project via a registry-read IAM key).
module "registry" {
  source = "../../modules/registry"
  name   = "${var.prefix}-srdp"
}

# Headscale mesh control plane — the one public endpoint. Public-only (no PN):
# subnet-routers reach it over the internet; attaching it to a gateway'd PN would
# break inbound to its public IP.
module "headscale" {
  source           = "../../modules/headscale-vm"
  fqdn             = var.headscale_fqdn
  ssh_public_key   = var.headscale_ssh_public_key
  allowed_ssh_cidr = var.headscale_allowed_ssh_cidr
  tags             = local.tags
}

output "project_id" { value = var.project_id }
output "hub_vpc_id" { value = module.hub_network.vpc_id }
output "hub_private_network_id" { value = module.hub_network.private_network_id }
output "registry_endpoint" { value = module.registry.endpoint }
output "headscale_url" { value = module.headscale.server_url }
output "headscale_public_ip" { value = module.headscale.public_ip }
