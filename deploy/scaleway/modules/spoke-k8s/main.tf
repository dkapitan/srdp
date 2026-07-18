# In-cluster bootstrap for a spoke: the ESO credential Secret and Flux.
# Split from modules/spoke because the kubernetes/helm providers used here are
# configured (in the env root) from the spoke's kapsule outputs — the two halves
# can't share a module without a provider-dependency cycle.

terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
  }
}

variable "environment" { type = string }

variable "eso_access_key" { type = string }
variable "eso_secret_key" {
  type      = string
  sensitive = true
}

variable "git_repo_url" { type = string }
variable "git_branch" {
  type    = string
  default = "main"
}
variable "git_ssh_private_key" {
  type      = string
  default   = null
  sensitive = true
}

variable "gitops_path" {
  type        = string
  default     = ""
  description = "Repo-relative path this cluster's Flux reconciles. Empty = the conventional deploy/gitops/clusters/scaleway/<environment>."
}

locals {
  gitops_path = var.gitops_path != "" ? var.gitops_path : "deploy/gitops/clusters/scaleway/${var.environment}"
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
    SCW_ACCESS_KEY = var.eso_access_key
    SCW_SECRET_KEY = var.eso_secret_key
  }
}

# --- Flux: installs controllers + reconciles this env's gitops leaf ----------
module "flux" {
  source              = "../flux"
  git_url             = var.git_repo_url
  git_branch          = var.git_branch
  git_path            = local.gitops_path
  git_ssh_private_key = var.git_ssh_private_key
}
