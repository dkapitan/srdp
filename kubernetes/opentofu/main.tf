# ----------------------------------------------------------------
# Variables
# ----------------------------------------------------------------
variable "region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway zone"
  type        = string
  default     = "fr-par-1"
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "srdp-cluster"
}

variable "database_name" {
  description = "Serverless SQL Database name"
  type        = string
  default     = "zitadel-db"
}

terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.60"
    }
  }
  required_version = ">= 0.13"
}

# Provider will automatically use these environment variables:
# - SCW_ACCESS_KEY
# - SCW_SECRET_KEY
# - SCW_DEFAULT_PROJECT_ID
provider "scaleway" {
  # No credentials needed here - reads from env vars
  zone   = var.zone
  region = var.region
}

# ----------------------------------------------------------------
# Registry - must be created through Scaleway Console beforehand
# ----------------------------------------------------------------
data "scaleway_registry_namespace" "srdp_registry" {
  name = "srdp-registry"
}

data "scaleway_account_project" "current" {
  # This automatically uses the SCW_DEFAULT_PROJECT_ID from your environment variables
}

# ----------------------------------------------------------------
# Private Network (required for Kubernetes)
# ----------------------------------------------------------------
resource "scaleway_vpc_private_network" "k8s_network" {
  name = "${var.cluster_name}-network"
  tags = ["kubernetes", "srdp"]
}

# ----------------------------------------------------------------
# Kubernetes Cluster
# ----------------------------------------------------------------
resource "scaleway_k8s_cluster" "srdp_cluster" {
  name = var.cluster_name
  version = "1.31.12"
  cni = "cilium"
  private_network_id = scaleway_vpc_private_network.k8s_network.id
  delete_additional_resources = false
  depends_on = [scaleway_vpc_private_network.k8s_network]
}

resource "scaleway_k8s_pool" "srdp_pool" {
  cluster_id  = scaleway_k8s_cluster.srdp_cluster.id
  name        = "${var.cluster_name}-default-pool"
  node_type   = "PLAY2-MICRO"
  size        = 2
  min_size    = 1 # TODO: Maybe reduce to 0?
  max_size    = 3
  autoscaling = true
  autohealing = true
  wait_for_pool_ready = true
}

# ----------------------------------------------------------------
# Managed Database
# ----------------------------------------------------------------
resource "random_password" "db_password" {
  length           = 16
  special          = true
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "_%@"
}

resource "scaleway_rdb_instance" "zitadel_rdb" {
  name           = "zitadel-postgres"
  node_type      = "DB-PLAY2-PICO"
  engine         = "PostgreSQL-16"
  is_ha_cluster  = false
  disable_backup = true
  user_name      = "scw_admin" 
  password       = random_password.db_password.result
  region         = var.region
  volume_type       = "sbs_5k" 
  volume_size_in_gb = 10
}

# ----------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------

output "registry_endpoint" {
  value       = data.scaleway_registry_namespace.srdp_registry.endpoint
  description = "Container registry endpoint"
}

output "private_network_id" {
  value       = scaleway_vpc_private_network.k8s_network.id
  description = "Private Network ID for Kubernetes cluster"
}

output "cluster_id" {
  value       = scaleway_k8s_cluster.srdp_cluster.id
  description = "Kubernetes cluster ID"
}

output "cluster_status" {
  value       = scaleway_k8s_cluster.srdp_cluster.status
  description = "Kubernetes cluster status"
}

output "kubeconfig" {
  value       = scaleway_k8s_cluster.srdp_cluster.kubeconfig[0].config_file
  sensitive   = true
  description = "Kubernetes configuration file content"
}

output "rdb_host" {
  value       = scaleway_rdb_instance.zitadel_rdb.endpoint_ip
  description = "Database Host IP"
}

output "rdb_port" {
  value       = scaleway_rdb_instance.zitadel_rdb.endpoint_port
  description = "Database Port"
}

output "rdb_password" {
  value       = random_password.db_password.result
  sensitive   = true
  description = "Database Password"
}

# ----------------------------------------------------------------
# Instructions
# ----------------------------------------------------------------
output "instructions" {
  value = <<-EOT
  
  ========================================
  Infrastructure Updated Successfully!
  ========================================
  
  1. Get Kubeconfig:
     tofu output -raw kubeconfig > kubeconfig.yaml
     export KUBECONFIG=./kubeconfig.yaml
     kubectl get nodes
  
  2. Update values-prod.yaml with DB Info:
     DB HOST:     ${scaleway_rdb_instance.zitadel_rdb.endpoint_ip}
     DB PORT:     ${scaleway_rdb_instance.zitadel_rdb.endpoint_port}
     
     Get Password:
     tofu output -raw rdb_password
  
  3. Registry:
     ${data.scaleway_registry_namespace.srdp_registry.endpoint}
  
  ========================================
  EOT
}
