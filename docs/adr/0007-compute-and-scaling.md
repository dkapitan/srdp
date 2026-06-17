---
status: proposed
date: 2026-06-08
decision-makers: Yannick Vinkesteijn
---

# Compute, execution, and scaling

## Context and Problem Statement

SRDP runs transformations as Dagster assets and serves data through the API and interactive tools. DuckDB executes in-process, which makes queries fast but co-locates compute with whatever process runs them. This ADR decides how runs are executed, how the API serves data without becoming a compute bottleneck, and where the boundary sits between serving a query directly and offloading it to an orchestrated job.

The API itself is not the scaling problem: it is stateless and scales horizontally (see [ADR-0002](./0002-api-and-access-strategy.md)). The problem is heavy query compute and run isolation.

## Considered Options

### Run execution

1. In-process or multiprocess executor for Compose; the `dagster-k8s` executor (one pod per run) as an optional extra on Kubernetes.
2. Always one isolated container or pod per run.
3. Always in-process.

### Serve versus offload

1. Hybrid: known-heavy endpoints submit async jobs up front; a bounded synchronous read path fails over to a job when it exceeds its limits.
2. Pure failover: always try synchronously, fail over when bounds are exceeded.
3. Pre-flight cost estimation: predict cost before running and route accordingly.

## Decision Outcome

### Run execution

Chosen option: "In-process or multiprocess for Compose; `dagster-k8s` optional on Kubernetes." Single-node deployments use the in-process or multiprocess executor, which needs no extra infrastructure. Kubernetes deployments can opt into the `dagster-k8s` executor, which runs one pod per run for isolation. This matches the core-versus-optional boundary in [ADR-0001](./0001-platform-architecture-and-distribution.md): the Kubernetes executor is an optional extra, not core.

### The read path is tiered

Reads are served at the tier that matches a deployment's sensitivity and trust, so the platform does not centralize compute just to obtain logs.

| Tier | Path | Compute | Audit | When |
|:---|:---|:---|:---|:---|
| A | Direct read-only scoped connection | In the tool's process | Session and grant level | Default, non-sensitive |
| B | Direct connection via a platform logging wrapper | In the tool's process | Per query | Sensitive, trusted analyst code |
| C | Server-side query gateway | Centralized, scaled with replicas | Per query, central auth | Untrusted code or hard central audit |

Tier A is the default and the fastest: the connection attaches only the project catalogs the user may read (see [ADR-0006](./0006-deployment-and-project-isolation-model.md)), compute is distributed in the tool's process, and there is no API hop. Tier B adds per-query audit with a client-side wrapper that logs each query before executing it locally, requiring that the platform provisions the connection and the tool never receives raw storage credentials. Tier C centralizes compute behind a gateway only when code is untrusted or central audit is mandatory.

Every tier consumes a short-lived capability token, and engine credentials are materialized against it (see [ADR-0008](./0008-identity-propagation-and-data-contracts.md), [ADR-0009](./0009-data-plane-credential-materialization.md)). Tier A serves coarse project grants only: fine-grained contract grants (column and row scope) are enforceable only on the mediated Tier C path, because direct engine credentials cannot subset DuckLake columns or filter rows.

The Tier C gateway protocol is a deferred sub-decision. The concrete candidates are the OData endpoint and a future Quack server (HTTP via FastAPI) versus Arrow Flight SQL (see [ADR-0008](./0008-identity-propagation-and-data-contracts.md)); it does not need resolving until a Tier C deployment exists.

### Serve versus offload: hybrid

Chosen option: "Hybrid." A query's cost cannot be reliably predicted before it runs, so the platform does not try to. Instead:

- Endpoints known to be heavy submit as async jobs up front, avoiding a wasted synchronous attempt.
- The synchronous read path, where the query is mediated by the platform (the API, the Tier B logging wrapper, or the Tier C gateway), is hard-bounded by a client-enforced timeout plus row and memory caps (DuckDB supports query interrupt and memory limits). A query that exceeds the bound is interrupted and resubmitted as an async job. Bounded-sync-then-failover is the backstop for queries that turn out heavier than expected. A pure Tier A direct read runs in the tool's own process and is bounded only by the per-connection memory limit set when the PEP provisions it; a deployment that needs enforced timeouts or automatic failover for ad-hoc reads routes them through Tier B or C.

