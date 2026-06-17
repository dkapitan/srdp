---
status: proposed
date: 2026-06-15
decision-makers: Yannick Vinkesteijn
---

# Data-plane access: credential materialization

## Context and Problem Statement

ADR-0008 decides the authorization *decision*: the PEP exchanges a validated identity token for a short-lived capability token carrying principal, project, contract reference, actions, and TTL. It does not decide how that token becomes real access to the resources that hold data and run compute. ADR-0005 (PEP, RBAC) and ADR-0007 (read tiers, writes via Dagster) name the access paths but defer the credential mechanics.

This ADR decides materialization: how a capability token is translated into concrete, scoped credentials against the three resource systems of the data plane: the query engine, object storage, and compute (Dagster).

The difficulty is an impedance mismatch. Capability tokens and data contracts express scope in rich terms (project, table, columns, rows, consent, purpose, a 15-minute lifetime). The resource systems enforce only in their own primitives:

| Permit concept | Enforcing primitive | Native fit |
|:---|:---|:---|
| project / table scope | PostgreSQL role, storage prefix, catalog attach | yes (coarse) |
| column subset | SQL projection / generated view | none (synthesized) |
| row filter (static or consent) | SQL predicate / generated view | none (synthesized) |
| masking / pseudonymization | SQL expression / generated view | none (synthesized) |
| compute (trigger-job) | Dagster run launch under a project identity | partial |
| purpose-of-use | — | none |

Every fine-grained dimension has no native enforcement primitive in DuckDB, DuckLake, or storage, and can only be enforced as synthesized SQL on a mediated path.

## Considered Options

### Engine credential mechanism (read)

1. Per-project PostgreSQL reader/writer roles plus per-prefix scoped storage credentials, materialized per capability token.
2. A platform-run DuckDB (Quack) server holding all credentials, with a server-side authorization callback.
3. Both, by tier: scoped credentials for coarse direct reads, the mediated server for fine-grained reads.

### Fine-grained enforcement mechanism (mediated)

1. Runtime SQL rewrite: the evaluator emits `SELECT <cols> … WHERE <filter>` per request.
2. Generated per-contract DuckDB views: column projection and row predicate baked into a view; access granted to the view, regenerated on contract-version change.

### Compute authorization

1. Treated as data access (a credential to "the compute resource").
2. Treated as a distinct capability: the API authorizes a job launch (`trigger-job` action) and Dagster runs it under a project-scoped writer identity.

## Decision Outcome

### Decided core

These hold regardless of the open mechanism choices:

- **Engine credentials are subordinate to the capability token.** No principal ever holds a storage, database, or session credential that outlives or outscopes the capability token it was issued against. Where a primitive has its own clock (e.g. a storage SAS), its expiry is set at or below the token TTL; where a primitive is persistent (a database role, a generated view), it is not handed to the principal as a standalone credential.
- **Materialization fans out per resource.** One capability token produces up to three independent credentials (query engine, storage, compute), each in its own primitive. Consistency across them (same scope, same lifetime, revoked together) is the platform's responsibility and the main source of risk; the seams between the three are where leaks occur.
- **Fine-grained scope is mediated-only** (consistent with ADR-0008). Column, row, masking, and consent scope are enforced only on a mediated path that executes the query on the principal's behalf, because no resource primitive enforces them. A contract-scoped principal is never issued a direct engine credential.
- **Compute is a distinct capability, not data access** (option 2 above). The API authorizes a job launch from the `trigger-job` action; Dagster executes it under a per-project writer identity. The write credential is platform-held and never materialized to the user. This is a different mechanism, audit shape, and failure mode from read access and is modelled separately.

### Open questions (to resolve with the team)

1. **Read engine mechanism.** Per-project PG roles + scoped storage credentials vs. a Quack server vs. both by tier. Quack is beta; do not commit before it stabilizes.
2. **Mediated enforcement mechanism.** Runtime SQL rewrite vs. generated per-contract views. Trade: rewrite makes the evaluator the sole boundary; views are persistent objects whose lifecycle does not match the token TTL.
3. **Lifecycle binding for persistent primitives.** How a database role or generated view is reconciled with a 15-minute token (e.g. fixed per-project roles brokered behind a connection pool vs. per-principal short-lived roles, which churn DDL on the shared PostgreSQL).
4. **Per-principal row parameter.** The capability token must carry a scope parameter for consent/per-principal row filters (ADR-0008); its shape is undecided.
5. **Local-filesystem backend.** Storage credentials cannot be scoped on a local-FS backend; direct reads there are safe only inside platform-controlled processes. Whether this remains a supported direct-read path or is restricted to mediated access must be decided.

### Consequences

- Good, because the subordination invariant gives a single, testable rule (engine credential ≤ capability token in scope and lifetime) that bounds the blast radius of any materialization bug.
- Good, because separating compute from data access keeps the write credential platform-held and out of user hands.
- Bad, because materialization is three mechanisms, not one; their consistency is custom platform code and the primary security risk in the data plane.
- Bad, because the fine-grained path has no engine backstop: the synthesized SQL (rewrite or view) is the only thing enforcing column/row scope, so its correctness is the boundary.
- Bad, because per-principal short-lived database credentials, if chosen, add role/connection churn on the single PostgreSQL already identified as the fan-in bottleneck.

### Relationship to existing ADRs

- Completes the materialization half of ADR-0008's capability-token model (the decision half stays in 0008).
- Supplies the credential mechanics ADR-0005 and ADR-0007 defer.
- Sits inside ADR-0006's catalog isolation boundary: materialization never crosses projects.
