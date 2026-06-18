# Kapsule (managed Kubernetes) for SRDP — the Scaleway analogue of AKS.
#
# Bimodal workload: a small always-on pool (Zitadel/Traefik/Dagster daemon) and
# a memory-optimized, scale-from-zero pool for bursty DuckDB/Polars jobs.
#
# Nodes attach to the spoke Private Network (no public IPs); egress is via the
# Public Gateway. CNI is Cilium (matches the AKS choice).
#
# DIVERGENCE FROM AZURE: Kapsule's API server uses a managed PUBLIC endpoint.
# There is no fully private API IP like AKS private clusters. We instead lock the
# endpoint with a k8s ACL (api_allowed_cidrs) to the PN + operator/mesh ranges,
# so kubectl works from inside the VPC or over the Headscale mesh.

variable "name" { type = string }
variable "kubernetes_version" {
  type    = string
  default = "1.35" # minor only: auto_upgrade requires x.y (not x.y.z)
}
variable "private_network_id" { type = string }

variable "system_node_type" {
  type    = string
  default = "PLAY2-MICRO"
}
variable "system_node_count" {
  type    = number
  default = 2
}

variable "compute_node_type" {
  type        = string
  default     = "POP2-8C-32G" # memory-oriented for DuckDB/Polars
  description = "DuckDB scales up, not out — size for RAM."
}
variable "compute_min_count" {
  type    = number
  default = 0
}
variable "compute_max_count" {
  type    = number
  default = 4
}

variable "api_allowed_cidrs" {
  type        = list(string)
  description = "PUBLIC source IPs allowed to reach the Kapsule API. Must include the spoke egress Public Gateway IP (full-isolation nodes reach the control plane through it) + any operator/mesh egress."
  default     = []
}

variable "node_public_ip_disabled" {
  type        = bool
  default     = true
  description = "Full isolation: nodes get NO public IP and egress via the Public Gateway. Requires the gateway IP in api_allowed_cidrs so kubelets can reach the (public) control plane."
}

variable "tags" {
  type    = list(string)
  default = []
}

resource "scaleway_k8s_cluster" "this" {
  name                        = var.name
  type                        = "kapsule"
  version                     = var.kubernetes_version
  cni                         = "cilium"
  private_network_id          = var.private_network_id
  delete_additional_resources = true
  tags                        = var.tags

  autoscaler_config {
    disable_scale_down          = false
    balance_similar_node_groups = true
  }

  auto_upgrade {
    enable                        = true
    maintenance_window_start_hour = 3
    maintenance_window_day        = "sunday"
  }
}

# Always-on system pool. Full isolation: no public IP, egress via the gateway.
# Depends on the ACL so the gateway IP is allowed BEFORE kubelets (which now
# reach the public control plane through that gateway) come up.
resource "scaleway_k8s_pool" "system" {
  cluster_id          = scaleway_k8s_cluster.this.id
  name                = "system"
  node_type           = var.system_node_type
  size                = var.system_node_count
  min_size            = var.system_node_count
  max_size            = var.system_node_count
  autohealing         = true
  public_ip_disabled  = var.node_public_ip_disabled
  wait_for_pool_ready = true

  depends_on = [scaleway_k8s_acl.this]
}

# Memory-optimized, scale-from-zero pool for batch query/transform jobs.
# Kapsule won't CREATE a pool with 0 nodes, so start at 1 and let the autoscaler
# scale back to min_size (0). The autoscaler owns the live count -> ignore drift.
resource "scaleway_k8s_pool" "compute" {
  cluster_id         = scaleway_k8s_cluster.this.id
  name               = "compute"
  node_type          = var.compute_node_type
  size               = max(var.compute_min_count, 1)
  min_size           = var.compute_min_count
  max_size           = var.compute_max_count
  autoscaling        = true
  autohealing        = true
  public_ip_disabled = var.node_public_ip_disabled

  tags = ["workload=srdp-compute"]

  lifecycle {
    ignore_changes = [size]
  }

  depends_on = [scaleway_k8s_acl.this]
}

# Lock the (public) API endpoint to the VPC + operator/mesh ranges.
resource "scaleway_k8s_acl" "this" {
  cluster_id = scaleway_k8s_cluster.this.id
  dynamic "acl_rules" {
    for_each = var.api_allowed_cidrs
    content {
      ip = acl_rules.value
    }
  }
}

output "id" { value = scaleway_k8s_cluster.this.id }
output "name" { value = scaleway_k8s_cluster.this.name }
output "kubeconfig" {
  value     = scaleway_k8s_cluster.this.kubeconfig[0].config_file
  sensitive = true
}
output "host" { value = scaleway_k8s_cluster.this.kubeconfig[0].host }
output "cluster_ca_certificate" {
  value     = scaleway_k8s_cluster.this.kubeconfig[0].cluster_ca_certificate
  sensitive = true
}
output "token" {
  value     = scaleway_k8s_cluster.this.kubeconfig[0].token
  sensitive = true
}
output "wildcard_dns" { value = scaleway_k8s_cluster.this.wildcard_dns }
