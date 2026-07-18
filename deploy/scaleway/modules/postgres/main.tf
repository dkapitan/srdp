# Scaleway Managed Database for PostgreSQL (RDB), attached to the spoke Private
# Network (private endpoint only — no public endpoint). Backs Zitadel (identity)
# and Dagster (orchestration), plus the DuckLake catalog, as separate databases.

variable "name" { type = string }
variable "private_network_id" { type = string }
variable "node_type" {
  type    = string
  default = "DB-DEV-S"
}
variable "engine" {
  type    = string
  default = "PostgreSQL-16"
}
variable "is_ha_cluster" {
  type    = bool
  default = false # flip true in prod
}
variable "volume_size_in_gb" {
  type    = number
  default = 20
}
variable "administrator_login" {
  type    = string
  default = "srdpadmin"
}
variable "administrator_password" {
  type      = string
  sensitive = true
}
variable "databases" {
  type    = list(string)
  default = ["zitadel", "dagster", "ducklake"]
}
variable "tags" {
  type    = list(string)
  default = []
}

resource "scaleway_rdb_instance" "this" {
  name               = var.name
  node_type          = var.node_type
  engine             = var.engine
  is_ha_cluster      = var.is_ha_cluster
  disable_backup     = false
  user_name          = var.administrator_login
  password           = var.administrator_password
  volume_type        = "sbs_5k" # block storage
  volume_size_in_gb  = var.volume_size_in_gb
  encryption_at_rest = true
  tags               = var.tags

  # Private endpoint on the spoke PN; IPAM assigns the address.
  private_network {
    pn_id       = var.private_network_id
    enable_ipam = true
  }
}

resource "scaleway_rdb_database" "this" {
  for_each    = toset(var.databases)
  instance_id = scaleway_rdb_instance.this.id
  name        = each.value
}

output "id" { value = scaleway_rdb_instance.this.id }
output "endpoint_ip" {
  description = "Private IP of the RDB endpoint on the PN."
  value       = scaleway_rdb_instance.this.private_network[0].ip
}
output "endpoint_port" {
  value = scaleway_rdb_instance.this.private_network[0].port
}
output "load_balancer_ip" {
  description = "Stable hostname/IP resolvable on the PN (use as Postgres host)."
  value       = scaleway_rdb_instance.this.private_network[0].hostname
}
