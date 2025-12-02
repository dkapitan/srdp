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
# 3. Kubernetes Cluster
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
  node_type   = "PLAY2-NANO"
  size        = 2
  min_size    = 1 # TODO: Maybe reduce to 0?
  max_size    = 3
  autoscaling = true
  autohealing = true
  wait_for_pool_ready = true
}

# ----------------------------------------------------------------
# Serverless SQL Database
# ----------------------------------------------------------------
resource "scaleway_sdb_sql_database" "zitadel_db" {
  name = var.database_name

  # CPU limits (0-15)
  min_cpu = 0
  max_cpu = 15

  region = var.region
}

# ----------------------------------------------------------------
# IAM Application for Database Access
# ----------------------------------------------------------------
resource "scaleway_iam_application" "zitadel_app" {
  name        = "zitadel-serverless-db"
  description = "IAM application for Zitadel to access Serverless SQL Database"
  
  organization_id = data.scaleway_account_project.current.organization_id
}

# Grant database access permissions
resource "scaleway_iam_policy" "zitadel_db_policy" {
  name           = "zitadel-db-access"
  description    = "Policy allowing Zitadel app to access the serverless database"
  application_id = scaleway_iam_application.zitadel_app.id

  organization_id = data.scaleway_account_project.current.organization_id

  rule {
    project_ids = [scaleway_sdb_sql_database.zitadel_db.project_id]
    permission_set_names = [
      "ServerlessSQLDatabaseReadWrite"
    ]
  }
}

# Create API key for database authentication
resource "scaleway_iam_api_key" "zitadel_app_key" {
  application_id = scaleway_iam_application.zitadel_app.id
  description    = "API key for Zitadel to connect to Serverless SQL Database"
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

output "db_endpoint" {
  value       = scaleway_sdb_sql_database.zitadel_db.endpoint
  description = "Serverless SQL Database endpoint"
}

output "db_name" {
  value       = scaleway_sdb_sql_database.zitadel_db.name
  description = "Database name"
}

# Connection information for Zitadel
output "db_connection_string" {
  value = format(
    "postgres://%s:%s@%s/%s?sslmode=require",
    scaleway_iam_application.zitadel_app.id,
    scaleway_iam_api_key.zitadel_app_key.secret_key,
    replace(scaleway_sdb_sql_database.zitadel_db.endpoint, "postgres://", ""),
    scaleway_sdb_sql_database.zitadel_db.name
  )
  sensitive   = true
  description = "PostgreSQL connection string with IAM credentials"
}

output "db_host" {
  value       = replace(scaleway_sdb_sql_database.zitadel_db.endpoint, "postgres://", "")
  description = "Database host (for separate config)"
}

output "db_user" {
  value       = scaleway_iam_application.zitadel_app.id
  description = "Database username (IAM Application ID)"
}

output "db_password" {
  value       = scaleway_iam_api_key.zitadel_app_key.secret_key
  sensitive   = true
  description = "Database password (IAM API Key)"
}

# Kubernetes configuration
output "instructions" {
  value = <<-EOT
  
  ========================================
  Infrastructure Created Successfully!
  ========================================
  
  1. Get Kubeconfig:
     tofu output -raw kubeconfig > kubeconfig.yaml
     export KUBECONFIG=./kubeconfig.yaml
     kubectl get nodes
  
  2. Get Database Connection Info:
     DB_HOST:     ${replace(scaleway_sdb_sql_database.zitadel_db.endpoint, "postgres://", "")}
     DB_NAME:     ${scaleway_sdb_sql_database.zitadel_db.name}
     DB_USER:     ${scaleway_iam_application.zitadel_app.id}
     DB_PASSWORD: (run: tofu output -raw db_password)
     
     Full connection string:
     tofu output -raw db_connection_string
  
  3. Registry:
     ${data.scaleway_registry_namespace.srdp_registry.endpoint}
  
  4. Private Network:
     ID: ${scaleway_vpc_private_network.k8s_network.id}
  
  ========================================
  EOT
}