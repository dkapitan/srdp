# Bootstrap: creates the per-Project Terraform state backend (an Object Storage
# bucket). Run MANUALLY, ONCE PER PROJECT, before `terraform init` in any
# envs/<env>. Uses LOCAL state (no backend block) — it builds the very thing
# remote state needs (chicken-and-egg).
#
#   just bootstrap-state hub      # then dev / stage / prod
#
# Object Storage is S3-compatible, so envs use Terraform's `backend "s3"` against
# the Scaleway S3 endpoint. Keep deploy/bootstrap/terraform.tfstate safe.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    scaleway = { source = "scaleway/scaleway", version = "~> 2.71" }
  }
}

provider "scaleway" {
  project_id = var.project_id
  region     = var.region
}

variable "project_id" {
  type        = string
  description = "Target Project (hub / dev / stage / prod)."
}

variable "env" {
  type        = string
  description = "Short env code: hub | dev | stg | prd."
  validation {
    condition     = contains(["hub", "dev", "stg", "prd"], var.env)
    error_message = "env must be one of hub, dev, stg, prd."
  }
}

variable "prefix" {
  type        = string
  description = "Org/company short code (lowercase, alphanumeric)."
}

variable "region" {
  type    = string
  default = "nl-ams"
}

resource "scaleway_object_bucket" "tfstate" {
  name   = "${var.prefix}-tfstate-${var.env}"
  region = var.region
  tags = {
    project    = "${var.prefix}-srdp"
    purpose    = "terraform-state"
    managed_by = "terraform-bootstrap"
  }

  versioning {
    enabled = true # protect state against bad writes
  }
}

output "bucket" { value = scaleway_object_bucket.tfstate.name }
output "endpoint" { value = "https://s3.${var.region}.scw.cloud" }
