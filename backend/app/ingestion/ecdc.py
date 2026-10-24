import csv
import logging
from io import StringIO
from typing import List

import httpx

from app.ingestion.common import (
    build_source_id,
    canonical_condition_name,
    clean_str,
    coerce_float,
    deduplicate_snapshots,
    parse_yearweek,
)

logger = logging.getLogger(__name__)

ECDC_RESP_CSV_URL = (
    "https://raw.githubusercontent.com/EU-ECDC/Respiratory_viruses_weekly_data/"
    "main/data/sentinelTestsDetectionsPositivity.csv"
)


async def _fetch_csv(url: str, timeout: float = 120.0) -> str:
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(url)
            response.raise_for_status()
            return response.text
    except Exception as exc:
        logger.warning(f"CSV fetch failed for {url}: {exc}")
        return ""


async def fetch_ecdc_respiratory() -> List[dict]:
    text = await _fetch_csv(ECDC_RESP_CSV_URL)
    if not text:
        return []
    snapshots = []
    reader = csv.DictReader(StringIO(text))
    for row in reader:
        country = clean_str(row.get("countryname"))
        yearweek = clean_str(row.get("yearweek"))
        pathogen = clean_str(row.get("pathogen"))
        indicator = clean_str(row.get("indicator"))
        raw_value = clean_str(row.get("value"))
        if not country or not yearweek or not pathogen or not indicator:
            continue

        value = coerce_float(raw_value)
        report_date = parse_yearweek(yearweek)
        source_id = build_source_id(
            "ecdc_respiratory",
            [
                country,
                yearweek,
                pathogen,
                row.get("pathogensubtype"),
                indicator,
                row.get("age"),
            ],
        )
        snapshots.append(
            {
                "source": "ecdc_respiratory",
                "source_id": source_id,
                "country": country,
                "region": country,
                "region_type": "country",
                "condition_name": canonical_condition_name(pathogen),
                "metric_name": indicator,
                "metric_value": value,
                "metric_value_text": raw_value if value is None else None,
                "report_date": report_date,
                "metadata_json": dict(row),
            }
        )
    return deduplicate_snapshots(snapshots)
