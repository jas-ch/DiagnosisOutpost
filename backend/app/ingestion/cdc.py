import logging
from typing import List

import httpx

from app.ingestion.common import (
    build_source_id,
    canonical_condition_name,
    clean_str,
    coerce_float,
    coerce_int,
    deduplicate_snapshots,
    derive_region_type,
    parse_date,
    parse_mmwr_week,
)

logger = logging.getLogger(__name__)

CDC_NNDSS_URL = "https://data.cdc.gov/resource/x9gk-5huc.json"
CDC_RESP_NAAT_URL = "https://data.cdc.gov/resource/rgnm-fkqb.json"
CDC_NSSP_ED_RESP_URL = "https://data.cdc.gov/resource/vjzj-u7u8.json"
CDC_WASTEWATER_URL = "https://data.cdc.gov/resource/atcp-73re.json"
CDC_ARI_ACTIVITY_URL = "https://data.cdc.gov/resource/f3zz-zga5.json"
CDC_HOSP_RESP_URL = "https://data.cdc.gov/resource/vdzy-6i9v.json"
CDC_MPOX_WASTEWATER_URL = "https://data.cdc.gov/resource/xpxn-rzgz.json"


async def _fetch_socrata_json(
    url: str,
    limit: int,
    where: str | None = None,
    order: str | None = None,
    timeout: float = 60.0,
) -> List[dict]:
    try:
        params = {"$limit": limit}
        if where:
            params["$where"] = where
        if order:
            params["$order"] = order
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            data = response.json()
            return data if isinstance(data, list) else []
    except Exception as exc:
        logger.warning(f"Socrata fetch failed for {url}: {exc}")
        return []


def _location_state(location: str) -> tuple:
    """Return (region_label, state_value, region_type) for CDC location strings."""
    upper = location.upper().replace(".", "")
    if upper in {"US RESIDENTS", "UNITED STATES", "USA", "NATIONAL"}:
        return location, None, "country"
    # states column sometimes contains regions like "NEW ENGLAND"; keep as region.
    return location, location, "state"


async def fetch_cdc_nndss(limit: int = 5000) -> List[dict]:
    rows = await _fetch_socrata_json(CDC_NNDSS_URL, limit)
    snapshots = []
    for row in rows:
        location = clean_str(row.get("states") or row.get("location1") or row.get("location2"))
        year = clean_str(row.get("year"))
        week = clean_str(row.get("week"))
        label = clean_str(row.get("label"))
        if not location or not year or not week or not label:
            continue

        region_label, state_value, region_type = _location_state(location)
        # NNDSS MMWR columns: m1=current week, m2=previous week,
        # m3=cumulative current year, m4=cumulative previous year.
        # Use the cumulative current year count so totals reflect year-to-date.
        case_total = coerce_int(row.get("m3")) or coerce_int(row.get("m1")) or 0
        weekly_total = coerce_int(row.get("m1")) or 0
        report_date = parse_mmwr_week(year, week)
        source_id = build_source_id(
            "cdc_nndss", [year, week, location, label, row.get("sort_order")]
        )
        snapshots.append(
            {
                "source": "cdc_nndss",
                "source_id": source_id,
                "country": "United States",
                "state": state_value,
                "region": region_label,
                "region_type": region_type,
                "condition_name": canonical_condition_name(label),
                "metric_name": "cases",
                "metric_value": case_total if case_total else None,
                "case_count": case_total if case_total else None,
                "weekly_count": weekly_total if weekly_total else None,
                "report_date": report_date,
                "metadata_json": dict(row),
            }
        )
    return deduplicate_snapshots(snapshots)


async def fetch_cdc_resp_naat(limit: int = 5000) -> List[dict]:
    rows = await _fetch_socrata_json(CDC_RESP_NAAT_URL, limit)
    snapshots = []
    for row in rows:
        pathogen = clean_str(row.get("pathogen"))
        if not pathogen:
            continue
        level = clean_str(row.get("level")) or "National"
        geography = clean_str(row.get("geography"))
        region_label = geography or level
        state_value = geography if geography and geography.upper() not in {"NATIONAL", "UNITED STATES"} else None
        report_date = parse_date(row.get("mmwrweek_end") or row.get("posted"))
        value = coerce_float(row.get("percent_pos"))
        source_id = build_source_id(
            "cdc_resp_naat",
            [level, geography, pathogen, row.get("subtype"), row.get("mmwrweek_end"), row.get("posted")],
        )
        snapshots.append(
            {
                "source": "cdc_resp_naat",
                "source_id": source_id,
                "country": "United States",
                "state": state_value,
                "region": region_label,
                "region_type": derive_region_type({"state": state_value, "country": "United States"}),
                "condition_name": canonical_condition_name(pathogen),
                "metric_name": "percent_positivity",
                "metric_value": value,
                "metric_value_text": clean_str(row.get("percent_pos")),
                "report_date": report_date,
                "metadata_json": dict(row),
            }
        )
    return deduplicate_snapshots(snapshots)


