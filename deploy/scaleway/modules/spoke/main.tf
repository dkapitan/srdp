# One SRDP spoke (dev / stage / prod / ...): network, cluster, data services,
# IAM, secrets. Composes the building-block modules so every env root is a thin
# wrapper — adding an environment is a new tfvars, not new Terraform.
#
# Deliberately contains NO kubernetes/helm resources: those providers are
# configured from this module's kapsule outputs, so putting them here would be
# a provider-dependency cycle. The in-cluster pieces live in modules/spoke-k8s.

terraform {
  required_providers {
    scaleway = { source = "scaleway/scaleway" }
    random   = { source = "hashicorp/random" }
  }
}

variable "environment" {
  type        = string
  description = "Spoke identity (e.g. dev, stage, prod — any short lowercase name). Drives resource names, the Secret Manager prefix, and the Flux path."
}
variable "project_id" { type = string }
variable "hub_project_id" { type = string }
variable "hub_vpc_id" { type = string }
variable "prefix" { type = string }
variable "region" { type = string }

variable "pn_vpc_cidr" { type = string }
variable "pn_subnet_cidr" { type = string }

variable "system_node_count" { type = number }
variable "compute_node_type" { type = string }
variable "compute_min_count" {
  type    = number
  default = 0
}
variable "compute_max_count" { type = number }

variable "postgres_node_type" { type = string }
variable "postgres_ha" {
  type    = bool
  default = false
}

variable "api_extra_allowed_cidrs" {
  type    = list(string)
  default = []
}

variable "oauth2_client_id" {
  type    = string
  default = "CHANGE_ME"
}
variable "oauth2_client_secret" {
  type      = string
  default   = "CHANGE_ME"
  sensitive = true
}

variable "runner_ssh_public_key" { type = string }
variable "headscale_url" {
  type    = string
  default = ""
}
variable "headscale_authkey" {
  type      = string
  default   = ""
  sensitive = true
}
variable "enable_hub_peering" {
  type    = bool
  default = false
}

locals {
  name_prefix = "${var.prefix}-${var.environment}"
  tags        = ["project=${var.prefix}-srdp", "environment=${var.environment}", "managed_by=terraform"]
}

# --- Network: spoke VPC + PN, egress gateway, peering to the hub -------------
module "networking" {
  source         = "../networking"
  name_prefix    = local.name_prefix
  pn_subnet_cidr = var.pn_subnet_cidr
  tags           = local.tags
}

module "egress" {
  source             = "../egress-gateway"
  name_prefix        = local.name_prefix
  private_network_id = module.networking.private_network_id
  tags               = local.tags
}

# Hub <-> spoke peering. The connector lives in the spoke and targets the hub
# VPC id (injected from the hub output via the Justfile). Both VPCs must be in
# the same Organization with routing enabled. Off by default: hub services are
# public-endpoint + IAM, so no private hub<->spoke traffic exists to carry (and
# cross-Project connectors currently error, see the enable_hub_peering variable).
resource "scaleway_vpc_connector" "to_hub" {
  count         = var.enable_hub_peering ? 1 : 0
  name          = "conn-${local.name_prefix}-to-hub"
  vpc_id        = module.networking.vpc_id
  target_vpc_id = var.hub_vpc_id
}

# --- Kapsule cluster ---------------------------------------------------------
module "kapsule" {
  source             = "../kapsule"
  name               = "k8s-${local.name_prefix}"
  private_network_id = module.networking.private_network_id
  system_node_count  = var.system_node_count
  compute_node_type  = var.compute_node_type
  compute_min_count  = var.compute_min_count
  compute_max_count  = var.compute_max_count
  # Full-isolation nodes AND the (private) mesh-router both reach the public
  # control plane via the egress gateway, so the gateway IP MUST be allowed. The
  # mesh-router has no public IP of its own; kubectl-over-mesh egresses (SNAT'd)
  # from this same gateway IP. Add operator IPs only via api_extra_allowed_cidrs.
  api_allowed_cidrs       = concat(["${module.egress.public_ip}/32"], var.api_extra_allowed_cidrs)
  node_public_ip_disabled = true
  tags                    = local.tags
  depends_on              = [module.egress]
}

# --- Workload identity stand-ins (IAM apps + keys) ---------------------------
# Data plane: Object Storage read/write for DuckDB/dlt.
module "data_app" {
  source             = "../iam-app"
  name               = "app-data-${local.name_prefix}"
  description        = "SRDP ${var.environment} data plane (Object Storage)"
  default_project_id = var.project_id # preferred Project for the lakehouse S3 buckets
  policy_rules = [{
    project_ids          = [var.project_id]
    permission_set_names = ["ObjectStorageFullAccess"]
  }]
  tags = local.tags
}

