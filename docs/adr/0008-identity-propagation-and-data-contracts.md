---
status: proposed
date: 2026-06-12
decision-makers: Yannick Vinkesteijn
---

# Identity propagation, capability tokens, and data contracts

## Context and Problem Statement

ADR-0002 commits the platform to zero-trust and ADR-0005 places enforcement at the API policy enforcement point (PEP). However these decisions left three gaps yet to be closed:

1. Identity travels between services as forwardauth headers (`X-Auth-Request-*`), which any process on the internal network can forge. Header trust is network trust, the model ADR-0002 rejected.
2. The "project-scoped, read-only connection" ADR-0005 relies on has no enforcement mechanism: DuckDB applies `READ_ONLY` client-side, in the untrusted process, and a DuckLake connection materializes as raw PostgreSQL and storage credentials in the consumer's hands.
3. Revocation lag is undefined: a grant rides in tokens and sessions that stay valid until they expire, and no target is set for how fast a revoked grant must stop working. Validating a token per request confirms it is unexpired, not that the grant still exists, so without a deliberately short lifetime a revoked grant keeps working for the token's full life.

ADR-0005 also deferred fine-grained access ("optional PostgreSQL policy store later") without deciding what the policy artifact is. However, consumer surfaces are growing past raw SQL: Power BI users need an OData feed, and any such surface needs column- and row-level scope, not just catalog attach/detach.

This ADR decides three things: how identity propagates between services, how a grant becomes an enforceable and narrowly-scoped credential, and what artifact carries fine-grained data scope.

### Trust boundaries

The platform has three distinct trust boundaries, each with its own question:

| Boundary | Question |
|:---|:---|
| B1: principal → edge | Who is this user or machine? |
| B2: service ↔ service | Is this internal call authentic, and on whose behalf? |
| B3: query-time data access | Which data, columns, and rows may this request touch? |

### Prior art

SRDP follows the conventional identity-and-access pattern for a single-issuer platform rather than inventing a new one. In that standard setup, an OIDC/OAuth2 provider issues tokens; every service that makes an authorization decision validates the token (signature, issuer, audience, expiry) against the provider's JWKS; RBAC expresses coarse grants; and short-lived tokens keep revocation bounded. The decisions below choose which of these conventional mechanisms fits each boundary.

Two practices guide the design throughout: keep credentials short-lived so revocation stays bounded, and keep any custom permission evaluator a small, fixed profile, because evaluator correctness is where the risk concentrates. Heavier alternatives (verifiable credentials, attenuated token formats, a general policy engine) are weighed in the options below and set aside as more machinery than a single-issuer deployment needs.

## Considered Options

### Identity and token model

1. Validated JWTs at every hop, plus PEP-issued short-lived capability tokens.
2. Forwarded identity headers from forwardauth (the mechanism ADR-0002 currently describes).
3. W3C Verifiable Credentials and DIDs (a decentralized verifiable-claims stack).
4. Attenuated token formats (Biscuit, macaroons).

### Fine-grained scope artifact