async def fetch_cdc_nssp_ed_resp(limit: int = 5000) -> List[dict]:
    rows = await _fetch_socrata_json(CDC_NSSP_ED_RESP_URL, limit)
    snapshots = []
    for row in rows:
        geography = clean_str(row.get("geography"))
        pathogen = clean_str(row.get("pathogen"))
        if not geography or not pathogen:
            continue
        report_date = parse_date(row.get("date"))
        value = coerce_float(row.get("percent_visits"))
        source_id = build_source_id(
            "cdc_nssp_ed_resp", [row.get("date"), geography, pathogen]
        )
        snapshots.append(
            {
                "source": "cdc_nssp_ed_resp",
                "source_id": source_id,
                "country": "United States",
                "state": geography,
                "region": geography,
                "region_type": "state",
                "condition_name": canonical_condition_name(pathogen),
                "metric_name": "percent_visits",
                "metric_value": value,
                "metric_value_text": clean_str(row.get("percent_visits")),
                "report_date": report_date,
                "metadata_json": dict(row),
            }
        )
    return deduplicate_snapshots(snapshots)


async def fetch_cdc_wastewater(limit: int = 5000) -> List[dict]:
    rows = await _fetch_socrata_json(CDC_WASTEWATER_URL, limit)
    snapshots = []
    for row in rows:
        state = clean_str(row.get("state_territory"))
        county = clean_str(row.get("counties_served"))
        site = clean_str(row.get("site"))
        pathogen = clean_str(row.get("pathogen_target"))
        if not state or not pathogen:
            continue
        report_date = parse_date(
            row.get("date_included_in_wval") or row.get("week_end") or row.get("date_updated")
        )
        value = coerce_float(row.get("site_wval"))
        source_id = build_source_id(
            "cdc_wastewater",
            [state, county, site, pathogen, row.get("week_end"), row.get("date_included_in_wval")],
        )
        snapshots.append(
            {
                "source": "cdc_wastewater",
                "source_id": source_id,
                "country": "United States",
                "state": state,
                "county": county,
                "site": site,
                "region": site or county or state,
                "region_type": derive_region_type(
                    {"site": site, "county": county, "state": state, "country": "United States"}
                ),
                "condition_name": canonical_condition_name(pathogen),
                "metric_name": "wastewater_level",
                "metric_value": value,
                "metric_value_text": clean_str(row.get("site_wval_category")),
                "report_date": report_date,
                "metadata_json": dict(row),
            }
        )
    return deduplicate_snapshots(snapshots)


async def fetch_cdc_ari_activity(limit: int = 5000) -> List[dict]:
    rows = await _fetch_socrata_json(CDC_ARI_ACTIVITY_URL, limit)
    snapshots = []
    for row in rows:
        geography = clean_str(row.get("geography"))
        label = clean_str(row.get("label"))
        if not geography or not label:
            continue
        report_date = parse_date(row.get("week_end"))
        source_id = build_source_id(
            "cdc_ari_activity", [row.get("week_end"), geography]
        )
        snapshots.append(
            {
                "source": "cdc_ari_activity",
                "source_id": source_id,
                "country": "United States",
                "state": geography,
                "region": geography,
                "region_type": "state",
                "condition_name": "Acute Respiratory Infection",
                "metric_name": "activity_level",
                "metric_value_text": label,
                "report_date": report_date,
                "metadata_json": dict(row),
            }
        )
    return deduplicate_snapshots(snapshots)


async def fetch_cdc_hosp_resp(limit: int = 5000) -> List[dict]:
    rows = await _fetch_socrata_json(CDC_HOSP_RESP_URL, limit)
    snapshots = []
    pathogens = [
        ("COVID-19", "totalconfc19newadm", "totalconfc19newadmper100klevel"),
        ("Influenza", "totalconfflunewadm", "totalconfflunewadmper100klevel"),
        ("RSV", "totalconfrsvnewadm", "totalconfrsvnewadmper100klevel"),
    ]
    for row in rows:
        jurisdiction = clean_str(row.get("jurisdiction"))
        weekending = clean_str(row.get("weekendingdate"))
        if not jurisdiction or not weekending:
            continue
        report_date = parse_date(weekending)
        for name, count_col, level_col in pathogens:
            value = coerce_float(row.get(count_col))
            if value is None:
                continue
            source_id = build_source_id(
                "cdc_hosp_resp", [jurisdiction, weekending, name]
            )
            snapshots.append(
                {
                    "source": "cdc_hosp_resp",
                    "source_id": source_id,
                    "country": "United States",
                    "state": jurisdiction,
                    "region": jurisdiction,
                    "region_type": "state",
                    "condition_name": canonical_condition_name(name),
                    "metric_name": "new_admissions",
                    "metric_value": value,
                    "metric_value_text": clean_str(row.get(level_col)),
                    "report_date": report_date,
                    "metadata_json": dict(row),
                }
            )
    return deduplicate_snapshots(snapshots)


