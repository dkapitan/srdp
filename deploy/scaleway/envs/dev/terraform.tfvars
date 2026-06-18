# DEV spoke. project_id, hub_project_id, hub_vpc_id, prefix, region, zone and
# headscale_url are injected by the Justfile (from .env / the hub state).
# Generated secrets (postgres password, zitadel masterkey, oauth cookie) are
# created by Terraform and stored in Secret Manager — no value needed here.

environment = "dev"

# --- Network. /16 VPC space, /20 PN subnet. Keep distinct from other envs. ---
pn_vpc_cidr    = "10.10.0.0/16"
pn_subnet_cidr = "10.10.0.0/20"

# --- Kapsule sizing (dev: smallest). ----------------------------------------
system_node_count = 1
compute_node_type = "POP2-4C-16G"
compute_min_count = 0
compute_max_count = 2

# --- Postgres (dev: single small node, no HA). ------------------------------
postgres_node_type = "DB-DEV-S"
postgres_ha        = false

# --- GitOps repo Flux reconciles. Set to your SRDP repo. --------------------
git_repo_url = "https://github.com/your-org/srdp.git"

# SSH public key for break-glass access to the mesh-router VM.
runner_ssh_public_key = "ssh-ed25519 AAAA_REPLACE_WITH_YOUR_PUBLIC_KEY ops@example.com"

# After the hub applies, add the Headscale public IP so the cluster API stays
# reachable while you bring the mesh up:
# api_extra_allowed_cidrs = ["203.0.113.10/32"]
