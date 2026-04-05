# AGENTS.md — SRDP Codebase Guide for AI Coding Assistants

This file describes the structure, conventions, and constraints of the **Single Repo Data Platform (SRDP)** repository. Read this before making any changes.

---

## What this repository is

SRDP assembles a modern open-source data platform — Zitadel (IAM), Traefik (ingress), Dagster (orchestration), Polars/DuckDB (data processing), marimo (notebooks), and Quarto (reporting) — into a single Git repository with two deployment targets:

- **`docker/`** — Docker Compose stack for local development and a GCP Compute Engine VM deployment
- **`kubernetes/`** — Helm umbrella chart + Scaleway Kapsule provisioned by OpenTofu

The repository is structerd as a monorepo (single repo, all infrastructure and apps together) for simplicity.

---

## Repository layout

```
srdp/
├── Justfile                        # Only task runner — use this, not raw shell
├── README.md
├── AGENTS.md                       # This file
├── zensical.toml                   # Documentation site config
├── srdp.archimate                  # Architecture model (do not edit)
├── docs/                           # Documentation source (Markdown, built by Zensical)
├── docker/                         # Docker Compose deployment target
│   ├── docker-compose.yml
│   ├── docker-compose.override.yml # Local TLS (self-signed mkcert certs)
│   ├── docker-compose.prod.yml     # Production override (Let's Encrypt ACME)
│   ├── .env.example                # Secret template — copy to .env, never commit .env
│   ├── traefik/traefik.yml
│   ├── apps/marimo/                # Marimo app image source
│   ├── apps/quarto/                # Quarto app image source
│   └── opentofu/gcp/               # OpenTofu for GCP Compute Engine VM
└── kubernetes/                     # Kubernetes + Helm deployment target
    ├── opentofu/                   # OpenTofu for Scaleway Kapsule cluster
    │   ├── main.tf
    │   ├── secrets.sh.example      # Scaleway credential template
    │   └── build-and-push.sh       # Build + push all 3 images to Scaleway registry
    ├── apps/srdp-etl/              # Dagster user code (separate container image)
    │   └── definitions.py          # ALL assets, jobs, and schedules live here
    └── srdp-chart/                 # Helm umbrella chart
        ├── Chart.yaml              # Dependency versions — change here to upgrade
        ├── values.yaml             # Base values (local.dev defaults)
        ├── values-local.yaml       # Local k8s overrides
        ├── values-prod.example.yaml
        └── templates/
```

---

## Task runner

**Always use `just`**. Run `just` at the repo root to list all commands.

| Command | What it does |
|:---|:---|
| `just local-tls` | Generate mkcert certs + create `custom-ingress-cert` K8s secret |
| `just local-deploy` | `helm dependency update` + `helm upgrade --install` (values.yaml + values-local.yaml) |
| `just local-delete` | Helm uninstall + delete all PVCs |
| `just prod-apply` | `source secrets.sh && tofu apply -auto-approve` |
| `just prod-traefik-only` | Deploy only Traefik to obtain the load balancer IP |
| `just prod-auth-only` | Deploy Traefik + Zitadel + OAuth2-Proxy only |
| `just prod-full` | Full production Helm deploy from `values-prod.yaml` |
| `just prod-uninstall` | Delete Traefik LB service → Helm uninstall → delete PVCs |

---

## Secrets and configuration

**Never commit secrets.** The following are gitignored and must never be added to version control:

```
.env
secrets.sh
values-prod.yaml
kubeconfig.yaml
certs/
login-client.pat
```

Work from their example counterparts:
- `docker/.env.example` → `docker/.env`
- `kubernetes/opentofu/secrets.sh.example` → `kubernetes/opentofu/secrets.sh`
- `kubernetes/srdp-chart/values-prod.example.yaml` → `kubernetes/srdp-chart/values-prod.yaml`

Placeholders in example files use the `CHANGE_ME_*` prefix convention.

---

## Helm chart conventions

- **Release name**: `srdp` — Kubernetes service names for upstream charts are `srdp-<component>` (e.g., `srdp-traefik`, `srdp-zitadel`, `srdp-oauth2-proxy`). Custom app templates use bare names (`marimo`, `quarto`).
- **Namespace**: always `srdp`.
- **Values layering**: `values.yaml` (base) → `values-local.yaml` (local cluster) → `values-prod.yaml` (production, gitignored).
- **Every template** must be guarded by `{{- if .Values.<component>.enabled }}`.
- **Domain substitution**: `global.domain` is the single source of truth — use `<app>.{{ .Values.global.domain }}` everywhere. For local development, this is `local.dev`; for production it is the public domain.
- **TLS branching**: templates check `{{ if .Values.traefik.certResolver }}` to switch between ACME (production) and `custom-ingress-cert` (local development).
- **IngressClass**: `srdp-traefik`.

### Dependency versions (Chart.yaml)

