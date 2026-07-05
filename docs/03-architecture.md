---
title: 3. Architecture & Conventions
icon: lucide/blocks
---

# Architecture & Conventions

## Service topology

Both deployment targets (Docker Compose and Helm) run the same logical services. The full stack has 11 containers (10 running, 1 ephemeral):

| Container | Role | Image | Notes |
|:---|:---|:---|:---|
| `srdp-postgres` | Shared platform database | `postgres:17-alpine` | Hosts databases for Zitadel and Dagster |
| `srdp-traefik` | Reverse proxy, TLS termination | `traefik:v3.5.3` | |
| `srdp-zitadel-init` | Database schema bootstrap | `ghcr.io/zitadel/zitadel:v4.2.2` | Runs once then exits |
| `srdp-zitadel` | Identity provider (OIDC) | `ghcr.io/zitadel/zitadel:v4.2.2` | API, console, OIDC endpoints |
| `srdp-zitadel-login` | Hosted login UI | `ghcr.io/zitadel/zitadel-login:v4.2.2` | Separate Next.js app since Zitadel v4 |
| `srdp-oauth2-proxy` | Forward-auth middleware | `quay.io/oauth2-proxy/oauth2-proxy:v7.6.0` | |
| `srdp-dagster-code` | User pipeline code (gRPC) | Built from `projects/default-etl/Dockerfile` | Separate so pipeline code can update independently |
| `srdp-dagster-webserver` | Orchestration UI | Built from `deploy/docker/dagster-webserver.Dockerfile` | No source code — connects to code server over gRPC |
| `srdp-dagster-daemon` | Schedule & sensor execution | Same image as webserver | Must be a separate process per Dagster's architecture |
| `srdp-marimo` | Reactive notebook app | Built from `services/marimo/` | |
| `srdp-quarto` | Static reporting site | Built from `services/quarto/` | |

**Why so many containers?** Zitadel requires a one-time init container and ships its login UI as a separate app since v4. Dagster requires three processes by design: the code server (isolates user code), the webserver (UI), and the daemon (runs schedules/sensors/backfills). These cannot be merged without breaking the tools' architecture.

## Naming conventions

### Containers

All containers use the prefix `srdp-`:

```
srdp-postgres
srdp-traefik
srdp-zitadel
srdp-zitadel-init
srdp-zitadel-login
srdp-oauth2-proxy
srdp-dagster-webserver
srdp-dagster-daemon
srdp-dagster-code
srdp-marimo
srdp-quarto
```

Every container has an explicit `container_name` in `docker-compose.yml` to prevent auto-generated names.

### Networks

| Name | Purpose |
|:---|:---|
| `srdp-app` | Services exposed via Traefik (HTTP traffic) |
| `srdp-db` | Database access (PostgreSQL only) |

### Volumes

| Name | Purpose |
|:---|:---|
| `srdp-pgdata` | PostgreSQL data directory |
| `srdp-dagster-compute-logs` | Dagster compute log storage |

### Domains

Local development uses `*.srdp.localhost` with mkcert certificates:

| Domain | Service |
|:---|:---|
| `auth.srdp.localhost` | Zitadel |
| `dagster.srdp.localhost` | Dagster webserver |
| `marimo.srdp.localhost` | Marimo |
| `quarto.srdp.localhost` | Quarto |

### Databases

One shared PostgreSQL instance. Each service gets its own database and user, created by `deploy/docker/initdb/01-create-databases.sql`:

| Database | User | Used by |
|:---|:---|:---|
| `zitadel` | `zitadel` | Zitadel identity provider |
| `dagster` | `dagster` | Dagster run/event storage |

## Component configuration

### PostgreSQL

Shared across all services. The `initdb/` directory runs SQL scripts on first boot to create per-service databases. Adding a new service database means adding a `CREATE USER` / `CREATE DATABASE` pair to the init script.

### Traefik

- Docker provider discovers services via container labels.
- Static routes for Zitadel and Zitadel Login are defined in `config/traefik/traefik.yml` (file provider) because they require `insecureSkipVerify` for the self-signed backend.
- All other services are routed via Docker labels on their containers.
- TLS: mkcert certificates locally (via `tls.stores.default`), Let's Encrypt in production (via ACME cert resolver).

### Zitadel

- Runs with TLS enabled (`ZITADEL_TLS_ENABLED: true`) using the same mkcert certificates.
- `zitadel-init` runs once to bootstrap the database schema, then exits.
- `zitadel-login` is the hosted Next.js login UI, connected via a personal access token generated during init.

### OAuth2-Proxy

- Configured as a Traefik forward-auth middleware (`zitadel-auth`).
- Protects all app services (Marimo, Quarto, Dagster) — requests are redirected to Zitadel for OIDC login.
- The `dagster.srdp.localhost` domain is included in the oauth2-proxy router rule alongside the other app domains.

### Dagster

Three containers, two images:

- **dagster-webserver** and **dagster-daemon** share an image (`dagster-webserver.Dockerfile`) that installs only the `[infra]` extra — no source code. They connect to the code server over gRPC.
- **dagster-code** uses the project Dockerfile (`projects/default-etl/Dockerfile`) which installs the full `srdp` package plus project code. It runs `dagster code-server start` to expose definitions over gRPC.
- The Helm chart uses `dagsterApiGrpcArgs` to configure the same gRPC server — the Dagster Helm chart manages the command internally, so `code-server` vs `api grpc` only applies to the Docker Compose setup.
- `dagster.yaml` configures PostgreSQL storage and the run launcher (`DefaultRunLauncher` locally, `K8sRunLauncher` in production).
- `workspace.yaml` tells the webserver/daemon where to find the code server (`srdp-dagster-code:3030`).

### Marimo & Quarto

Stateless app containers. No database dependency. Routed through Traefik with the same OAuth2-Proxy auth chain as Dagster.

## Directory layout

```
config/
  dagster/
    dagster.yaml          # Dagster storage & run launcher config
    workspace.yaml        # Code server location
  traefik/
    traefik.yml           # Traefik static configuration
deploy/
  docker/
    docker-compose.yml    # Local development stack
    docker-compose.override.yml  # TLS cert mounts
    dagster-webserver.Dockerfile
    initdb/               # PostgreSQL init scripts
    certs/                # mkcert certificates (gitignored)
  kubernetes/
    srdp-chart/           # Helm umbrella chart
projects/
  default-etl/            # Example Dagster project
    Dockerfile
    src/etl/
services/
  marimo/
  quarto/
src/
  srdp/                   # Core platform library
```
