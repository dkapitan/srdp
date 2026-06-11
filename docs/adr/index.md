---
title: Architectural Decision Records
icon: lucide/landmark
---

# Architectural Decision Records

Decisions that shape the platform's architecture, recorded using the [MADR](https://adr.github.io/madr/) format. See [Contributing](../07-contributing.md#architectural-decision-records-adrs) for when and how to write an ADR.

| ADR | Status | Decision |
|:---|:---|:---|
| [0001 — Platform architecture and distribution](./0001-platform-architecture-and-distribution.md) | Proposed | Single package with extras, base images for client deployment, four platform layers |
| [0002 — API and access strategy](./0002-api-and-access-strategy.md) | Proposed | Traefik + Zitadel at the edge, FastAPI as core platform API, services accessed directly |
| [0003 — Data catalog, lineage, and observability](./0003-data-catalog-lineage-and-observability.md) | Proposed | DuckLake + Polars + OpenLineage for in-process analytics with portable lineage |
