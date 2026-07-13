# Spoke variables. IDENTICAL across all spokes; values are supplied per-env in
# terraform.tfvars (+ a few injected by the Justfile from .env / the hub state:
# project_id, hub_project_id, hub_vpc_id, prefix, region, zone, headscale_url).

variable "environment" {
  type        = string
  description = "Spoke identity — any short lowercase name (the shipped examples are dev/stage/prod, but the set is yours: one env is fine). Drives resource names, the Secret Manager prefix, and the Flux path (deploy/gitops/clusters/scaleway/<environment>)."
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,15}$", var.environment))
    error_message = "environment must be short lowercase alphanumeric (used in resource/bucket names)."
  }
}

variable "project_id" {
  type        = string
  description = "This spoke's Scaleway Project id."
}

variable "hub_project_id" {
  type        = string
  description = "Hub/connectivity Project id — scope for the registry-pull IAM policy."
}

variable "hub_vpc_id" {
  type        = string
  description = "Hub VPC id (regional, {region}/{uuid}) — the peering target. Injected from the hub output by the Justfile."
}

variable "prefix" {
  type        = string
  description = "Org/company short code (lowercase, alphanumeric) used in resource names."
}

variable "region" {
  type    = string
  default = "nl-ams"
}

variable "zone" {
  type        = string
  default     = "nl-ams-1"
  description = "Default AZ. RDB private networking requires the region's default AZ."
}

# --- Network -----------------------------------------------------------------
variable "pn_vpc_cidr" {
  type        = string
  description = "Spoke VPC address space (a /16) advertised into the mesh so operators reach RDB, the internal LB, and node IPs. Must not overlap the hub or other spokes."
}

variable "pn_subnet_cidr" {
  type        = string
  description = "Spoke Private Network subnet (a /20 inside pn_vpc_cidr): nodes, RDB private endpoint, mesh-router."
}

# --- Kapsule sizing ----------------------------------------------------------
variable "system_node_count" {
  type        = number
  description = "Always-on system pool size (Zitadel / Traefik / Dagster daemon)."
}

variable "compute_node_type" {
  type        = string
  description = "Memory-optimized instance type for the scale-from-zero DuckDB/Polars pool (sized for RAM; DuckDB scales up, not out)."
}

variable "compute_min_count" {
  type        = number
  default     = 0
  description = "Compute pool floor (0 = scale to zero when idle)."
}

variable "compute_max_count" {
  type        = number
  description = "Compute pool ceiling."
}

# --- Postgres ----------------------------------------------------------------
variable "postgres_node_type" {
  type        = string
  description = "Managed Database (RDB) instance type, e.g. DB-DEV-S / DB-GP-S / DB-GP-M."
}

variable "postgres_ha" {
  type        = bool
  default     = false
  description = "Provision RDB as an HA cluster (recommended for prod)."
}

# --- Kapsule API access ------------------------------------------------------
variable "api_extra_allowed_cidrs" {
  type        = list(string)
  default     = []
  description = "Extra CIDRs allowed to reach the Kapsule API (e.g. an operator egress IP for the first apply). The spoke egress gateway IP is always allowed automatically."
}

# --- GitOps (Flux) -----------------------------------------------------------
variable "git_repo_url" {
  type        = string
  description = "GitOps repo Flux reconciles. Use an ssh:// URL with git_ssh_private_key for a private repo. Set this in terraform.tfvars."
}

variable "git_branch" {
  type    = string
  default = "main"
}

variable "git_ssh_private_key" {
  type      = string
  default   = null
  sensitive = true
}

# --- Application secrets (externally sourced placeholders) -------------------
variable "oauth2_client_id" {
  type        = string
  default     = "CHANGE_ME"
  description = "OIDC client id for oauth2-proxy (created in Zitadel post-bootstrap)."
}

variable "oauth2_client_secret" {
  type      = string
  default   = "CHANGE_ME"
  sensitive = true
}

# --- Mesh --------------------------------------------------------------------
variable "runner_ssh_public_key" {
  type        = string
  description = "SSH public key for break-glass access to the mesh-router VM."
}

variable "headscale_url" {
  type        = string
  default     = ""
  description = "Headscale control-plane URL the mesh-router registers against. Injected from the hub output by the Justfile; empty = not yet known."
}

variable "headscale_authkey" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Headscale pre-auth key for the mesh-router (create on the Headscale VM). Empty = install but don't register yet."
}

variable "enable_hub_peering" {
  type        = bool
  default     = false
  description = "Create the hub<->spoke VPC connector. Not required for the mesh or cluster reachability; cross-Project connectors currently return an opaque 'invalid argument(s)' from the API."
}