async def fetch_cdc_mpox(limit: int = 5000) -> List[dict]:
    """Fetch CDC wastewater mpox concentrations from data.cdc.gov."""
    rows = await _fetch_socrata_json(CDC_MPOX_WASTEWATER_URL, limit)
    snapshots = []
    for row in rows:
        state = clean_str(row.get("state_territory"))
        county = clean_str(row.get("counties_served"))
        site = clean_str(row.get("site"))
        target = clean_str(row.get("pcr_target"))
        if not state:
            continue
        report_date = parse_date(row.get("sample_collect_date"))
        value = coerce_float(row.get("pcr_target_avg_conc"))
        source_id = build_source_id(
            "cdc_mpox", [state, county, site, target, row.get("sample_collect_date")]
        )
        snapshots.append(
            {
                "source": "cdc_mpox",
                "source_id": source_id,
                "country": "United States",
                "state": state,
                "county": county,
                "site": site,
                "region": site or county or state,
                "region_type": derive_region_type(
                    {"site": site, "county": county, "state": state, "country": "United States"}
                ),
                "condition_name": canonical_condition_name("Mpox"),
                "metric_name": "pcr_target_avg_conc",
                "metric_value": value,
                "metric_value_text": clean_str(row.get("pcr_target_avg_conc")),
                "report_date": report_date,
                "metadata_json": dict(row),
            }
        )
    return deduplicate_snapshots(snapshots)


async def fetch_cdc_dengue(limit: int = 5000) -> List[dict]:
    """Fetch CDC NNDSS dengue case counts from data.cdc.gov."""
    rows = await _fetch_socrata_json(
        CDC_NNDSS_URL,
        limit,
        where="lower(label) like '%dengue%'",
        order="year DESC, week DESC",
    )
    snapshots = []
    for row in rows:
        location = clean_str(row.get("states") or row.get("location2"))
        year = clean_str(row.get("year"))
        week = clean_str(row.get("week"))
        label = clean_str(row.get("label"))
        if not location or not year or not week or not label:
            continue

        region_label, state_value, region_type = _location_state(location)
        case_total = coerce_int(row.get("m3")) or coerce_int(row.get("m1")) or 0
        weekly_total = coerce_int(row.get("m1")) or 0
        report_date = parse_mmwr_week(year, week)
        source_id = build_source_id(
            "cdc_dengue", [year, week, location, label, row.get("sort_order")]
        )
        snapshots.append(
            {
                "source": "cdc_dengue",
                "source_id": source_id,
                "country": "United States",
                "state": state_value,
                "region": region_label,
                "region_type": region_type,
                "condition_name": canonical_condition_name(label),
                "metric_name": "cases",
                "metric_value": case_total if case_total else None,
                "case_count": case_total if case_total else None,
                "weekly_count": weekly_total if weekly_total else None,
                "report_date": report_date,
                "metadata_json": dict(row),
            }
        )
    return deduplicate_snapshots(snapshots)


async def fetch_cdc_measles(limit: int = 5000) -> List[dict]:
    """Fetch CDC NNDSS measles case counts from data.cdc.gov."""
    rows = await _fetch_socrata_json(
        CDC_NNDSS_URL,
        limit,
        where="lower(label) like '%measles%'",
        order="year DESC, week DESC",
    )
    snapshots = []
    for row in rows:
        location = clean_str(row.get("states") or row.get("location2"))
        year = clean_str(row.get("year"))
        week = clean_str(row.get("week"))
        label = clean_str(row.get("label"))
        if not location or not year or not week or not label:
            continue

        region_label, state_value, region_type = _location_state(location)
        case_total = coerce_int(row.get("m3")) or coerce_int(row.get("m1")) or 0
        weekly_total = coerce_int(row.get("m1")) or 0
        report_date = parse_mmwr_week(year, week)
        source_id = build_source_id(
            "cdc_measles", [year, week, location, label, row.get("sort_order")]
        )
        snapshots.append(
            {
                "source": "cdc_measles",
                "source_id": source_id,
                "country": "United States",
                "state": state_value,
                "region": region_label,
                "region_type": region_type,
                "condition_name": canonical_condition_name(label) or "Measles",
                "metric_name": "cases",
                "metric_value": case_total if case_total else None,
                "case_count": case_total if case_total else None,
                "weekly_count": weekly_total if weekly_total else None,
                "report_date": report_date,
                "metadata_json": dict(row),
            }
        )
    return deduplicate_snapshots(snapshots)
