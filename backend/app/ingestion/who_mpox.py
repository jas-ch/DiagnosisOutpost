import logging
from datetime import datetime, timedelta
from typing import List

import httpx

from app.ingestion.common import (
    build_source_id,
    canonical_condition_name,
    clean_str,
    coerce_int,
    deduplicate_snapshots,
    parse_date,
)

logger = logging.getLogger(__name__)

WHO_MPOX_URL = "https://xmart-api-public.who.int/MPX/V_MPX_VALIDATED_DAILY"


async def _fetch_json(url: str, timeout: float = 120.0) -> dict:
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(url)
            response.raise_for_status()
            return response.json()
    except Exception as exc:
        logger.warning(f"WHO Mpox fetch failed for {url}: {exc}")
        return {}


async def fetch_who_mpox(limit: int = 5000) -> List[dict]:
    """Fetch WHO xMART validated daily Mpox data.

    Emits one snapshot per country/date for new confirmed cases and one for
    total confirmed cases.  Only rows within the last 180 days are kept.
    """
    data = await _fetch_json(WHO_MPOX_URL)
    rows = data.get("value", []) if isinstance(data, dict) else []
    if not rows:
        return []

    snapshots = []
    cutoff = datetime.utcnow() - timedelta(days=180)

    for row in rows:
        country = clean_str(row.get("COUNTRY"))
        iso3 = clean_str(row.get("ISO3"))
        date_str = clean_str(row.get("DATE"))
        if not country or not date_str:
            continue

        report_date = parse_date(date_str)
        if not report_date or report_date < cutoff:
            continue

        base = {
            "source": "who_mpox",
            "country": country,
            "region_code": iso3,
            "region": country,
            "region_type": "country",
            "condition_name": canonical_condition_name("Mpox"),
            "report_date": report_date,
            "metadata_json": dict(row),
        }

        for metric_name, column in (
            ("new_cases", "NEW_CONF_CASES"),
            ("cases", "TOTAL_CONF_CASES"),
        ):
            value = coerce_int(row.get(column))
            if value is None:
                continue
            snapshots.append(
                {
                    **base,
                    "source_id": build_source_id(
                        "who_mpox", [iso3 or country, date_str, metric_name]
                    ),
                    "metric_name": metric_name,
                    "metric_value": float(value),
                    "case_count": value,
                }
            )

    snapshots = deduplicate_snapshots(snapshots)
    logger.info(f"WHO Mpox: ingested {len(snapshots)} snapshots")
    return snapshots[:limit]
