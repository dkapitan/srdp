import polars as pl
from dagster import (
    Definitions,
    MetadataValue,
    Output,
    ScheduleDefinition,
    asset,
    define_asset_job,
)


# In this deployment, Dagster uses the K8sRunLauncher. That means job-level
# `dagster-k8s/config` tags customize the Kubernetes Job/Pod that executes the
# run. Queue ordering is controlled separately by the `dagster/priority` tag.
BASE_RUN_K8S_CONFIG = {
    "container_config": {
        "resources": {
            "requests": {"cpu": "250m", "memory": "256Mi"},
            "limits": {"cpu": "500m", "memory": "512Mi"},
        }
    },
    "job_metadata": {
        "labels": {
            "workload": "etl",
            "team": "data-platform",
        }
    },
}

FAST_LANE_K8S_CONFIG = {
    **BASE_RUN_K8S_CONFIG,
    "container_config": {
        "resources": {
            "requests": {"cpu": "500m", "memory": "512Mi"},
            "limits": {"cpu": "1", "memory": "1Gi"},
        }
    },
    "job_spec_config": {
        "ttl_seconds_after_finished": 600,
        "active_deadline_seconds": 900,
    },
    "job_metadata": {
        "labels": {
            "workload": "etl-fast-lane",
            "team": "data-platform",
        }
    },
}

BACKFILL_K8S_CONFIG = {
    **BASE_RUN_K8S_CONFIG,
    "container_config": {
        "resources": {
            "requests": {"cpu": "750m", "memory": "1Gi"},
            "limits": {"cpu": "2", "memory": "2Gi"},
        }
    },
    "job_spec_config": {
        "ttl_seconds_after_finished": 3600,
        "active_deadline_seconds": 7200,
    },
    "job_metadata": {
        "labels": {
            "workload": "etl-backfill",
            "team": "data-platform",
        }
    },
}


@asset
def raw_orders() -> Output[pl.DataFrame]:
    """Simulated order data from an e-commerce platform."""
    df = pl.DataFrame(
        {
            "order_id": list(range(1, 21)),
            "country": [
                "NL", "DE", "NL", "FR", "DE", "BE", "NL", "FR", "DE", "NL",
                "BE", "FR", "DE", "NL", "FR", "BE", "DE", "NL", "FR", "DE",
            ],
            "category": [
                "Electronics", "Books", "Electronics", "Clothing", "Books",
                "Electronics", "Clothing", "Books", "Electronics", "Clothing",
                "Books", "Electronics", "Clothing", "Books", "Electronics",
                "Clothing", "Books", "Electronics", "Clothing", "Books",
            ],
            "revenue_eur": [
                120.0, 95.0, 210.0, 60.0, 150.0, 85.0, 45.0, 130.0,
                200.0, 75.0, 110.0, 180.0, 55.0, 90.0, 160.0, 70.0,
                140.0, 195.0, 65.0, 125.0,
            ],
        }
    )
    return Output(
        df,
        metadata={
            "num_orders": len(df),
            "countries": MetadataValue.text(
                ", ".join(df["country"].unique().sort().to_list())
            ),
            "total_revenue": MetadataValue.float(df["revenue_eur"].sum()),
        },
    )


@asset
def revenue_by_country(raw_orders: pl.DataFrame) -> Output[pl.DataFrame]:
    """Aggregate revenue and order count per country."""
    result = (
        raw_orders.group_by("country")
        .agg(
            pl.col("revenue_eur").sum().alias("total_revenue_eur"),
            pl.col("order_id").count().alias("order_count"),
        )
        .sort("total_revenue_eur", descending=True)
    )
    return Output(
        result,
        metadata={
            "num_countries": len(result),
            "top_country": result.row(0, named=True)["country"],
            "preview": MetadataValue.md(f"```\n{result}\n```"),
        },
    )


@asset
def revenue_by_category(raw_orders: pl.DataFrame) -> Output[pl.DataFrame]:
    """Aggregate revenue, order count, and average order value per category."""
    result = (
        raw_orders.group_by("category")
        .agg(
            pl.col("revenue_eur").sum().alias("total_revenue_eur"),
            pl.col("order_id").count().alias("order_count"),
            pl.col("revenue_eur").mean().alias("avg_order_eur"),
        )
        .sort("total_revenue_eur", descending=True)
    )
    return Output(
        result,
        metadata={
            "num_categories": len(result),
            "top_category": result.row(0, named=True)["category"],
            "preview": MetadataValue.md(f"```\n{result}\n```"),
        },
    )


@asset
def top_country(revenue_by_country: pl.DataFrame) -> Output[str]:
    """Pick the single highest-revenue country."""
    winner = revenue_by_country.row(0, named=True)
    return Output(
        winner["country"],
        metadata={
            "country": winner["country"],
            "revenue": MetadataValue.float(winner["total_revenue_eur"]),
            "order_count": winner["order_count"],
        },
    )


@asset
def executive_summary(
    revenue_by_country: pl.DataFrame,
    revenue_by_category: pl.DataFrame,
) -> Output[str]:
    """Produce a short text summary combining country and category insights."""
    top_c = revenue_by_country.row(0, named=True)
    top_cat = revenue_by_category.row(0, named=True)
    total = revenue_by_country["total_revenue_eur"].sum()
    summary = (
        f"Total revenue: €{total:,.2f}\n"
        f"Top country: {top_c['country']} (€{top_c['total_revenue_eur']:,.2f})\n"
        f"Top category: {top_cat['category']} (€{top_cat['total_revenue_eur']:,.2f})\n"
        f"Countries served: {len(revenue_by_country)}\n"
        f"Product categories: {len(revenue_by_category)}"
    )
    return Output(
        summary,
        metadata={"summary": MetadataValue.md(f"```\n{summary}\n```")},
    )


srdp_etl_job = define_asset_job(
    "srdp_etl_job",
    tags={
        "dagster-k8s/config": BASE_RUN_K8S_CONFIG,
        "dagster/priority": "0",
        "team": "data-platform",
        "workload_kind": "scheduled-etl",
    },
)

# Higher queue priority and a slightly larger pod for a small, user-facing run.
executive_summary_job = define_asset_job(
    "executive_summary_job",
    selection=["executive_summary", "top_country"],
    tags={
        "dagster-k8s/config": FAST_LANE_K8S_CONFIG,
        "dagster/priority": "5",
        "team": "data-platform",
        "workload_kind": "fast-lane",
    },
)

# Lower queue priority for heavier ad hoc work so it yields to operational jobs.
srdp_etl_backfill_job = define_asset_job(
    "srdp_etl_backfill_job",
    tags={
        "dagster-k8s/config": BACKFILL_K8S_CONFIG,
        "dagster/priority": "-2",
        "team": "data-platform",
        "workload_kind": "backfill",
    },
)

etl_schedule = ScheduleDefinition(
    job=srdp_etl_job,
    cron_schedule="*/5 * * * *",
    tags={"dagster/priority": "-1"},
)

defs = Definitions(
    assets=[
        raw_orders,
        revenue_by_country,
        revenue_by_category,
        top_country,
        executive_summary,
    ],
    jobs=[srdp_etl_job, executive_summary_job, srdp_etl_backfill_job],
    schedules=[etl_schedule],
)
