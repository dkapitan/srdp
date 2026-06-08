---
status: proposed
date: 2026-06-05
decision-makers: Yannick Vinkesteijn
---

# API and access strategy

## Context and Problem Statement

SRDP runs multiple backend services (Dagster, DuckLake, PostgreSQL) and optional user-facing tools (Dagster UI, marimo, quarto). Without a unified access strategy, external consumers would need to know which internal tool to call for each operation, and each service would need its own authentication, logging, and API contract.

This ADR addresses how traffic flows through the platform at three communication levels:

1. External: how do external consumers access the core platform programmatically? (consumer → Traefik → FastAPI)
2. External through service: how do users access optional services that themselves interact with platform backends? (user → Traefik → service → platform backends)
3. Internal: how do services communicate with each other and with platform backends over the shared network? (service → service/backend)

## Considered Options

### Ingress and authentication

1. Traefik + Zitadel + oauth2-proxy forwardauth: one ingress, one identity provider, one auth middleware for all external access.
2. nginx + Keycloak: similar pattern with nginx as reverse proxy and Keycloak as identity provider.
3. Per-service OIDC: each service registers its own OIDC client and handles login independently.

### Core platform API framework

1. FastAPI: async-first Python web framework with native Pydantic integration and automatic OpenAPI generation.
2. gRPC: high-performance RPC framework with Protocol Buffers for service communication.

## Decision Outcome

### Communication levels

All external traffic enters through Traefik, which terminates TLS and enforces authentication via Zitadel + oauth2-proxy forwardauth. Behind Traefik, traffic reaches the platform through three distinct levels:

```
                               ┌─── Dagster UI (optional) ──┐
                               ├─── marimo (optional)       │
External traffic → Traefik ────┤                            │
                   (Zitadel)   ├─── quarto (optional)       │
                               │                            ▼
                               └─── FastAPI ──┬── DuckLake (read-only)
                                              ├── Platform management
                                              └── Dagster GraphQL ← ──┘
                                                     ↑
                                              (internal only)
```

Level 1, external: programmatic consumers (dashboards, CLI tools, third-party integrations) access the core platform through FastAPI. FastAPI composes results from multiple backend services (DuckLake, Dagster GraphQL, platform config) into a unified, function-oriented API. Consumers interact with capabilities (query data, trigger a job, check health), not with individual tools. Internal backends like Dagster GraphQL are never exposed directly; external orchestration access is proxied through FastAPI.

Level 2, external through service: users access optional services (Dagster UI, marimo, quarto) in a browser, routed directly from Traefik. These services then interact with platform backends internally. For example, the Dagster UI consumes GraphQL over the internal network; marimo may query DuckLake directly. Each service is registered with Traefik labels/annotations and the forwardauth middleware. No service implements its own login flow. The platform functions without any of these deployed.

Level 3, internal: services communicate with each other and with platform backends (DuckLake, PostgreSQL, Dagster GraphQL) over the shared container network. This is the service-to-platform communication described in the internal communication section below.

### Ingress and authentication: Traefik + Zitadel + oauth2-proxy

Chosen option: "Traefik + Zitadel + oauth2-proxy forwardauth", because it enforces authentication at the edge without touching service code, integrates natively with both Docker Compose (labels) and Kubernetes (IngressRoute CRDs), and Zitadel provides a self-hostable identity stack.

- Unauthenticated requests are redirected to `/oauth2/sign_in`.
- Authenticated requests receive `X-Auth-Request-User` and `X-Auth-Request-Email` headers.
- Adding a new service requires only two Traefik labels (`middlewares=zitadel-errors,zitadel-auth`).
- TLS certificates are configured once in Traefik's static config, not per service.
- For machine-to-machine access, Zitadel service accounts authenticate via the OAuth2 token endpoint.

### Unified platform API

The platform exposes a single API that composes data and operations from multiple backends (DuckLake, Dagster, platform config) into one surface. Endpoints are organized by function (data access, orchestration, platform management), not by backend tool. External consumers interact with capabilities, not with individual tools.

The API is implemented with FastAPI, which generates an OpenAPI specification directly from Pydantic models (already used throughout SRDP for settings and configuration). It runs as a container behind Traefik, receiving pre-authenticated headers from forwardauth. DuckDB runs in-process for read-only data queries. All writes go through Dagster assets and the DuckLake IO manager (see [ADR-0003](./0003-data-catalog-lineage-and-observability.md)). The API does not write to the data layer.

Each platform module registers its endpoints as a FastAPI router; new modules add a router without modifying shared application code.

### Internal communication

Services deployed internally (marimo, quarto, custom UIs) need to interact with platform data and operations. There are three approaches, and the choice can be made per service:

1. Direct access: the service connects to DuckLake or PostgreSQL over the internal network. Fastest path, but activity is invisible to the platform unless the service implements its own logging.
2. Through the FastAPI API: the service calls the same API as external consumers, over the internal network. Centralized activity tracking and consistent auth, at the cost of an additional network hop.
3. Hybrid: direct access where interactive performance matters (e.g., marimo running ad-hoc DuckDB queries), API access where observability matters more than latency (e.g., triggering jobs, accessing data that should be audited).

The trade-off is between direct access performance and centralized observability. Routing through the API means activity logging and rate limiting apply automatically. Direct access pushes that responsibility to each service.

Current state: all services communicate over the shared container network without authentication. The network boundary (Docker Compose / Kubernetes) acts as the trust boundary. This is acceptable for a single-tenant, self-hosted platform. Service-to-service authentication using Zitadel service accounts (machine-to-machine OAuth2 client credentials) becomes necessary if the platform moves to multi-tenant deployments, services cross network boundaries, or compliance requires authenticated internal calls.

### Activity logging

The platform needs to track who accessed what data and operations, when, and through which path. This is directly tied to the internal communication trade-off above: services that route through FastAPI get activity logging for free via middleware; services that access backends directly must implement their own logging or accept the gap.

The implementation approach (JSONL files, database table, or external logging service) has not been decided.

### Consequences

- Good, because authentication is enforced once at the Traefik edge for all external access, both services and API.
- Good, because FastAPI composes multiple backends into a unified API surface. External consumers interact with functions, not tools. Internal APIs like Dagster GraphQL are never exposed directly.
- Good, because adding a new service requires only Traefik labels, no auth code.
- Good, because automatic OpenAPI docs mean consumers can generate typed clients without manual spec maintenance.
- Bad, because the forwardauth round-trip adds one hop per authenticated request.
- Bad, because DuckDB serves API queries in-process, and it is not always predictable upfront whether a query will be lightweight or expensive. Heavy queries can be offloaded to Dagster jobs, but the boundary between "serve directly" and "offload" needs to be defined per endpoint.

## Pros and Cons of the Options

### nginx + Keycloak

- Good, because nginx is widely known.
- Bad, because Keycloak is heavyweight and resource-intensive for a single-tenant self-hosted setup.
- Bad, because nginx does not have the same native Docker/Kubernetes label-driven config model as Traefik.

### Per-service OIDC

- Good, because each service is independently deployable.
- Bad, because each service must maintain its own OIDC client, session handling, and token refresh logic.
- Bad, because inconsistent auth UX across services.

### gRPC

- Good, because high performance for internal service-to-service communication.
- Good, because Protocol Buffers enforce a strict API contract.
- Bad, because browser clients cannot call gRPC directly without a proxy (gRPC-Web).
- Bad, because Pydantic models cannot be reused; data schemas must be duplicated as `.proto` definitions.
- Bad, because no auto-generated interactive documentation (unlike OpenAPI/Swagger).