1. Data contracts ([Data Contract Specification](https://datacontract.com/) YAML, evaluated by a constrained built-in evaluator).
2. Bespoke PostgreSQL policy store (the path ADR-0005 sketched as "later").
3. ODRL profile embedded in credentials.
4. General policy engine (OPA).

## Decision Outcome

### Identity: one issuer, validated at every hop

Zitadel is the only identity issuer in a deployment. Every service that makes an authorization decision validates the caller's JWT against Zitadel's JWKS endpoint: signature, issuer, audience, expiry. oauth2-proxy forwards the access token (`--pass-access-token`); the plain `X-Auth-Request-*` headers are display hints only and are never an input to authorization. Machine-to-machine callers use Zitadel client-credentials tokens validated the same way. This closes the header-forgery gap at B2: a Zitadel-signed JWT verified offline is a verifiable credential in every property that matters inside a single-issuer deployment.

### Capability tokens: a grant becomes a short-lived, scoped, offline-verifiable credential

The PEP is a token-exchange point. A caller presents its identity token; the PEP checks current grants and issues a **capability token**: a short-lived signed JWT embedding the principal, the project, the data-contract reference and version, the allowed actions (read; trigger-job; admin), and an expiry (default 15 minutes, configurable per deployment). The signing key is platform-owned and published JWKS-style, so any service — the API itself, an OData worker, a Quack server, a future gateway — verifies capability tokens offline without calling the PEP.

Properties:

- A capability token is never wider than the principal's grants at exchange time, and it is attenuated: it names one project/contract scope, not the principal's full grant set.
- The revocation SLO equals the capability-token TTL: a revoked grant stops working at the next exchange, at most one TTL after revocation. No introspection call sits on the query path.
- Engine credentials are subordinate to capability tokens. Whatever mechanism materializes actual data access (per-project PostgreSQL reader/writer roles, scoped storage tokens, or a Quack server session; the mechanism is decided in [ADR-0009](./0009-data-plane-credential-materialization.md)) is issued against a presented capability token and bound to its lifetime. No principal ever holds an engine credential that outlives or outscopes its capability token. This closes the enforcement half of gap 2 above (a direct connection hands the consumer real credentials, and DuckDB's client-side `READ_ONLY` is not enforcement); turning that grant into a column/row-safe credential is the separate materialization problem decided in ADR-0009.

Because the capability token is a plain signed JWT, a forward path stays open: it can later be issued in W3C Verifiable Credential form (the VC-JWT / SD-JWT-VC profiles) without changing the offline-verification pattern. That extension is deliberately not built in early versions, and full VC/DID participation (holder presentations, DID-resolved issuers) is the larger federation effort noted under scope below. The point is only that the token format does not foreclose it.

### Data contracts as the scope artifact

When a dataset is exposed to consumers with fine-grained or cross-tenant scope, it is described by a **data contract**: a versioned YAML document following the Data Contract Specification, living in the owning project's repository next to the asset code that produces the data. A contract defines the schema, the exposed scope (tables, columns, optional row filters drawn from a fixed predicate set), terms of use, quality checks, and SLAs. Contracts are the opt-in fine-grained layer; a dataset reached only through coarse project RBAC needs none.

Grants then take two forms, coarse and fine:

- Project-scoped RBAC (ADR-0005) remains the coarse default: reader/writer/admin on a whole project.
- A contract grant scopes a principal to exactly what one contract version exposes. The capability token references the contract; enforcement reads the contract, not ad-hoc rules.

The same artifact serves three further platform functions, which is the reason to choose a standard spec over a bespoke policy table:

- **Ingestion gating (ADR-0004)**: the landing-zone gate checks *are* contract validation — schema and quality checks executed with `datacontract-cli` (DuckDB support to be confirmed in the spike) or natively against the contract model.
- **Discovery (ADR-0003)**: the API's catalog endpoints serve contracts as the description of what exists, instead of raw engine schemas.
- **Consumer surfaces**: each consumer-facing surface generates its schema from the contract rather than hand-maintaining one; the OData entity model below is the first example, and others follow the same way.

### Constrained evaluator, deliberately

The platform ships a small built-in evaluator that maps (capability token, contract version, request) to allow/deny plus the effective column list and row filter. The profile is fixed: read-only actions, column subsetting, and row predicates from an enumerated set (equality, range, membership on declared fields). It is explicitly not a general policy language; requests outside the profile are denied. This reflects the prior-art lesson above: a custom evaluator is acceptable only when its input language is small enough to test exhaustively. The evaluator carries the highest test bar in the platform alongside the PEP.

### Fine-grained enforcement and tier compatibility

The evaluator produces an effective column list and row filter, but *where* that result is applied depends on the access tier (ADR-0007), and the two fine-grained dimensions do not map onto every tier:

- **Mediated tiers (ADR-0007 Tier C: API sync query, OData, a future Quack server)** have the evaluator in the request path and execute the query on the principal's behalf. Column subsetting and row filters are applied here by constraining the generated SQL; this is the only place contract column/row scope can be enforced.
- **Direct reads (Tier A)** hand the principal engine credentials (a per-project PostgreSQL reader role plus scoped storage credentials). These enforce at catalog/table and storage-prefix granularity only. PostgreSQL roles do not subset DuckLake columns and storage prefixes do not filter rows, so a contract's column/row scope cannot be honored on a direct read.

The consequence is structural: **fine-grained scope is a property of mediated access, not of the credential.** A principal whose grant is a contract (not a whole project) cannot be given Tier A direct credentials without leaking everything in the underlying table. Coarse project grants stay Tier A eligible; fine contract grants are mediated-only. The capability token can be minted either way, but it does not by itself make a direct connection column/row-safe.

This evaluator is a data-*minimization* layer, not the tenant-*isolation* boundary: isolation between projects/customers stays the hard catalog/deployment boundary of ADR-0006, and the evaluator operates strictly inside it. That distinction is what reconciles this ADR with ADR-0006's rejection of in-data-plane row/column scoping: 0006 rejects it as an *isolation* mechanism, whereas here it is defence-in-depth *within* a project. The evaluator must never be the only thing standing between two tenants.

This forces three choices that change the enforcement model. They are recorded under [Open questions](#open-questions-to-resolve-with-the-team) and deliberately left undecided here:

- whether to **forbid** Tier A for contract-scoped principals (a mediated-only invariant) or to also offer a coarse table-level direct path alongside the mediated fine-grained one;
- the **mediated enforcement mechanism**: runtime SQL rewrite (the evaluator emits `SELECT <cols> … WHERE <filter>`) versus platform-generated per-contract DuckDB views (column projection and row predicate baked into a view, access granted to the view, regenerated on contract-version change);
- whether **per-principal row filters** are in scope: a contract-version row filter applies uniformly to every holder of that grant, whereas true per-principal row-level security (e.g. *rows where region = the principal's region*) requires a parameter bound at token-exchange time and carried in the capability token, which the token shape above does not yet include.

### Contract-grant storage

Coarse project RBAC lives in Zitadel (ADR-0005). The fine grant (*principal X may use contract Y at version Z*) needs a home too, and the choice is consequential rather than mechanical:

- carrying contract grants as Zitadel claims keeps a single grant store but reintroduces the token claim-bloat this design otherwise avoids, and couples contract-grant changes to the identity provider;
- a platform-side grant table is the natural query surface for the PEP, but it is the same PostgreSQL store rejected above as the *scope* artifact, acceptable as a *grant binding* (who-holds-what) only if it does not grow back into a policy language;
- a hybrid keeps coarse roles in Zitadel and fine contract grants in the platform table.

The PEP reads this binding at token-exchange time to decide whether to mint a contract-scoped capability token. The store is required for fine-grained access to function at all; the specific option is an open question below.

### Capability-token signing key

Capability tokens are signed by a platform-owned key, published JWKS-style for offline verification. That key mints data-access credentials, so it is the highest-value secret in a deployment and needs a lifecycle the ADRs do not yet define: where it is held (secret manager / KMS), how it rotates without invalidating in-flight tokens (overlapping keys in the JWKS, `kid`-based selection), and how compromise is contained. Because TTL-based expiry cannot stop a stolen *signing* key, key rotation doubles as the break-glass for mass revocation. The operational specifics are deferred to a security spike.

### OData endpoint for Power BI consumers

The platform adds an optional OData v4 read surface as a consumer service. It is an instance of ADR-0007's Tier C (centralized, per-query audited): entity sets are generated from data contracts, requests carry capability tokens, and `$select`/`$filter`/`$top`/`$skip` are pushed down to DuckDB SQL with server-driven paging. Only the minimal OData subset needed by Power BI is implemented (metadata document, entity sets, the four query options); no Python OData server framework is assumed.

### Out of scope now: EHDS/dataspace federation infrastructure

SRDP is field-agnostic but should be useful for healthcare, where the European Health Data Space (EHDS) and dataspaces set the standards. Those standards split into two parts, and only one is in play here:

- **Conventions** (data formats, consent semantics, ODRL-style usage policies): expressible through SRDP's data contracts and API surfaces. This is the part that makes SRDP useful in a healthcare deployment, and keeping the contract model standards-based leaves room to adopt it. A new conforming surface is added as a FastAPI router, the way the OData endpoint already is.
- **Federation infrastructure** (DSP contract negotiation, IDS connectors, W3C VC/DID identity, EHDS data-permit flows): the cross-organization sovereign-exchange layer for parties with no shared issuer. This is heavier and out of scope for v1.

One party consuming another's data over its API is not federation; that is ordinary external consumer access, already covered here. Federation is the protocol layer above it. SRDP implements none of that layer today (a signed JWT is not a W3C VC), so adopting EHDS/dataspace standards is a separate, later ADR.

SRDP allows for the pieces such alignment needs, added at its extension seams rather than by becoming a node:

- identity adapters at the PEP (external verifiable-credential identity → capability token),
- EHDS/dataspace conventions carried in data contracts (formats, consent, ODRL-style usage policies),
- conforming API surfaces added as routers (as the OData endpoint is),
- validation hooks in the validator/proxy layer.

The PEP's token issuance and the evaluator's enforcement stay fixed.

### Impact on existing ADRs

No structural rewrites; on acceptance of this ADR the following are amended:

| ADR | Amendment |
|:---|:---|
| 0002 | Internal trust section: identity at B2 is a validated JWT, never forwarded headers; forwardauth remains the edge gate only |
| 0005 | The PEP issues capability tokens (token exchange), not bare connections; "optional PostgreSQL policy store later" is superseded by data contracts |
| 0004 | Landing-zone gate checks are defined as data-contract validation |
| 0003 | Catalog discovery serves data contracts as dataset descriptions |
| 0007 | Read tiers consume capability tokens; the OData endpoint is a Tier C instance; the Tier C protocol question gains Quack and OData as concrete candidates; Tier A serves coarse project grants only, fine-grained contract grants are mediated (Tier C) |

### Open questions (to resolve with the team)

These are deliberately undecided; they change the enforcement model and warrant team discussion rather than a unilateral call:

1. **Fine-grained vs. direct read.** For sensitive/regulated data (e.g. healthcare) the lean is **mediated-only**: Tier A direct reads can produce neither per-record audit nor column/row enforcement, both of which such data requires. Open: whether non-sensitive projects may still offer a coarse table-level direct path alongside the mediated fine-grained one, or whether the platform is mediated-only throughout.
2. **Mediated enforcement mechanism.** Runtime SQL rewrite vs. generated per-contract DuckDB views.
3. **Per-principal / consent row filters (required; mechanism open).** Healthcare consent is per-record and dynamic, so per-principal row filtering is a requirement, not optional. Open: the mechanism, a scope parameter bound at token-exchange time and carried in the capability token (the token shape above does not yet include one).
4. **Column masking vs. subsetting.** Does the evaluator only *drop* columns, or also *transform* them (mask, pseudonymize, generalize, e.g. birth-year not birth-date)? Masking expands the evaluator's profile and directly threatens the "small enough to test exhaustively" property; in-or-out must be an explicit decision.
5. **Purpose-of-use binding.** Regulated access is purpose-bound (treatment / research / billing). Does the capability token carry a `purpose` claim that the evaluator and the audit log consume, or is purpose out of scope for v1?
6. **Contract-grant storage.** Zitadel claims, platform table, or hybrid.
7. **Signing-key lifecycle and break-glass.** Storage, rotation, and an emergency-revocation path faster than waiting out the TTL.
8. **Revocation SLO value.** 15 minutes is a placeholder; the security-critical revoke-data-access operation may warrant a tighter default or a separate kill-switch.

### Consequences

- Good, because zero-trust is mechanically enforced (signature validation) at every boundary instead of asserted over forgeable headers.
- Good, because revocation has a defined bound (the capability-token TTL) with no per-query introspection cost.
- Good, because one versioned artifact — the data contract — carries fine-grained authorization scope, ingestion gating, discovery metadata, and consumer schemas, instead of four divergent ones.
- Good, because the Data Contract Specification is a public standard with tooling, so contracts are not a bespoke in-house format.
- Good, because capability tokens are plain signed JWTs: no new cryptographic stack, verifiable with the same JWKS pattern already used for Zitadel tokens.
- Bad, because the PEP token exchange adds a step before data access (mitigated: tokens are reusable for their TTL, so the exchange is per-session, not per-query).
- Bad, because the constrained evaluator is custom security-critical code with no reference implementation; its correctness rests on an exhaustive test suite.
- Bad, because every exposed dataset now requires an authored contract, which is real friction for project teams (mitigated: contract scaffolding generated from the asset's schema).
- Bad, because Zitadel roles (coarse) and contract grants (fine) are two grant surfaces that must be kept coherent in the PEP.
- Bad, because the OData subset is custom-built and Power BI's OData client behavior must be integration-tested, not assumed.
- Bad, because fine-grained (column/row) scope is enforceable only on mediated tiers; the direct-read path (Tier A) is coarse by construction, so contract-scoped principals must be routed through the API/OData/Quack (see open questions).
- Bad, because offline capability-token verification removes the PEP from the query path, so Tier A direct reads yield only session/grant-level audit, not per-query audit; per-query audit exists only on the mediated tiers.
- Bad, because capability tokens are bearer credentials with no proof-of-possession; a leaked token is replayable for its TTL (mitigated by the short TTL, accepted in place of the heavier Biscuit/macaroon attenuation).
- Bad, because the platform signing key is a new crown-jewel secret whose rotation and compromise handling the platform now owns (Zitadel previously owned the only signing lifecycle).

## Pros and Cons of the Options

### Forwarded identity headers

- Good, because zero additional code; oauth2-proxy already injects them.
- Bad, because forgeable by any process that can reach a service directly, reducing zero-trust to network trust.

### W3C Verifiable Credentials / DIDs

- Good, because issuer-independent verification: the right tool when there is no shared identity provider (the federated setting).
- Good, because standards-aligned with EHDS/dataspace ecosystems.
- Bad, because inside a single-issuer deployment it duplicates what a Zitadel-signed JWT already provides, at the cost of DID management, wallets, and presentation exchange.
- Bad, because heavy operational footprint (per-instance identity nodes, credential lifecycle governance).

### Attenuated token formats (Biscuit, macaroons)

- Good, because offline attenuation is first-class: a holder can derive narrower tokens without the issuer.
- Bad, because a non-standard dependency and verification stack for every service, where short-lived JWTs from a single PEP achieve the needed attenuation (the PEP is always reachable at exchange time).

### Bespoke PostgreSQL policy store

- Good, because simplest to query from the PEP.
- Bad, because it invents a private policy schema with no consumer-facing value: it cannot double as ingestion gate, discovery document, or schema contract, and offers no standard tooling or export path.

### ODRL profile

- Good, because W3C standard for expressing permissions, the natural target for future federation.
- Bad, because no production-grade Python evaluator exists, and full ODRL is far more language than the platform's needs; real deployments constrain it to a small custom subset anyway — at which point a data-contract-scoped evaluator is the same work with a more useful artifact.

### General policy engine (OPA)

- Good, because battle-tested evaluation engine and policy language.
- Bad, because it is a new always-on service and a Turing-complete policy language for an access model (project roles + contract scopes) that does not need one; ADR-0005 already rejected a standalone policy engine until rule complexity justifies it.
