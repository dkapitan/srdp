---
status: proposed
date: 2026-06-05
decision-makers: Yannick Vinkesteijn
---

# Data catalog, lineage, and observability

## Context and Problem Statement

A running SRDP instance needs to answer two categories of questions:

1. Data observability: what data exists, where did it come from, what transformed it, and is it current? Without an enforced write path, data can change unobserved: files appear on storage that no catalog knows about, transformations run without lineage, and no one can answer "what happened to this dataset."
2. Functional observability: are services running, are pipelines succeeding, and what errors occurred?

These two concerns require different mechanisms. Data observability is solved by making the catalog mandatory: if every data change goes through a single IO layer, every change is automatically tracked. Functional observability is solved at the infrastructure layer with logging, health checks, and pipeline status.

## Considered Options

### Data observability: catalog and IO layer

1. DuckLake (mandatory IO wrapper): all data writes go through DuckLake via the Dagster IO manager. Every change is automatically cataloged, versioned, and discoverable.
2. Apache Iceberg + REST catalog: industry-standard open table format with broad engine support.
3. No mandatory catalog: let services and assets write data directly, track metadata separately.

### Data observability: lineage

1. OpenLineage: open standard for lineage events, emitted at each layer.
2. Dagster-native lineage only: rely on Dagster's built-in asset graph.

## Decision Outcome

### Data observability: DuckLake as mandatory IO wrapper

Chosen option: "DuckLake as mandatory IO wrapper", because it makes data observability automatic rather than opt-in. By routing all writes through the Dagster IO manager and into DuckLake, every data change is cataloged, versioned, and discoverable without any action from the asset author.

This is the core architectural decision: DuckLake is not optional. It is the mechanism that ensures no data exists outside the catalog. Without it, observability depends on each asset author remembering to register their output, which is error-prone.

DuckLake stores catalog metadata in PostgreSQL, which the platform already runs for Dagster and Zitadel. This means zero additional infrastructure for the catalog: no separate catalog server, no new database, just a new schema in the existing PostgreSQL instance. Data is written as standard Parquet files to any storage backend. DuckDB serves as the in-process query engine.

The IO wrapper is agnostic to how data is produced. Asset authors can use Polars, pandas, DuckDB SQL, or any other tool to build their transformations. The platform provides Polars as a core dependency, but it is not mandatory. What is mandatory is that every output goes through the IO manager into DuckLake.

### Write path: Dagster IO manager

The IO manager (`srdp.io.ducklake`) is the single write path into DuckLake. Asset code contains no storage logic; the IO manager handles persistence and catalog registration automatically.

```python
@asset(key_prefix="raw")
def source_data(context) -> pl.DataFrame:
    return pl.read_csv("data.csv")
    # → IO manager writes to DuckLake table: raw.source_data
```

The IO manager maps asset key segments to DuckLake schemas and tables:

| Asset key | DuckLake table | Storage path |
|:---|:---|:---|
| `["orders"]` | `ducklake.main.orders` | `DATA_PATH/main/orders/` |
| `["raw", "orders"]` | `ducklake.raw.orders` | `DATA_PATH/raw/orders/` |

DuckLake manages Parquet files autonomously: UUID-named, immutable, copy-on-write. There is no manual file management.

Why an IO manager, not a Dagster resource? A resource requires every asset to explicitly call `ducklake.write(...)`. A developer forgetting that call means data exists in the pipeline but not in the catalog. The IO manager makes catalog registration automatic and impossible to skip.

### Storage backends

The `StorageBackend` abstract base class (`srdp.io.storage`) decouples DuckLake from storage providers. Implementing a new backend requires two methods:

- `get_base_path()`: returns the root path or URI for data files.
- `configure_duckdb()`: installs extensions and sets credentials on the DuckDB connection.

Built-in: local filesystem (`.data/ducklake/`). Optional via extras: Azure Blob Storage, S3-compatible storage.

### Data observability: OpenLineage for cross-system lineage

Chosen option: "OpenLineage as the lineage standard", because DuckLake tracks what data exists and how it changed, but not the full lineage across systems. OpenLineage extends observability beyond the catalog by tracking data flow across Dagster and DuckDB, both of which support OpenLineage natively. Polars supports OpenLineage in its on-premises/distributed engine (v1.39.2+), but not in the standard open-source single-node library.

| Layer | Integration | Status |
|:---|:---|:---|
| Dagster | `openlineage-dagster` | Planned |
| DuckDB / DuckLake | `duck_lineage` extension | Planned |
| Polars Distributed | Native (v0.6.1+) | Available when distributed engine is deployed |

Lineage events are collected by a compatible backend (Marquez self-hosted or a managed endpoint).

Dagster's built-in asset catalog serves as the primary browsing interface for data discovery. It stores asset metadata, descriptions, partition status, and freshness in PostgreSQL. OpenLineage augments this with cross-system lineage; it does not replace Dagster's catalog.

### Functional observability

Functional concerns (logs, health, metrics) are handled at the infrastructure layer, not in the data catalog:

- Application logs: all services write structured logs to stdout/stderr. Log aggregation is the responsibility of the hosting environment (Docker log driver, Kubernetes log tooling).
- Pipeline health: Dagster tracks run success/failure and asset materialization status in its UI and PostgreSQL.
- Metrics: a Prometheus + Grafana stack is a reasonable future addition but is not part of the platform core yet. Live service status is covered by health endpoints.

### Consequences

- Good, because data observability is automatic: every write goes through DuckLake, so no data exists outside the catalog.
- Good, because the IO wrapper is tool-agnostic: asset authors choose their own dataframe library, the platform ensures observability regardless.
- Good, because zero additional infrastructure for the catalog. DuckDB is in-process, PostgreSQL is already deployed.
- Good, because storage backends are pluggable via a two-method interface.
- Good, because OpenLineage extends observability beyond the catalog with cross-system lineage.
- Bad, because DuckLake is newer than Iceberg, so fewer external tools can read DuckLake metadata natively.
- Bad, because a lineage collector (Marquez) is an additional service to deploy.

## Pros and Cons of the Options

### Apache Iceberg + REST catalog

- Good, because widest engine support (Spark, Trino, Flink, Snowflake, BigQuery).
- Bad, because the REST catalog is an additional service to deploy and operate.
- Bad, because JVM dependency conflicts with SRDP's Python-native, in-process philosophy.

### No mandatory catalog

- Good, because no IO wrapper overhead; services write data directly.
- Bad, because data changes are unobserved unless each service implements its own tracking.
- Bad, because no single source of truth for what data exists in the platform.

### Dagster-native lineage only

- Good, because zero additional dependencies.
- Bad, because lineage is only visible inside the Dagster UI, not portable.
- Bad, because DuckDB queries executed outside Dagster (notebooks, API) produce no lineage.
