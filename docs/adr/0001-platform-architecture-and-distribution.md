---
status: proposed
date: 2026-06-05
decision-makers: Yannick Vinkesteijn
---

# Platform architecture and distribution

## Context and Problem Statement

SRDP is a composable data platform that assembles open-source components into a single deployable stack. The platform itself contains no business logic: it is an empty shell that client projects fill with their own data pipelines, assets, and transformations.

This ADR addresses two questions:

1. Distribution: how is the platform packaged, installed, and deployed? The primary path is installing `srdp` as a package dependency, requiring no platform engineering expertise. Advanced users may also fork or template the repository for full control over the platform internals. Both modes must work on a developer laptop and a production cluster with the same service topology.
2. Extension: how do clients get their own pipeline code into a running SRDP instance, and how do they deploy it?

## Considered Options

1. Single `srdp` PyPI package with optional extras, Docker Compose and Helm as deployment targets. Clients build custom images extending srdp base images to deploy their pipeline code.
2. uv workspace: clients clone the `srdp` repo and add their project as a workspace member, each with its own `pyproject.toml`.
3. CLI-driven (`srdp init / dev / deploy`): a wrapper that scaffolds client projects, builds images, and manages deployment. Bare Docker Compose and Helm remain available for advanced users.

## Decision Outcome

Chosen option: "Single package with base images", because it minimises the number of things a customer needs to understand while supporting the full range from laptop to production. The CLI (option 3) is under consideration as a future abstraction layer on top of this foundation.

### Platform layers

The platform is composed of four layers:

Core library (`src/srdp/`): the Python package clients install. Contains IO managers, resources, base asset patterns, and the FastAPI API server. This is what `uv add srdp` provides.

Core infrastructure services (containers, always deployed): PostgreSQL, Traefik, Dagster (daemon + code server + GraphQL), Zitadel, and oauth2-proxy. These form the platform runtime and are deployed via Docker Compose or Helm. They are not Python packages.

Optional services (containers, added as needed): Dagster UI (webserver), marimo, quarto, and potentially others. These extend the platform with additional capabilities. Some may import `srdp` (e.g. through a Python client), others are standalone. The platform functions without any of these deployed.

Optional extras (Python dependencies, environment-specific): cloud storage backends and deployment-target-specific dependencies. These are genuine optional extras because the platform functions without them on a default local deployment.

```
uv add srdp                # core library (Dagster, Polars, DuckDB, FastAPI)
uv add srdp[azure]         # + Azure Blob Storage backend
uv add srdp[k8s]           # + Kubernetes executor (dagster-k8s)
```

### Platform deployment

| Target | Location | Use case |
|:---|:---|:---|
| Docker Compose | `deploy/docker/` | Local development, single-node production VMs |
| Helm chart | `deploy/kubernetes/srdp-chart/` | Kubernetes clusters |
| OpenTofu | `deploy/opentofu/` | Cloud VM provisioning (GCP, Scaleway) |

Both Docker Compose and Helm define the same logical set of services (core infrastructure + optional services). Adding a new service means adding a container definition in both places with standard Traefik labels/annotations (see [ADR-0002](./0002-api-and-access-strategy.md)).

### Client project deployment

A client project is a separate repository that imports `srdp` as a dependency and contains pipeline code (Dagster assets, dlt sources, transformations). To deploy, the client builds a Docker image extending an srdp base image:

```dockerfile
FROM srdp/dagster-worker:latest
COPY . /app
RUN uv sync
```

The resulting image contains both the platform library and the client's assets. It slots into the existing Docker Compose or Helm deployment by replacing the default worker image.

`projects/default-etl/` in this repo serves as a reference implementation and starting template for client projects.

### Extension model

Data layer: what the platform ingests, transforms, and exposes. Extensions live in client projects and import from `srdp`. No changes to the `srdp` repo required.

- Add a data source: define a dlt pipeline, register it as a Dagster asset.
- Add a transformation: write a Dagster asset that reads from DuckLake and writes back through the IO manager.
- Add a compute profile: use the K8s resource profiles in `srdp.resources.k8s` as job tags.

Service layer: what infrastructure or tooling services the platform runs. Extensions require a change to the `srdp` repo.

- Add a service: add a container to Docker Compose / Helm with Traefik middleware labels.
- Add a storage backend: implement the `StorageBackend` interface (`srdp.io.storage`), which requires two methods: `get_base_path()` and `configure_duckdb()`.

### Consequences

- Good, because one package to install, version, and document. Client projects have a single dependency.
- Good, because Docker Compose and Helm mirror the same topology, with no conceptual gap between environments.
- Good, because client projects are cleanly external with their own repo, lockfile, and release cycle.
- Good, because base images give clients a standard deployment mechanism without requiring platform expertise.
- Good, because optional extras are genuinely optional (cloud backends, k8s executor), not functionally mandatory.
- Bad, because service config changes must be applied in both Docker Compose and Helm. This is mitigated by sharing configuration through external env and config files, but structural changes (adding a service, changing port mappings) still require updates in both places.
- Bad, because without a CLI, clients must understand Docker image builds and Compose/Helm configuration to deploy.

## Pros and Cons of the Options

### uv workspace

- Good, because client projects can resolve against the platform source directly, with no published package needed.
- Bad, because clients must clone the full `srdp` repo to start working.
- Bad, because workspace membership couples client release cycles to the platform repo, making independent versioning difficult.

### CLI-driven

- Good, because it lowers the barrier to entry for clients with no Docker or Kubernetes experience.
- Good, because it can enforce conventions (project structure, image naming, deployment config).
- Bad, because the CLI becomes a critical dependency that must be maintained alongside the platform.
- Bad, because it adds an abstraction layer that advanced users may need to bypass, creating two paths to support.
