# Object Storage = the SRDP lakehouse (S3-compatible).
#
# DuckDB/DuckLake and dlt read & write Parquet here over the S3 API (DuckDB
# `httpfs`, dlt `s3fs`). Unlike Azure ADLS + workload identity, access is via an
# S3 access key / secret key minted from an IAM application (see the data
# iam-app instance at env level) — there is no keyless pod identity on Scaleway.
# The credentials land in Secret Manager and are synced into the cluster by ESO.

variable "name_prefix" {
  type        = string
  description = "Bucket name prefix, e.g. <prefix>-dev. Buckets are <prefix>-<container>."
}
variable "region" { type = string }
variable "containers" {
  type        = list(string)
  default     = ["landing", "lakehouse", "staging"]
  description = "dlt lands raw -> lakehouse parquet (DuckDB/dbt) -> staging."
}
variable "tags" {
  type    = map(string)
  default = {}
}

resource "scaleway_object_bucket" "this" {
  for_each = toset(var.containers)
  name     = "${var.name_prefix}-${each.value}"
  region   = var.region
  tags     = var.tags

  versioning {
    enabled = false
  }
}

output "endpoint" {
  description = "S3 endpoint for this region."
  value       = "https://s3.${var.region}.scw.cloud"
}
output "bucket_names" {
  value = { for k, b in scaleway_object_bucket.this : k => b.name }
}
output "lakehouse_s3_url" {
  description = "s3:// URL DuckLake uses as its DATA_PATH."
  value       = "s3://${scaleway_object_bucket.this["lakehouse"].name}"
}
