---
status: proposed
date: 2026-06-08
decision-makers: Yannick Vinkesteijn
---

# Authorization and data access

## Context and Problem Statement

Edge authentication (see [ADR-0002](./0002-api-and-access-strategy.md)) establishes who a principal is. It does not decide which data that principal may read or write. That is authorization, and it is the platform's most security-critical decision.

The hard part is that DuckLake and DuckDB have no native per-row or per-column security, so authorization cannot be pushed into the query engine. The platform must decide where data-access control is enforced and what the access model is. Access is scoped to projects, which are the unit of data organization and isolation (see [ADR-0006](./0006-deployment-and-project-isolation-model.md)).

## Considered Options

### Where enforcement lives

1. In the engine: rely on DuckDB/DuckLake row and column security. Not available; the engine has none.
2. At the API as a policy enforcement point: a thin authorization layer maps the authenticated principal and the requested resource to a permission, and constructs the scoped, read-only connection.
3. In each service independently: every tool implements its own checks.

### Access model

1. Project-scoped RBAC: roles granted per project (reader, writer, admin), plus service-access roles.
2. ABAC: attribute-based policies evaluated per request.

### Where grants are stored

1. Zitadel roles and claims, now; an optional PostgreSQL policy store later for finer rules.
2. A dedicated policy engine (for example OPA) from the start.

## Decision Outcome

### Enforcement at the API; identity is not enforcement

Chosen option: "At the API as a policy enforcement point." Zitadel supplies identity and role claims in the token, but it does not enforce data access. A thin enforcement module, implemented as a FastAPI dependency, is the policy enforcement point (PEP): it maps the authenticated principal and the requested resource to a permission, and builds the project-scoped, read-only connection that the request runs against.

There are two enforcement layers, because there are two kinds of access:

- Service access is enforced at the Traefik edge using Zitadel roles (who may reach the Dagster UI, marimo, quarto, the API). Every externally exposed route carries its own edge-level role policy, distinct from data RBAC: edge authorization decides who may reach a service, data RBAC decides what they may read once there.
- Data access is authorized at the API, which is the policy decision and provisioning point, not necessarily the query path. The PEP maps principal and resource to a permission and issues a project-scoped, read-only connection that attaches only the catalogs the user may read (see [ADR-0006](./0006-deployment-and-project-isolation-model.md)). The query itself may then run directly in a tool's process (the default Tier A read in [ADR-0007](./0007-compute-and-scaling.md)) or be routed through the API or a logging wrapper for higher tiers. The invariant is that no principal ever obtains a connection or credential wider than their grants; only the PEP can issue one, because the engine cannot enforce row or column scope itself.

This keeps the strongest security guarantee in one auditable place rather than scattered across services.

### Access model: project-scoped RBAC

Chosen option: "Project-scoped RBAC". Roles are granted per project, which is the natural grant boundary because a project is its own DuckLake catalog. The default role taxonomy:

| Role | Grants |
|:---|:---|
| Project reader | Read-only scoped connection to the project's catalog; read endpoints |
| Project writer | Reader plus the ability to trigger ingestion and Dagster jobs for the project |
| Project admin | Writer plus managing grants and project lifecycle |
| Service roles | Access to specific services (Dagster UI, marimo, quarto) independent of project data grants |

RBAC is chosen over ABAC because the access question the platform actually has is "which projects may this user read or write," which roles express directly. ABAC's per-request attribute evaluation is more power than the model needs today.

### Grants in Zitadel now; policy store later

Chosen option: "Zitadel roles and claims now, optional PostgreSQL policy store later." Role grants live in Zitadel and arrive as token claims, reusing the existing identity stack with no new component. If finer-grained rules are later required (for example per-table or conditional grants), a PostgreSQL policy store the PEP consults is added without changing where enforcement happens. A standalone policy engine is deliberately deferred until the rules justify it.

### Reads, writes, and audit

- Writes go through Dagster by default (see [ADR-0002](./0002-api-and-access-strategy.md), [ADR-0007](./0007-compute-and-scaling.md)); the writer role gates who may trigger them.
- Reads run on a read-only scoped connection, so a reader physically cannot mutate data.
- Read-only solves the mutation risk but not read confidentiality (who looked at what), which is a separate concern. Read-audit granularity is a per-deployment policy: session and grant level by default, escalating to per-query for sensitive deployments (see the read tiers in [ADR-0007](./0007-compute-and-scaling.md)). API access is always audited per request.

### Consequences

- Good, because enforcement lives in one auditable place (the API PEP) rather than in an engine that cannot do it or scattered across services.
- Good, because project-scoped RBAC matches the catalog-per-project boundary: a grant is attaching a catalog, a revoke is detaching it.
- Good, because reusing Zitadel for grants adds no new infrastructure, while leaving room for a policy store when rules grow.
- Good, because the read and write split makes reader access incapable of mutation by construction.
- Bad, because authorization is application code on the request path, so the PEP must be correct and is itself security-critical.
- Bad, because read confidentiality at per-query granularity requires routing reads through the API or a logging wrapper, which costs the direct-read performance of the default path.

## Pros and Cons of the Options

### Enforcement in the engine

- Good, because in-engine row and column security would be the simplest mental model.
- Bad, because DuckDB and DuckLake do not provide it, so it is not an option.

### Enforcement in each service

- Good, because services stay independent.
- Bad, because the platform's most critical guarantee would be duplicated and inconsistently implemented across tools.

### ABAC from the start

- Good, because maximally expressive.
- Bad, because it adds policy-evaluation machinery for rules the project-scoped model does not yet need.

### Dedicated policy engine from the start

- Good, because centralizes complex policy.
- Bad, because it is a new component to run and learn before the rule complexity justifies it; Zitadel claims cover current needs.
