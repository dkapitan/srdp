import polars as pl
from dagster import Definitions, asset, define_asset_job


@asset
def raw_orders() -> pl.DataFrame:
    return pl.DataFrame(
        {
            "order_id": [1, 2, 3, 4, 5],
            "country": ["NL", "DE", "NL", "FR", "DE"],
            "revenue_eur": [120.0, 95.0, 210.0, 60.0, 150.0],
        }
    )


@asset
def revenue_by_country(raw_orders: pl.DataFrame) -> pl.DataFrame:
    return (
        raw_orders.group_by("country")
        .agg(pl.col("revenue_eur").sum().alias("total_revenue_eur"))
        .sort("total_revenue_eur", descending=True)
    )


@asset
def top_country(revenue_by_country: pl.DataFrame) -> str:
    return revenue_by_country.row(0, named=True)["country"]


srdp_etl_job = define_asset_job("srdp_etl_job")

defs = Definitions(
    assets=[raw_orders, revenue_by_country, top_country],
    jobs=[srdp_etl_job],
)
