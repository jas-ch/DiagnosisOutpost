import asyncio
import logging
from typing import Callable, Coroutine, List

from app.ingestion.cdc import (
    fetch_cdc_ari_activity,
    fetch_cdc_dengue,
    fetch_cdc_hosp_resp,
    fetch_cdc_measles,
    fetch_cdc_mpox,
    fetch_cdc_nndss,
    fetch_cdc_nssp_ed_resp,
    fetch_cdc_resp_naat,
    fetch_cdc_wastewater,
)
from app.ingestion.common import deduplicate_snapshots
from app.ingestion.ecdc import fetch_ecdc_respiratory
from app.ingestion.paho_dengue import fetch_paho_dengue
from app.ingestion.who import fetch_who_covid, fetch_who_don
from app.ingestion.who_flunet import fetch_who_flunet
from app.ingestion.who_measles import fetch_who_measles
from app.ingestion.who_mpox import fetch_who_mpox

logger = logging.getLogger(__name__)

# Registry of supported ingestion sources. Each fetcher returns a list of
# normalized snapshot dicts ready for persistence.
SOURCE_FETCHERS: dict[str, Callable[[], Coroutine[None, None, List[dict]]]] = {
    "cdc_nndss": lambda limit=5000: fetch_cdc_nndss(limit=limit),
    "cdc_resp_naat": lambda limit=5000: fetch_cdc_resp_naat(limit=limit),
    "cdc_nssp_ed_resp": lambda limit=5000: fetch_cdc_nssp_ed_resp(limit=limit),
    "cdc_wastewater": lambda limit=5000: fetch_cdc_wastewater(limit=limit),
    "cdc_ari_activity": lambda limit=5000: fetch_cdc_ari_activity(limit=limit),
    "cdc_hosp_resp": lambda limit=5000: fetch_cdc_hosp_resp(limit=limit),
    "cdc_mpox": lambda limit=5000: fetch_cdc_mpox(limit=limit),
    "cdc_dengue": lambda limit=5000: fetch_cdc_dengue(limit=limit),
    "cdc_measles": lambda limit=5000: fetch_cdc_measles(limit=limit),
    "who_covid": lambda _limit=5000: fetch_who_covid(),
    "who_don": lambda limit=5000: fetch_who_don(limit=limit),
    "who_flunet": lambda limit=5000: fetch_who_flunet(limit=limit),
    "who_measles_monthly": lambda limit=5000: fetch_who_measles(limit=limit),
    "who_mpox": lambda limit=5000: fetch_who_mpox(limit=limit),
    "paho_dengue": lambda limit=5000: fetch_paho_dengue(limit=limit),
    "ecdc_respiratory": lambda _limit=5000: fetch_ecdc_respiratory(),
}


async def ingest_all(
    limit_per_source: int = 5000,
    sources: List[str] | None = None,
) -> List[dict]:
    """Fetch and normalize snapshots from configured public-health sources.

    Args:
        limit_per_source: Maximum rows to request from each source.
        sources: Optional list of source names to ingest. If omitted, all
            registered sources are fetched.

    Returns:
        Deduplicated list of normalized snapshot dicts.
    """
    selected = sources if sources else list(SOURCE_FETCHERS.keys())
    unknown = [name for name in selected if name not in SOURCE_FETCHERS]
    if unknown:
        raise ValueError(f"Unknown ingestion source(s): {unknown}")

    coroutines = [
        SOURCE_FETCHERS[name](limit_per_source) for name in selected
    ]
    results = await asyncio.gather(*coroutines, return_exceptions=True)

    snapshots = []
    for name, result in zip(selected, results):
        if isinstance(result, Exception):
            logger.warning(f"Ingestion source '{name}' failed: {result}")
            continue
        snapshots.extend(result)
        logger.info(f"Ingestion source '{name}': {len(result)} snapshots")

    snapshots = deduplicate_snapshots(snapshots)
    logger.info(f"Ingested {len(snapshots)} normalized snapshots total")
    return snapshots


__all__ = ["ingest_all", "SOURCE_FETCHERS"]
