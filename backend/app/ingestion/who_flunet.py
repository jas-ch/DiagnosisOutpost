import csv
import logging
from datetime import datetime, timedelta
from io import StringIO
from typing import List

import httpx

from app.ingestion.common import (
    build_source_id,
    canonical_condition_name,
    clean_str,
    coerce_float,
    coerce_int,
    deduplicate_snapshots,
    parse_date,
)

logger = logging.getLogger(__name__)

FLUNET_CSV_URL = "https://xmart-api-public.who.int/FLUMART/VIW_FNT?&$format=csv"

# Metric columns in the WHO FluNet feed and the canonical condition they map to.
FLUNET_METRICS = {
    "INF_A": "Influenza A",
    "RSV": "Respiratory Syncytial Virus",
    "ILI_ACTIVITY": "Acute Respiratory Infection",
}


async def _fetch_csv(url: str, timeout: float = 120.0) -> str:
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(url)
            response.raise_for_status()
            return response.text
    except Exception as exc:
        logger.warning(f"FluNet CSV fetch failed for {url}: {exc}")
        return ""


def _parse_week_start(value: str) -> datetime:
    """Parse ISO_WEEKSTARTDATE and return the Monday of the week."""
    parsed = parse_date(value)
    if parsed:
        return parsed
    # Fallback: ISO year-week to Monday.
    try:
        return datetime.strptime(value + "-1", "%G-W%V-%u")
    except ValueError:
        raise ValueError(f"Cannot parse week start: {value}")


async def fetch_who_flunet(limit: int = 5000) -> List[dict]:
    """Fetch country-level WHO FluNet data for Influenza A, RSV and ARI/ILI.

    Only the most recent 52 weeks of data are processed to keep ingestion fast
    and the database small.  The feed covers the whole world, so rows are
    marked with coverage "global" in aggregation.
    """
    text = await _fetch_csv(FLUNET_CSV_URL)
    if not text:
        return []

    snapshots = []
    reader = csv.DictReader(StringIO(text))
    cutoff = datetime.utcnow() - timedelta(days=365)

    for row in reader:
        country = clean_str(row.get("COUNTRY_AREA_TERRITORY"))
        country_code = clean_str(row.get("COUNTRY_CODE") or row.get("ISO2"))
        week_start = clean_str(row.get("ISO_WEEKSTARTDATE"))
        if not country or not week_start:
            continue

        try:
            report_date = _parse_week_start(week_start)
        except ValueError:
            continue

        if report_date < cutoff:
            continue

        who_region = clean_str(row.get("WHOREGION"))

        for column, condition in FLUNET_METRICS.items():
            raw_value = clean_str(row.get(column))
            if raw_value is None:
                continue

            # ILI_ACTIVITY is an ordinal activity level (e.g. 1-5); the others
            # are specimen counts.
            if column == "ILI_ACTIVITY":
                value = coerce_float(raw_value)
                metric_name = "ili_activity"
                case_count = None
            else:
                value = coerce_float(raw_value)
                metric_name = "cases"
                case_count = coerce_int(raw_value)

            if value is None:
                continue

            source_id = build_source_id(
                "who_flunet",
                [country_code or country, week_start, column],
            )
            snapshots.append(
                {
                    "source": "who_flunet",
                    "source_id": source_id,
                    "country": country,
                    "region_code": country_code,
                    "region": country,
                    "region_type": "country",
                    "condition_name": canonical_condition_name(condition),
                    "metric_name": metric_name,
                    "metric_value": value,
                    "metric_value_text": raw_value if value is None else None,
                    "case_count": case_count,
                    "report_date": report_date,
                    "metadata_json": {
                        **dict(row),
                        "who_region": who_region,
                        "flunet_metric_column": column,
                    },
                }
            )

    snapshots = deduplicate_snapshots(snapshots)
    logger.info(f"WHO FluNet: ingested {len(snapshots)} snapshots")
    return snapshots[:limit]
