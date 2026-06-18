# Scaleway Container Registry namespace — created ONCE, in the hub Project.
# Private (is_public = false); all clusters pull from it.
#
# DIVERGENCE FROM AZURE: a Scaleway registry has no private endpoint. It is
# reached over its public HTTPS endpoint with credentials. Same-Project Kapsule
# clusters get pull access automatically; cross-Project pulls (spokes -> hub
# registry) use an IAM API key with ContainerRegistryReadOnly on the hub Project
# (see the registry-pull iam-app instance + the dockerconfigjson ExternalSecret).

variable "name" {
  type        = string
  description = "Globally unique registry namespace name, e.g. <prefix>-srdp."
}

resource "scaleway_registry_namespace" "this" {
  name        = var.name
  description = "SRDP shared container registry"
  is_public   = false
}

output "id" { value = scaleway_registry_namespace.this.id }
output "endpoint" { value = scaleway_registry_namespace.this.endpoint }