| Chart | Version |
|:---|:---|
| traefik | 37.4.0 |
| zitadel | 9.13.0 |
| postgresql (alias: zitadel-db) | 18.1.11 |
| oauth2-proxy | 9.0.0 |
| dagster | 1.12.17 |

To upgrade a dependency, change the version in `Chart.yaml` and run `helm dependency update kubernetes/srdp-chart`.

---

## Container images

All custom images are published to the Scaleway registry: `rg.nl-ams.scw.cloud/srdp-registry/`

| Image | Source directory | Tag |
|:---|:---|:---|
| `marimo` | `docker/apps/marimo/` | `v1.0` |
| `quarto` | `docker/apps/quarto/` | `v1.0` |
| `srdp-etl` | `kubernetes/apps/srdp-etl/` | `v1.0` |

Bump the image tag in both `values.yaml` (or `values-prod.yaml`) and `build-and-push.sh` whenever a new image is built. In `values-local.yaml`, `imagePullPolicy` is set to `Never` — images must be loaded into the local cluster's containerd cache manually before deploying locally.

Build and push all images with:
```bash
source kubernetes/opentofu/secrets.sh
bash kubernetes/opentofu/build-and-push.sh
```

---

## Dagster user code

All Dagster assets, jobs, and schedules live in `kubernetes/apps/srdp-etl/definitions.py`. The module is loaded by the Dagster gRPC server via `-m definitions`.

Conventions in use:
- Assets use typed return annotations (`Output[pl.DataFrame]`, `Output[str]`)
- K8s resource profiles are module-level dicts (`BASE_RUN_K8S_CONFIG`, `FAST_LANE_K8S_CONFIG`, `BACKFILL_K8S_CONFIG`) applied via job tags
- Priority scheme: fast-lane = 5, default = 0, background = −1, backfill = −2
- `defs = Definitions(...)` is the top-level export

---

## PostgreSQL

A single in-cluster PostgreSQL instance (Bitnami chart, aliased as `zitadel-db`) serves both the `zitadel` and `dagster` databases. When changing the database password, it must be updated consistently across `values.yaml` (or `values-prod.yaml`) in multiple locations:

- `zitadel-db.auth.password`
- `zitadel.zitadel.masterkey` (separate — must be exactly 32 characters)
- `zitadel.zitadel.configmapConfig.Database.Postgres.Password`
- `dagster.postgresql.postgresqlPassword`

If PostgreSQL is redeployed with a stale PVC, the password stored on disk will not match the new secret. Delete the PVC and let the init container recreate the database.

---

## OpenTofu targets

### GCP (`docker/opentofu/gcp/`)
Provisions a single Debian 12 `e2-medium` Compute Engine VM with a static IP and firewall rules for ports 80 and 443. A startup script installs Docker, clones the repo, writes `.env` from injected variables, substitutes the public domain into config files, and starts the Docker Compose production stack.

Key variables (in `tofu.tfvars`): `gcp_project_id`, `domain_name`, `repo_url`, `acme_email`, plus sensitive secrets. Default region: `europe-west4`.

### Scaleway Kapsule (`kubernetes/opentofu/`)
Provisions a VPC, private network, Kapsule managed Kubernetes cluster (v1.32, Cilium CNI), and autoscaling node pool (`PLAY2-MICRO`, 1–3 nodes). Credentials are passed exclusively via environment variables (`SCW_ACCESS_KEY`, `SCW_SECRET_KEY`, `SCW_DEFAULT_PROJECT_ID`). The Scaleway Container Registry (`srdp-registry`) must be created manually via the Scaleway Console before running `tofu apply`.

---

## Documentation

Documentation source is in `docs/` as Markdown files, built with [Zensical](https://zensical.org/).

- Local preview: `uvx zensical serve` (live reload at `localhost:8000`)
- Build: `uvx zensical build --clean`
- Deployment: automatic via GitHub Actions on push to `main` when `docs/**` or `zensical.toml` changes

File naming convention: files are prefixed `01-` through `06-` for ordered navigation. Icons use the `lucide/` or `material/` namespace in frontmatter.

---

## Known gotchas

- **Zitadel master key** must be exactly 32 characters.
- **`imagePullPolicy: Never`** is active for local deployments — if a pod is stuck in `ImagePullBackOff`, the image is not in the local containerd cache.
- **`tofu destroy` may fail** if a Scaleway load balancer was not released first. Run `just prod-uninstall` before `tofu destroy`; if already stuck, delete the load balancer via the Scaleway API.
- **Traefik stuck in Init** after redeployment usually means the `ReadWriteOnce` PVC is still held by the previous pod. Delete the old pod or PVC to unblock it.
- **OAuth login loops** are almost always a domain mismatch — check that `global.domain`, the Zitadel OIDC redirect URI, and the `--oidc-issuer-url` in oauth2-proxy all use the same domain.
- **Dagster CrashLoopBackOff with "password authentication failed"** means the Dagster database credentials are out of sync with the PVC. Delete the `zitadel-db` PVC and redeploy.
