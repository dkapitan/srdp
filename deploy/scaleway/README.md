# SRDP on Scaleway — deployment blueprint

Terraform blueprint for deploying **SRDP** (Single Repo Data Platform) on
Scaleway Kapsule. It is reusable: nothing company-specific is hardcoded in the
Terraform. Org identity (Project IDs, prefix, region, SCW key) lives in `.env`;
all environment knobs (CIDRs, cluster sizing, Postgres tier) live in each env's
`terraform.tfvars`. Copy `.env.example` + the tfvars, fill them in, and apply.

This mirrors the Scaleway/Azure landing-zone pattern: a hub-spoke architecture
and GitOps model built on Scaleway-native primitives. The mapping to the
equivalent Azure services is kept below as reference; where Scaleway genuinely
diverges, the difference is called out inline and tracked in
[docs/BACKLOG.md](docs/BACKLOG.md).

## Architecture decisions (locked)

| Decision | Choice |
|---|---|
| Topology | **Hub-spoke**: a connectivity hub + dev/stage/prod spokes |
| Environments | 4 Scaleway **Projects** in one Organization: hub / dev / stage / prod |
| Region | Single region — `nl-ams` (NL data residency) |
| IaC | Terraform, **directory-per-env** (no workspaces) |
| State | **Per-Project** Object Storage (S3) backend (state never crosses envs) |
| Connectivity | Spokes **peered** to the hub via `scaleway_vpc_connector` |
| Egress | Per-spoke **Public Gateway** (NAT). No managed L7 firewall — see below |
| Compute | Kapsule (Cilium): always-on system pool + scale-from-zero memory pool for DuckDB/Polars |
| Lakehouse | **Object Storage** (S3), accessed via an IAM key (no pod identity on Scaleway) |
| Postgres | **Managed Database (RDB)**, private network only (Zitadel + Dagster + DuckLake) |
| Registry | **One Container Registry in the hub**, private; clusters pull with an IAM key |
| Secrets | **Secret Manager** + External Secrets (Scaleway provider) |
| Compute isolation | Kapsule **full isolation** (private nodes, egress via Public Gateway); API is public + **ACL-locked to the gateway IP** (Kapsule has no private API) |
| Mesh | **Headscale** control plane (hub) + a per-spoke **mesh-router VM** in the PN (advertises PN CIDR + the API /32) |
| CI | **GitHub Actions** (hosted runners + `SCW_*` secrets); optional in-VPC self-hosted runner module |

## How this maps from Azure

| Azure | Scaleway |
|---|---|
| Subscriptions | Projects |
| VNet + peering | VPC per Project; `scaleway_vpc_connector` is **optional/off** — hub services are public+IAM, so no private peering is needed (see BACKLOG) |
| Azure Firewall (forced tunnel) | Public Gateway NAT (+ VPC ACLs) — **no native L7** |
| AKS (private API) | Kapsule + `scaleway_k8s_acl` (API locked to PN/mesh) |
| ADLS Gen2 + workload identity | Object Storage + IAM key (**static creds**) |
| Azure DB for PostgreSQL | Managed Database (RDB) |
| Key Vault | Secret Manager |
| ACR | Container Registry |
| `microsoft.flux` extension | Flux via Helm (`flux2` + `flux2-sync`) |
| Azure DevOps + VMSS agents | GitHub Actions + self-hosted runner Instance |

## Layout

```
modules/
  hub-network/    hub VPC + Private Network
  egress-gateway/ Public Gateway + NAT (egress; the "firewall" analogue)
  networking/     spoke VPC + Private Network
  registry/       Container Registry (hub)
  lakehouse/      Object Storage buckets (landing/lakehouse/staging)
  postgres/       Managed Database (RDB) on the PN + databases
  kapsule/        cluster + system/compute pools + API ACL
  iam-app/        IAM application + policy + API key (workload-identity stand-in)
  secrets/        Secret Manager secrets + versions
  flux/           Flux install + per-env GitRepository/Kustomization
  headscale-vm/   mesh control plane (hub)
  mesh-router/    per-spoke subnet-router VM (PN CIDR + API /32 over the mesh)
  ci-runner/      OPTIONAL in-VPC GitHub Actions runner (not deployed by default)
envs/
  hub/                    connectivity: VPC, egress, registry, Headscale
  dev/  stage/  prod/     workload spokes (peered to the hub)
deploy/
  bootstrap/    per-Project Object Storage state buckets
  clusters/     per-env Flux entrypoint (srdp + platform + mesh)
  srdp/         the umbrella chart deploy (base + per-env overlays)
  platform/     External Secrets (Scaleway provider)
  mesh/         Headscale subnet routers
```

## Getting started

Company-specific config (Project IDs, org prefix, region, SCW key) lives in
**`.env`** — copy `.env.example` and fill it in. Everything is driven from there
via the **Justfile**; no Project IDs or org names are hardcoded in the Terraform.

Per-environment knobs (PN CIDRs, Kapsule sizing, Postgres tier, the GitOps repo
URL, your SSH public key) live in **`envs/<env>/terraform.tfvars`**. The shipped
tfvars carry sensible defaults and a few placeholders — replace
`AAAA_REPLACE_WITH_YOUR_PUBLIC_KEY` and `https://github.com/your-org/srdp.git`
before applying. The spoke `main.tf` files are identical across dev/stage/prod;
only the tfvars differ.

```bash
cp .env.example .env        # set ORG_PREFIX + four PROJECT_ID_* + SCW_ACCESS/SECRET_KEY
# edit envs/*/terraform.tfvars  # SSH key + git_repo_url placeholders, sizing
just doctor                 # check tooling/config
just bootstrap-all          # state backends + hub, then all spokes
```

> **Before applying:** verify your Scaleway identity / raise quotas at
> <https://console.scaleway.com/organization/quotas>. Fresh Organizations have a
> **0 quota** for the memory-optimized **POP2** instance types the compute pool
> uses, so Kapsule node creation fails until that's lifted. The API key also needs
> **`ObjectStorageFullAccess`** and its **preferred Project set to hub** (the S3
> state backend resolves buckets only within the key's preferred Project). See
> [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

Terraform is pinned to **1.10.3** (`.tool-versions`). One-time: set the registry
`REPLACE-PREFIX` in `deploy/srdp/base/` (see [deploy/srdp](deploy/srdp/README.md)).

For the full end-to-end runbook see **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)**.

## Apply order (what `bootstrap-all` does)

```
bootstrap-state hub/dev/stage/prod  → per-Project S3 state buckets
up hub                              → VPC + egress + Container Registry + Headscale
                                      (outputs: hub_vpc_id, registry_endpoint, headscale_public_ip)
up dev / stage / prod               → spokes: VPC peered to the hub, Kapsule, RDB,
                                      Object Storage, Secret Manager, Flux, CI runner
```

The hub must apply first — spokes read its **VPC id** and peer to it (the
Justfile injects `hub_vpc_id` from the hub state into spoke applies).

## Notable divergences from Azure (be honest about these)

- **No managed L7 egress firewall.** Azure Firewall FQDN allow-lists have no
  Scaleway equivalent; egress is Public Gateway NAT + L3/L4 VPC ACLs. FQDN
  filtering, if needed, runs in-cluster (forward proxy). Tracked in the backlog.
- **No pod workload identity.** Scaleway has no OIDC federation for pods, so the
  lakehouse is reached with a static IAM key (synced via ESO) rather than keyless
  identity.
- **Kapsule API is a public endpoint, ACL-locked** — not a private IP like an AKS
  private cluster. Add your mesh egress to `api_extra_allowed_cidrs`.
