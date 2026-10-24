import logging
from datetime import datetime, timedelta
from io import BytesIO
from typing import List

import httpx
import openpyxl

from app.ingestion.common import (
    build_source_id,
    canonical_condition_name,
    clean_str,
    coerce_int,
    deduplicate_snapshots,
)

logger = logging.getLogger(__name__)

WHO_MEASLES_XLSX_URL = (
    "https://immunizationdata.who.int/docs/librariesprovider21/"
    "measles-and-rubella/404-table-web-epi-curve-data.xlsx"
)


async def _fetch_xlsx(url: str, timeout: float = 120.0) -> bytes:
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(url)
            response.raise_for_status()
            return response.content
    except Exception as exc:
        logger.warning(f"WHO Measles XLSX fetch failed for {url}: {exc}")
        return b""


def _month_to_date(year: str, month: str) -> datetime:
    return datetime(int(year), int(month), 1)


async def fetch_who_measles(limit: int = 5000) -> List[dict]:
    """Fetch WHO monthly country-level measles case data.

    Uses the 'Measles total' column (index 9).  Only the last 24 months are
    ingested to keep the database small and recent.
    """
    content = await _fetch_xlsx(WHO_MEASLES_XLSX_URL)
    if not content:
        return []

    try:
        workbook = openpyxl.load_workbook(BytesIO(content), read_only=True, data_only=True)
    except Exception as exc:
        logger.warning(f"Failed to parse WHO Measles workbook: {exc}")
        return []

    sheet = workbook["WEB"]
    snapshots = []
    cutoff = datetime.utcnow() - timedelta(days=730)

    for row in sheet.iter_rows(values_only=True):
        if not row or row[0] == "Region":
            continue

        region = clean_str(row[0])
        country = clean_str(row[1])
        iso3 = clean_str(row[2])
        year = clean_str(row[3])
        month = clean_str(row[4])
        total_cases = coerce_int(row[9])

        if not country or not year or not month or total_cases is None:
            continue

        try:
            report_date = _month_to_date(year, month)
        except (ValueError, TypeError):
            continue

        if report_date < cutoff:
            continue

        source_id = build_source_id(
            "who_measles_monthly", [iso3 or country, year, month]
        )
        snapshots.append(
            {
                "source": "who_measles_monthly",
                "source_id": source_id,
                "country": country,
                "region_code": iso3,
                "region": country,
                "region_type": "country",
                "condition_name": canonical_condition_name("Measles"),
                "metric_name": "cases",
                "metric_value": float(total_cases),
                "case_count": total_cases,
                "report_date": report_date,
                "metadata_json": {
                    "who_region": region,
                    "iso3": iso3,
                    "year": year,
                    "month": month,
                    "measles_total": total_cases,
                },
            }
        )

    snapshots = deduplicate_snapshots(snapshots)
    logger.info(f"WHO Measles monthly: ingested {len(snapshots)} snapshots")
    return snapshots[:limit]
