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

PAHO_DENGUE_URLS = [
    "https://opendata.paho.org/en/dengue-indicators",
    "https://www3.paho.org/data/index.php/en/mnu-topics/indicadores-dengue-en/dengue-nacional-en/252-dengue-pais-ano-en.html",
    "https://www3.paho.org/data/index.php/en/mnu-topics/indicadores-dengue-en/dengue-regional-en/261-dengue-reg-ano-en.html",
]


async def _fetch_page(url: str, timeout: float = 60.0) -> str:
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(url)
            response.raise_for_status()
            return response.text
    except Exception as exc:
        logger.warning(f"PAHO Dengue fetch failed for {url}: {exc}")
        return ""


def _extract_iframe_src(html: str) -> str:
    """Look for an embedded dashboard iframe."""
    lower = html.lower()
    idx = lower.find('iframe')
    if idx == -1:
        return ""
    src_idx = lower.find('src=', idx)
    if src_idx == -1:
        return ""
    quote = lower[src_idx + 4]
    end = lower.find(quote, src_idx + 5)
    if end == -1:
        return ""
    return html[src_idx + 5:end]


async def fetch_paho_dengue(limit: int = 5000) -> List[dict]:
    """Fetch PAHO dengue indicators for the Americas.

    The PAHO portal is currently dashboard/HTML-based and has been unstable.
    This fetcher attempts to read the indicator page and any embedded iframe,
    and returns an empty list when the data is not available in a parseable
    format.  The aggregation layer will fall back to US CDC dengue data in
    that case.
    """
    for url in PAHO_DENGUE_URLS:
        html = await _fetch_page(url)
        if not html:
            continue

        iframe_src = _extract_iframe_src(html)
        if iframe_src:
            logger.info(f"PAHO Dengue dashboard iframe found: {iframe_src}")
            # Future enhancement: parse the iframe/dashboard content.
            # For now, the portal does not expose machine-readable case counts.

        # If the page ever contains HTML tables with country-level case data,
        # parsing would be added here.  At present the portal returns either
        # 502 Bad Gateway or a dashboard landing page.
        break

    logger.info("PAHO Dengue: no machine-readable case counts available; skipped")
    return []
