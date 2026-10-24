import hashlib
import logging
from datetime import datetime
from typing import Any, Iterable, List, Optional

logger = logging.getLogger(__name__)

# Canonical condition names used by the frontend outbreak-intel cards.
# Each key is a canonical name; values are lower-cased synonyms seen in
# public-health data sources (CDC, WHO, ECDC).
CANONICAL_CONDITIONS: dict[str, list[str]] = {
    "Influenza A": ["influenza", "flu", "influenza a", "influenza a virus", "h1n1", "h3n2", "seasonal influenza"],
    "COVID-19": ["covid-19", "covid", "covid 19", "sars-cov-2", "sars cov 2", "coronavirus"],
    "Measles": ["measles", "morbilli"],
    "Norovirus": ["norovirus", "norwalk"],
    "Mpox": ["mpox", "monkeypox"],
    "Dengue fever": ["dengue", "dengue fever", "dengue virus"],
    "Pertussis": ["pertussis", "whooping cough", "bordetella pertussis"],
    "Respiratory Syncytial Virus": ["rsv", "respiratory syncytial virus"],
    "Scarlet fever": ["scarlet fever", "group a strep", "group a streptococcus", "streptococcus pyogenes"],
    "Hand-foot-mouth disease": ["hand-foot-mouth", "hand foot mouth", "hfmd", "coxsackievirus", "enterovirus"],
    "Chickenpox": ["chickenpox", "varicella", "varicella-zoster"],
    "Acute Respiratory Infection": ["acute respiratory infection", "ari"],
}


def canonical_condition_name(name: Optional[str]) -> Optional[str]:
    """Return a canonical condition name if the raw name is a known synonym.

    The match is substring-based so source labels like 'Measles, Total' or
    'Influenza A virus' still resolve correctly. Returns the original name
    (cleaned) when no canonical form is recognized.
    """
    raw = clean_str(name)
    if raw is None:
        return None
    lower = raw.lower()
    for canonical, synonyms in CANONICAL_CONDITIONS.items():
        if lower == canonical.lower():
            return canonical
        for synonym in synonyms:
            if synonym in lower:
                return canonical
    return raw


def clean_str(value: Any) -> Optional[str]:
    if value is None:
        return None
    s = str(value).strip()
    return s if s and s not in (".", "-", "NA", "N/A") else None


def coerce_float(value: Any) -> Optional[float]:
    s = clean_str(value)
    if s is None:
        return None
    try:
        return float(s)
    except (ValueError, TypeError):
        return None


def coerce_int(value: Any) -> Optional[int]:
    s = clean_str(value)
    if s is None:
        return None
    try:
        return int(float(s))
    except (ValueError, TypeError):
        return None


def parse_date(value: Any) -> Optional[datetime]:
    s = clean_str(value)
    if s is None:
        return None
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    formats = (
        "%Y-%m-%dT%H:%M:%S.%f%z",
        "%Y-%m-%dT%H:%M:%S%z",
        "%Y-%m-%dT%H:%M:%S.%f",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d",
    )
    for fmt in formats:
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def parse_yearweek(value: Any) -> Optional[datetime]:
    s = clean_str(value)
    if s is None:
        return None
    # ISO week format used by ECDC: 2026-W37
    if s.upper().startswith("W"):
        s = s[1:]
    if "-W" in s.upper():
        try:
            return datetime.strptime(s.upper() + "-1", "%G-W%V-%u")
        except ValueError:
            return None
    return None


def parse_mmwr_week(year: Any, week: Any) -> Optional[datetime]:
    y = clean_str(year)
    w = clean_str(week)
    if not y or not w:
        return None
    try:
        return datetime.strptime(f"{y}-W{int(w):02d}-1", "%G-W%V-%u")
    except ValueError:
        return None


def _clean_part(value: Any) -> str:
    s = clean_str(value)
    if s is None:
        return ""
    # Avoid ambiguity in the composite id by replacing the delimiter.
    return s.replace(":", "_").replace("|", "_")


def build_source_id(source: str, parts: Iterable[Any], max_length: int = 512) -> str:
    cleaned = [_clean_part(p) for p in parts]
    cleaned = [p for p in cleaned if p]
    if not cleaned:
        cleaned = ["unknown"]
    composite = ":".join([source, *cleaned])
    if len(composite) > max_length:
        digest = hashlib.sha256(composite.encode("utf-8")).hexdigest()[:16]
        composite = composite[: max_length - len(digest) - 1] + ":" + digest
    return composite


def derive_region_type(snapshot: dict) -> Optional[str]:
    if snapshot.get("site"):
        return "site"
    if snapshot.get("county"):
        return "county"
    if snapshot.get("city"):
        return "city"
    if snapshot.get("state"):
        return "state"
    if snapshot.get("country"):
        return "country"
    return None


def deduplicate_snapshots(snapshots: List[dict]) -> List[dict]:
    seen = set()
    out = []
    for snap in snapshots:
        key = (snap.get("source"), snap.get("source_id"))
        if key in seen:
            continue
        seen.add(key)
        out.append(snap)
    return out
