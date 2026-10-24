import csv
import logging
from io import StringIO
from typing import List, Optional

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

WHO_COVID_CSV_URL = (
    "https://srhdpeuwpubsa.blob.core.windows.net/whdh/COVID/WHO-COVID-19-global-data.csv"
)
WHO_DON_URL = "https://www.who.int/api/emergencies/diseaseoutbreaknews"

# Keywords used to associate WHO DON alerts with the diseases of interest.
DISEASE_KEYWORDS = {
    "Mpox": ["mpox", "monkeypox"],
    "Dengue fever": ["dengue"],
    "Pertussis": ["pertussis", "whooping cough"],
    "Respiratory Syncytial Virus": ["rsv", "respiratory syncytial virus"],
    "Scarlet fever": ["scarlet fever", "group a strep", "streptococcus pyogenes"],
    "Hand-foot-mouth disease": ["hand-foot-mouth", "hand foot mouth", "hfmd", "coxsackievirus", "enterovirus"],
    "Chickenpox": ["chickenpox", "varicella"],
    "Measles": ["measles", "morbilli"],
    "Influenza A": ["influenza", "flu", "influenza a", "h1n1", "h3n2"],
    "Acute Respiratory Infection": ["acute respiratory infection", "ari"],
    "Norovirus": ["norovirus", "norwalk"],
}


async def _fetch_csv(url: str, timeout: float = 120.0) -> str:
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(url)
            response.raise_for_status()
            return response.text
    except Exception as exc:
        logger.warning(f"CSV fetch failed for {url}: {exc}")
        return ""


async def fetch_who_covid() -> List[dict]:
    text = await _fetch_csv(WHO_COVID_CSV_URL)
    if not text:
        return []
    snapshots = []
    reader = csv.DictReader(StringIO(text))
    for row in reader:
        country = clean_str(row.get("Country"))
        country_code = clean_str(row.get("Country_code"))
        who_region = clean_str(row.get("WHO_region"))
        report_date = parse_date(row.get("Date_reported"))
        if not country or not report_date:
            continue

        base = {
            "source": "who_covid_cases",
            "country": country,
            "region_type": "country",
            "region_code": country_code,
            "region": who_region,
            "condition_name": canonical_condition_name("COVID-19"),
            "report_date": report_date,
            "metadata_json": dict(row),
        }

        for metric_name, column in (("new_cases", "New_cases"), ("new_deaths", "New_deaths")):
            value = coerce_int(row.get(column))
            if value is None:
                continue
            snapshots.append(
                {
                    **base,
                    "source_id": build_source_id(
                        "who_covid_cases",
                        [country_code or country, row.get("Date_reported"), metric_name],
                    ),
                    "metric_name": metric_name,
                    "metric_value": float(value),
                    "case_count": value if metric_name == "new_cases" else None,
                }
            )
    return deduplicate_snapshots(snapshots)


def _normalize_who_don_country(country: Optional[str]) -> str:
    if not country:
        return "Global"
    country = country.strip()
    lower = country.lower()
    if lower in {"global situation", "global update", "global"}:
        return "Global"
    if lower in {"multi-country", "multi-locations", "multi-location", "multiple countries"}:
        return "Multiple"
    return country


def _match_who_don_condition(title: str, event_title: str) -> Optional[str]:
    text = f"{title} {event_title}".lower()
    for condition, keywords in DISEASE_KEYWORDS.items():
        for keyword in keywords:
            if keyword in text:
                return condition
    return None


def _extract_who_don_country(title: str, event_title: Optional[str]) -> str:
    if event_title and title.lower().startswith(event_title.lower()):
        country = title[len(event_title):].strip()
        country = country.lstrip(":-–—").strip()
        return _normalize_who_don_country(country)
    for separator in (" – ", " - ", ", "):
        if separator in title:
            return _normalize_who_don_country(title.rsplit(separator, 1)[1])
    return "Global"


async def _fetch_who_don_json(url: str, params: dict, timeout: float = 60.0) -> List[dict]:
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            data = response.json()
            return data.get("value", []) if isinstance(data, dict) else []
    except Exception as exc:
        logger.warning(f"WHO DON fetch failed for {url}: {exc}")
        return []


async def fetch_who_don(limit: int = 5000) -> List[dict]:
    """Fetch WHO Disease Outbreak News alerts for diseases of interest."""
    # The WHO DON OData endpoint rejects $top values above 100.
    top = min(limit, 100)
    params = {
        "sf_provider": "dynamicProvider372",
        "sf_culture": "en",
        "$orderby": "PublicationDateAndTime desc",
        "$expand": "EmergencyEvent",
        "$select": "Title,EmergencyEvent,PublicationDate,ItemDefaultUrl,UrlName,DonId",
        "$top": top,
    }
    rows = await _fetch_who_don_json(WHO_DON_URL, params)
    snapshots = []
    for row in rows:
        title = clean_str(row.get("Title"))
        if not title:
            continue
        event = row.get("EmergencyEvent") or {}
        event_title = clean_str(event.get("Title"))
        condition = _match_who_don_condition(title, event_title or "")
        if not condition:
            continue
        country = _extract_who_don_country(title, event_title)
        report_date = parse_date(row.get("PublicationDate"))
        don_id = clean_str(row.get("DonId"))
        source_id = build_source_id("who_don", [don_id, condition, country])
        snapshots.append(
            {
                "source": "who_don",
                "source_id": source_id,
                "country": country,
                "region": country,
                "region_type": "country",
                "condition_name": canonical_condition_name(condition),
                "metric_name": "outbreak_alert",
                "metric_value": 1.0,
                "metric_value_text": title,
                "report_date": report_date,
                "metadata_json": dict(row),
            }
        )
    return deduplicate_snapshots(snapshots)