# External Secrets Operator: read this Project's Secret Manager.
module "eso_app" {
  source      = "../iam-app"
  name        = "app-eso-${local.name_prefix}"
  description = "SRDP ${var.environment} External Secrets (Secret Manager RO)"
  policy_rules = [{
    project_ids          = [var.project_id]
    permission_set_names = ["SecretManagerSecretAccess", "SecretManagerReadOnly"]
  }]
  tags = local.tags
}

# Registry pull: ContainerRegistryReadOnly on the HUB Project (cross-Project).
module "registry_pull_app" {
  source      = "../iam-app"
  name        = "app-regpull-${local.name_prefix}"
  description = "SRDP ${var.environment} registry pull (hub Container Registry RO)"
  policy_rules = [{
    project_ids          = [var.hub_project_id]
    permission_set_names = ["ContainerRegistryReadOnly"]
  }]
  tags = local.tags
}

# --- Data services -----------------------------------------------------------
module "lakehouse" {
  source      = "../lakehouse"
  name_prefix = local.name_prefix
  region      = var.region
  tags        = { environment = var.environment, project = "${var.prefix}-srdp" }
}

resource "random_password" "postgres" {
  length           = 28
  special          = true
  override_special = "!#$%*-_"
}

resource "random_password" "zitadel_masterkey" {
  length  = 32
  special = false
}

resource "random_password" "oauth2_cookie" {
  length  = 32
  special = false
}

module "postgres" {
  source                 = "../postgres"
  name                   = "pg-${local.name_prefix}"
  private_network_id     = module.networking.private_network_id
  node_type              = var.postgres_node_type
  is_ha_cluster          = var.postgres_ha
  administrator_password = random_password.postgres.result
  tags                   = local.tags
}

# --- Secret Manager (Key Vault analogue) -------------------------------------
module "secrets" {
  source      = "../secrets"
  name_prefix = "srdp-${var.environment}"
  tags        = local.tags
  secrets = {
    "postgres-password"    = random_password.postgres.result
    "zitadel-masterkey"    = random_password.zitadel_masterkey.result
    "oauth2-cookie-secret" = random_password.oauth2_cookie.result
    "oauth2-client-id"     = var.oauth2_client_id     # externally sourced placeholder
    "oauth2-client-secret" = var.oauth2_client_secret # externally sourced placeholder
    "lakehouse-access-key" = module.data_app.access_key
    "lakehouse-secret-key" = module.data_app.secret_key
    "registry-access-key"  = module.registry_pull_app.access_key
    "registry-secret-key"  = module.registry_pull_app.secret_key
  }
}

# --- Mesh subnet-router VM (in the PN) ----------------------------------------
# Private (no public IP): egress + Headscale registration + subnet-routed kubectl
# all go via the egress gateway, whose IP is in the Kapsule ACL above. A VM that
# is BOTH on the gateway'd PN AND has its own public IP gets two fighting default
# routes and breaks — leave it private (see modules/mesh-router for the detail).
module "mesh_router" {
  source             = "../mesh-router"
  private_network_id = module.networking.private_network_id
  pn_cidr            = var.pn_vpc_cidr
  apiserver_url      = module.kapsule.host
  headscale_url      = var.headscale_url
  headscale_authkey  = var.headscale_authkey
  ssh_public_key     = var.runner_ssh_public_key
  gateway_ip         = module.egress.gateway_pn_ip # PN-only egress: explicit gateway default route
  tags               = local.tags
}

# --- Outputs -------------------------------------------------------------------
# Kubeconfig pieces: the env root configures its kubernetes/helm providers from
# these (for modules/spoke-k8s).
output "kapsule_host" { value = module.kapsule.host }
output "kapsule_token" {
  value     = module.kapsule.token
  sensitive = true
}
output "kapsule_ca_certificate" {
  value     = module.kapsule.cluster_ca_certificate
  sensitive = true
}

# ESO bootstrap credential (seeded into the cluster by modules/spoke-k8s).
output "eso_access_key" { value = module.eso_app.access_key }
output "eso_secret_key" {
  value     = module.eso_app.secret_key
  sensitive = true
}

output "kapsule_id" { value = module.kapsule.id }
output "lakehouse_endpoint" { value = module.lakehouse.endpoint }
output "lakehouse_s3_url" { value = module.lakehouse.lakehouse_s3_url }
output "lakehouse_buckets" { value = module.lakehouse.bucket_names }
output "postgres_host" { value = module.postgres.load_balancer_ip }
output "postgres_port" { value = module.postgres.endpoint_port }
output "data_access_key" { value = module.data_app.access_key }
output "private_network_id" { value = module.networking.private_network_id }
