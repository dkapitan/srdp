# Spoke environment root — a thin wrapper around modules/spoke + modules/spoke-k8s.
# IDENTICAL across all spokes; every environment-specific value comes from
# `terraform.tfvars` (+ a few injected by the Justfile from .env / the hub state).
# To add an environment: copy this directory, write its tfvars, register the env
# in .env (SPOKE_ENVS + PROJECT_ID_<ENV>), and add its gitops leaf under
# deploy/gitops/clusters/scaleway/.

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

# All Scaleway-side infra for this spoke.
module "spoke" {
  source = "../../modules/spoke"

  environment    = var.environment
  project_id     = var.project_id
  hub_project_id = var.hub_project_id
  hub_vpc_id     = var.hub_vpc_id
  prefix         = var.prefix
  region         = var.region

  pn_vpc_cidr    = var.pn_vpc_cidr
  pn_subnet_cidr = var.pn_subnet_cidr

  system_node_count = var.system_node_count
  compute_node_type = var.compute_node_type
  compute_min_count = var.compute_min_count
  compute_max_count = var.compute_max_count

  postgres_node_type = var.postgres_node_type
  postgres_ha        = var.postgres_ha

  api_extra_allowed_cidrs = var.api_extra_allowed_cidrs

  oauth2_client_id     = var.oauth2_client_id
  oauth2_client_secret = var.oauth2_client_secret

  runner_ssh_public_key = var.runner_ssh_public_key
  headscale_url         = var.headscale_url
  headscale_authkey     = var.headscale_authkey
  enable_hub_peering    = var.enable_hub_peering
}

# Kubernetes + Helm providers, configured from the freshly-created Kapsule
# kubeconfig. Used by modules/spoke-k8s (Flux install + ESO bootstrap secret).
# On a brand-new spoke the cluster must exist before these can plan:
# `just _tf <env> "apply -target=module.spoke"` first, then a full apply.
provider "kubernetes" {
  host                   = module.spoke.kapsule_host
  token                  = module.spoke.kapsule_token
  cluster_ca_certificate = base64decode(module.spoke.kapsule_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.spoke.kapsule_host
    token                  = module.spoke.kapsule_token
    cluster_ca_certificate = base64decode(module.spoke.kapsule_ca_certificate)
  }
}

# In-cluster bootstrap: ESO credential + Flux reconciling this env's gitops leaf.
module "spoke_k8s" {
  source = "../../modules/spoke-k8s"

  environment    = var.environment
  eso_access_key = module.spoke.eso_access_key
  eso_secret_key = module.spoke.eso_secret_key

  git_repo_url        = var.git_repo_url
  git_branch          = var.git_branch
  git_ssh_private_key = var.git_ssh_private_key
}

output "kapsule_id" { value = module.spoke.kapsule_id }
output "lakehouse_endpoint" { value = module.spoke.lakehouse_endpoint }
output "lakehouse_s3_url" { value = module.spoke.lakehouse_s3_url }
output "lakehouse_buckets" { value = module.spoke.lakehouse_buckets }
output "postgres_host" { value = module.spoke.postgres_host }
output "postgres_port" { value = module.spoke.postgres_port }
output "data_access_key" { value = module.spoke.data_access_key }
output "private_network_id" { value = module.spoke.private_network_id }