Async work follows the request-reply pattern: the API accepts the request (a landing-zone drop or an explicit materialize trigger), triggers a Dagster run, and immediately returns a job or run id (HTTP 202), optionally with queue position or an expected end time. The caller polls run status (for example `POST /api/assets/{key}/materialize` then `GET /api/runs/{id}`) or, optionally, receives a push notification (webhook or callback) when the run completes. Heavy queries always run as Dagster jobs so they never block API request workers.

### Refinements

- Result-return channel: a heavy read produces data, not just status. The job writes its result to a result area (a temporary table or object with a TTL), and the caller fetches it by job id through an authorized endpoint.
- Idempotency: job submission takes an idempotency key, so a retry or double-submit returns the existing job id rather than launching a duplicate run.
- Sync concurrency limit: because DuckDB's memory limit is per process, per-query caps are not enough; the synchronous path also bounds concurrency (a small queue) so a few heavy reads cannot starve an API worker.
- Timeout mechanism: DuckDB has no native per-statement SQL timeout; it is enforced client-side via connection interrupt on a timer plus a memory limit.
- Scoped write credentials: the API's landing-drop credentials reach the landing zone only, never raw or beyond; operational write endpoints stay narrow and audited so they do not become a backdoor around Dagster lineage (see [ADR-0004](./0004-data-organization-and-ingestion.md)).

### Writes default through Dagster

All writes to lake-managed layers go through Dagster by default, for lineage, retries, asset checks, and scheduling (see [ADR-0002](./0002-api-and-access-strategy.md), [ADR-0004](./0004-data-organization-and-ingestion.md)). A direct API write path exists only as an explicit, audited exception.

### Scaling boundaries

The platform has components that scale horizontally and components that do not. This table makes the boundaries explicit so deployments can plan around them.

Scales horizontally:

| Component | How |
|:---|:---|
| FastAPI (API server) | Stateless; multiple workers per host, multiple replicas behind Traefik |
| Dagster webserver | Stateless (state in PostgreSQL); multiple replicas behind a load balancer |
| Traefik | Stateless; standard reverse proxy scaling |
| Dagster assets (on K8s) | With the `dagster-k8s` executor, each run gets its own pod |

Single-instance or bounded:

| Component | Constraint | Mitigation |
|:---|:---|:---|
| PostgreSQL | Single instance; holds catalog metadata, Dagster state, and identity data. The most critical scaling boundary. | Managed PostgreSQL with automated failover and read replicas for heavy read loads |
| Dagster daemon | Single instance by design (coordinates schedules, sensors, run queue). Cannot be replicated. | Lightweight process; rarely the bottleneck in practice. Monitor for run queue depth. |
| Dagster code server | One replica per code location | Each client project is its own code location; scaling is per-project, not per-replica |
| DuckDB in-process | Compute co-located with the process running the query; bounded by single-node memory and CPU | Memory limits per connection; heavy queries offloaded to async Dagster jobs (see serve-vs-offload above) |
| Object storage | Throughput and IOPS limits vary by provider and tier | Provider-specific tuning; DuckLake's file-level parallelism helps |

### Consequences

- Good, because single-node deployments run with no extra execution infrastructure, while Kubernetes deployments get per-run isolation when they want it.
- Good, because the default read path (Tier A) keeps compute distributed and adds no API hop, so it loses no performance.
- Good, because the platform bounds and fails over instead of guessing query cost, which cannot be predicted reliably.
- Good, because the async job contract (job id, poll or notify, result channel, idempotency) is a standard, well-understood pattern.
- Good, because heavy compute never blocks API request workers.
- Bad, because the failover path can waste work: a query may run up to the timeout before being rejected and resubmitted; declaring known-heavy endpoints async up front mitigates but does not eliminate this.
- Bad, because per-query read audit (Tier B or C) trades away some of Tier A's direct-read performance.
- Bad, because the Tier C gateway, if ever needed, reintroduces centralized compute that must be scaled separately.

## Pros and Cons of the Options

### Always one isolated container per run

- Good, because maximal isolation between runs.
- Bad, because per-run container startup is heavy overhead on a single-node Compose deployment that does not need it.

### Always in-process

- Good, because simplest execution.
- Bad, because it offers no run isolation on clusters where that matters.

### Pre-flight cost estimation

- Good, because it would route precisely if estimates were trustworthy.
- Bad, because query cost cannot be reliably estimated before execution, so the router would be wrong often enough to be harmful.
