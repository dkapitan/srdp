# Per-env Secret Manager entries — the Scaleway analogue of Key Vault.
#
# Terraform generates/loads the secret values and stores them as
# scaleway_secret + scaleway_secret_version. Workloads never read these
# directly; External Secrets (Scaleway provider) syncs them into k8s Secrets
# referenced by the chart as `existingSecret`. ESO's OWN credentials are the one
# exception — they're written straight to a k8s Secret by Terraform to break the
# chicken-and-egg (see the env's kubernetes_secret.eso_creds).

variable "name_prefix" {
  type        = string
  description = "Secret name prefix, e.g. srdp-dev. Final name is <prefix>-<key>."
}
variable "secrets" {
  type        = map(string)
  sensitive   = true
  description = "key => value. Stored as Secret Manager secrets/versions."
}
variable "tags" {
  type    = list(string)
  default = []
}

# for_each can't take a sensitive value, but the secret KEYS are not sensitive —
# nonsensitive() asserts that so we can iterate; the values stay sensitive.
locals {
  secret_keys = nonsensitive(toset(keys(var.secrets)))
}

resource "scaleway_secret" "this" {
  for_each    = local.secret_keys
  name        = "${var.name_prefix}-${each.key}"
  description = "SRDP ${each.key}"
  tags        = var.tags
}

resource "scaleway_secret_version" "this" {
  for_each  = local.secret_keys
  secret_id = scaleway_secret.this[each.key].id
  data      = var.secrets[each.key]
}

output "secret_names" {
  value = { for k, s in scaleway_secret.this : k => s.name }
}
