terraform {
  required_providers {
    scaleway = {
      source = "scaleway/scaleway"
    }
  }
  required_version = ">= 0.13"
}

provider "scaleway" {
  zone = "fr-par-1" # Or your preferred zone
}

resource "scaleway_registry_namespace" "srdp_registry" {
  name        = "srdp-registry"
  description = "Registry for SRDP Sprint 2"
  is_public   = false
}

output "registry_endpoint" {
  value = scaleway_registry_namespace.srdp_registry.endpoint
}