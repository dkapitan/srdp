---
title: Architectural Decision Records
icon: lucide/landmark
---

# Architectural Decision Records

Decisions that shape the platform's architecture, recorded using the [MADR](https://adr.github.io/madr/) format. See [Contributing](../07-contributing.md#architectural-decision-records-adrs) for when and how to write an ADR.

| ADR | Status | Decision |
|:---|:---|:---|
| [0001 — Platform architecture and distribution](./0001-platform-architecture-and-distribution.md) | Proposed | Single package with extras, base images for client deployment, four platform layers, semver over an explicit public API |
| [0002 — API and access strategy](./0002-api-and-access-strategy.md) | Proposed | Traefik + Zitadel at the edge, FastAPI as unified API, zero-trust internal model with a read/write split, audit logs on blob |
| [0003 — Data catalog, lineage, and observability](./0003-data-catalog-lineage-and-observability.md) | Proposed | DuckLake as mandatory IO wrapper, OpenLineage core with a pluggable backend (default PostgreSQL; optional Marquez), layered observability, failure-mode matrix and drift detection |
| [0004 — Data organization and ingestion](./0004-data-organization-and-ingestion.md) | Proposed | Configurable medallion layers (landing/raw/curated), raw append-only invariant, governed erasure, landing-zone-first ingestion |
| [0005 — Authorization and data access](./0005-authorization-and-data-access.md) | Proposed | API as the policy enforcement point, project-scoped RBAC, Zitadel for identity and grants, read/write split |
| [0006 — Deployment and project isolation model](./0006-deployment-and-project-isolation-model.md) | Proposed | Deployment is the isolation unit; a project is its own DuckLake catalog (project/layer/entity) |
| [0007 — Compute, execution, and scaling](./0007-compute-and-scaling.md) | Proposed | In-process executor (k8s optional), tiered read paths, hybrid serve-vs-offload with async jobs, writes via Dagster |
