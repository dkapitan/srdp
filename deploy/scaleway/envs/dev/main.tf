# Spoke environment root (dev / stage / prod).
#
# This file is IDENTICAL across the three spokes — every environment-specific
# value (CIDRs, cluster sizing, Postgres tier, the env name itself) comes from
# `terraform.tfvars`. Keep the three copies in sync; only the tfvars differ.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    scaleway   = { source = "scaleway/scaleway", version = "~> 2.71" }
    random     = { source = "hashicorp/random", version = "~> 3.6" }
    helm       = { source = "hashicorp/helm", version = "~> 2.13" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
  }
  backend "s3" {}
}

provider "scaleway" {
  project_id = var.project_id
  region     = var.region
  zone       = var.zone
}

# Kubernetes + Helm providers, configured from the freshly-created Kapsule
# kubeconfig. Used to install Flux and seed the ESO bootstrap credential.
provider "kubernetes" {
  host                   = module.kapsule.host
  token                  = module.kapsule.token
  cluster_ca_certificate = base64decode(module.kapsule.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.kapsule.host
    token                  = module.kapsule.token
    cluster_ca_certificate = base64decode(module.kapsule.cluster_ca_certificate)
  }
}

locals {
  name_prefix = "${var.prefix}-${var.environment}"
  tags        = ["project=${var.prefix}-srdp", "environment=${var.environment}", "managed_by=terraform"]
}

# --- Network: spoke VPC + PN, egress gateway, peering to the hub -------------
module "networking" {
  source         = "../../modules/networking"
  name_prefix    = local.name_prefix
  pn_subnet_cidr = var.pn_subnet_cidr
  tags           = local.tags
}

module "egress" {
  source             = "../../modules/egress-gateway"
  name_prefix        = local.name_prefix
  private_network_id = module.networking.private_network_id
  tags               = local.tags
}

# Hub <-> spoke peering. The connector lives in the spoke and targets the hub
# VPC id (injected from the hub output via the Justfile). Both VPCs must be in
# the same Organization with routing enabled. Off by default — see docs/BACKLOG.md.
resource "scaleway_vpc_connector" "to_hub" {
  count         = var.enable_hub_peering ? 1 : 0
  name          = "conn-${local.name_prefix}-to-hub"
  vpc_id        = module.networking.vpc_id
  target_vpc_id = var.hub_vpc_id
}

# --- Kapsule cluster ---------------------------------------------------------
module "kapsule" {
  source             = "../../modules/kapsule"
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
  source             = "../../modules/iam-app"
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
  source      = "../../modules/iam-app"
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
  source      = "../../modules/iam-app"
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
  source      = "../../modules/lakehouse"
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
  source                 = "../../modules/postgres"
  name                   = "pg-${local.name_prefix}"
  private_network_id     = module.networking.private_network_id
  node_type              = var.postgres_node_type
  is_ha_cluster          = var.postgres_ha
  administrator_password = random_password.postgres.result
  tags                   = local.tags
}

# --- Secret Manager (Key Vault analogue) -------------------------------------
module "secrets" {
  source      = "../../modules/secrets"
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

# --- ESO bootstrap credential (NOT in Secret Manager — breaks chicken-egg) ---
resource "kubernetes_namespace" "external_secrets" {
  metadata { name = "external-secrets" }
}

resource "kubernetes_secret" "eso_creds" {
  metadata {
    name      = "scaleway-eso-creds"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
  }
  data = {
    SCW_ACCESS_KEY = module.eso_app.access_key
    SCW_SECRET_KEY = module.eso_app.secret_key
  }
}

# --- Flux: installs controllers + reconciles deploy/clusters/<environment> ---
module "flux" {
  source              = "../../modules/flux"
  git_url             = var.git_repo_url
  git_branch          = var.git_branch
  git_path            = "deploy/clusters/${var.environment}"
  git_ssh_private_key = var.git_ssh_private_key
}

# --- Mesh subnet-router VM (in the PN; replaces the Flux subnet-router pod) ---
# Private (no public IP): egress + Headscale registration + subnet-routed kubectl
# all go via the egress gateway, whose IP is in the Kapsule ACL above. A VM that
# is BOTH on the gateway'd PN AND has its own public IP gets two fighting default
# routes and breaks — leave it private (see modules/mesh-router for the detail).
module "mesh_router" {
  source             = "../../modules/mesh-router"
  private_network_id = module.networking.private_network_id
  pn_cidr            = var.pn_vpc_cidr
  apiserver_url      = module.kapsule.host
  headscale_url      = var.headscale_url
  headscale_authkey  = var.headscale_authkey
  ssh_public_key     = var.runner_ssh_public_key
  gateway_ip         = module.egress.gateway_pn_ip # PN-only egress: explicit gateway default route
  tags               = local.tags
}

output "kapsule_id" { value = module.kapsule.id }
output "lakehouse_endpoint" { value = module.lakehouse.endpoint }
output "lakehouse_s3_url" { value = module.lakehouse.lakehouse_s3_url }
output "lakehouse_buckets" { value = module.lakehouse.bucket_names }
output "postgres_host" { value = module.postgres.load_balancer_ip }
output "postgres_port" { value = module.postgres.endpoint_port }
output "data_access_key" { value = module.data_app.access_key }
