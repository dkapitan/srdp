"""Kubernetes run config profiles for Dagster job tags.

Import these in any project's definitions.py and apply them as job tags:

    srdp_job = define_asset_job(
        "srdp_job",
        tags={"dagster-k8s/config": BASE_RUN_K8S_CONFIG, "dagster/priority": "0"},
    )
"""

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
