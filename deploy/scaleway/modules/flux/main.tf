# Flux on Kapsule.
#
# Azure used the native `microsoft.flux` cluster extension. Scaleway has no
# equivalent, so we install Flux ourselves with Helm (community charts) — still
# from Terraform, still per-env, still reconciling ONLY this env's path:
#   - flux2       : the controllers (source/kustomize/helm/notification)
#   - flux2-sync  : a GitRepository + Kustomization pinned to this cluster's
#                   gitops leaf (deploy/gitops/clusters/scaleway/<env>)
#
# Helm-only (no kubernetes_manifest) so `terraform plan` does not need to reach
# the API server before the cluster exists. The helm provider is configured in
# the env root from the Kapsule kubeconfig and passed in.

terraform {
  required_providers {
    helm = { source = "hashicorp/helm" }
  }
}

variable "git_url" {
  type        = string
  description = "Repo URL. ssh:// for a private repo (supply git_ssh_private_key)."
}
variable "git_branch" {
  type    = string
  default = "main"
}
variable "git_path" {
  type        = string
  description = "Repo-relative path this cluster reconciles, e.g. deploy/gitops/clusters/scaleway/dev."
}
variable "git_ssh_private_key" {
  type        = string
  default     = null
  sensitive   = true
  description = "SSH private key (PEM) for a private repo; null = public repo."
}
variable "flux_version" {
  type    = string
  default = "2.14.1" # flux2 community chart version
}
variable "sync_version" {
  type    = string
  default = "1.10.0" # flux2-sync community chart version
}
variable "sync_interval" {
  type    = string
  default = "2m"
}

resource "helm_release" "flux" {
  name             = "flux2"
  namespace        = "flux-system"
  create_namespace = true
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  version          = var.flux_version
}

resource "helm_release" "sync" {
  name       = "flux2-sync"
  namespace  = "flux-system"
  repository = "https://fluxcd-community.github.io/helm-charts"
  chart      = "flux2-sync"
  version    = var.sync_version
  depends_on = [helm_release.flux]

  set {
    name  = "gitRepository.spec.url"
    value = var.git_url
  }
  set {
    name  = "gitRepository.spec.ref.branch"
    value = var.git_branch
  }
  set {
    name  = "gitRepository.spec.interval"
    value = var.sync_interval
  }
  set {
    name  = "kustomization.spec.path"
    value = "./${var.git_path}"
  }
  set {
    name  = "kustomization.spec.interval"
    value = var.sync_interval
  }
  set {
    name  = "kustomization.spec.prune"
    value = "true"
  }

  # Private-repo SSH auth: create the deploy-key secret Flux references.
  dynamic "set_sensitive" {
    for_each = var.git_ssh_private_key == null ? [] : [1]
    content {
      name  = "secret.data.identity"
      value = var.git_ssh_private_key
    }
  }
  dynamic "set" {
    for_each = var.git_ssh_private_key == null ? [] : [1]
    content {
      name  = "secret.create"
      value = "true"
    }
  }
}
