from dagster import Definitions, ScheduleDefinition, define_asset_job

from etl.assets.example import (
    executive_summary,
    raw_orders,
    revenue_by_category,
    revenue_by_country,
    top_country,
)
from srdp.resources.k8s import (
    BACKFILL_K8S_CONFIG,
    BASE_RUN_K8S_CONFIG,
    FAST_LANE_K8S_CONFIG,
)

# ---------------------------------------------------------------------------
# Jobs
# ---------------------------------------------------------------------------

srdp_etl_job = define_asset_job(
    "srdp_etl_job",
    tags={
        "dagster-k8s/config": BASE_RUN_K8S_CONFIG,
        "dagster/priority": "0",
        "team": "data-platform",
        "workload_kind": "scheduled-etl",
    },
)

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

srdp_etl_backfill_job = define_asset_job(
    "srdp_etl_backfill_job",
    tags={
        "dagster-k8s/config": BACKFILL_K8S_CONFIG,
        "dagster/priority": "-2",
        "team": "data-platform",
        "workload_kind": "backfill",
    },
)

# ---------------------------------------------------------------------------
# Schedules
# ---------------------------------------------------------------------------

etl_schedule = ScheduleDefinition(
    job=srdp_etl_job,
    cron_schedule="*/5 * * * *",
    tags={"dagster/priority": "-1"},
)

# ---------------------------------------------------------------------------
# Top-level export — Dagster gRPC server loads this via `-m etl.definitions`
# ---------------------------------------------------------------------------

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
