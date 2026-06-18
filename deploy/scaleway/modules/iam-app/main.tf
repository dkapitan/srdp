# Generic IAM application + policy + API key.
#
# This is the Scaleway stand-in for Azure workload identity. Scaleway has no pod
# OIDC federation, so instead of a federated managed identity we mint a scoped
# IAM application with an API key. The key (access_key / secret_key) is the
# credential a workload uses — for S3 (Object Storage), Secret Manager, or
# Container Registry pulls. Store it in Secret Manager and sync into the cluster
# with External Secrets (or, for ESO's own bootstrap key, write it straight to a
# k8s Secret from Terraform).
#
# Reused per concern: data (Object Storage RW), eso (Secret Manager RO),
# registry-pull (Container Registry RO on the hub Project).

variable "name" { type = string }
variable "description" {
  type    = string
  default = ""
}
variable "policy_rules" {
  type = list(object({
    project_ids          = list(string)
    permission_set_names = list(string)
  }))
  description = "IAM permission sets scoped to one or more Projects."
}
variable "default_project_id" {
  type        = string
  default     = null
  description = "Preferred Project for the API key. REQUIRED for Object Storage keys — Scaleway's S3 API resolves buckets only within the key's preferred Project."
}

variable "api_key_expires_at" {
  type        = string
  default     = ""
  description = "RFC3339 expiry for the API key. Empty => ~1 year from creation. Some Orgs' security settings REQUIRE an expiry. Rotate before it lapses (`terraform apply -replace`)."
}
variable "tags" {
  type    = list(string)
  default = []
}

resource "scaleway_iam_application" "this" {
  name        = var.name
  description = var.description
  tags        = var.tags
}

resource "scaleway_iam_policy" "this" {
  name           = "pol-${var.name}"
  description    = var.description
  application_id = scaleway_iam_application.this.id

  dynamic "rule" {
    for_each = var.policy_rules
    content {
      project_ids          = rule.value.project_ids
      permission_set_names = rule.value.permission_set_names
    }
  }
}

resource "scaleway_iam_api_key" "this" {
  application_id     = scaleway_iam_application.this.id
  description        = var.description
  default_project_id = var.default_project_id
  # Org policy may require an expiry. Set once at creation; ignore drift so the
  # timestamp()-derived default doesn't churn on every apply.
  expires_at = var.api_key_expires_at != "" ? var.api_key_expires_at : timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [expires_at]
  }
}

output "application_id" { value = scaleway_iam_application.this.id }
output "access_key" { value = scaleway_iam_api_key.this.access_key }
output "secret_key" {
  value     = scaleway_iam_api_key.this.secret_key
  sensitive = true
}
