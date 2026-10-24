from collections import Counter, defaultdict
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
import hashlib
import logging
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

from apscheduler.schedulers.background import BackgroundScheduler
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session
from sqlalchemy import text

from app import models, schemas
from app.config import get_settings
from app.database import Base, SessionLocal, engine, get_db
from app.ingestion import SOURCE_FETCHERS, ingest_all
from app.ingestion.common import canonical_condition_name
from app.routers import classify


def _ensure_database_constraints() -> None:
    """Create missing unique indexes/columns for existing databases."""
    db = SessionLocal()
    try:
        dialect = db.bind.dialect.name if db.bind else "sqlite"

        if dialect == "sqlite":
            # Remove duplicate (source, source_id) rows before adding a unique index.
            db.execute(
                text("""
                DELETE FROM outbreak_snapshots
                WHERE id NOT IN (
                    SELECT MIN(id) FROM outbreak_snapshots GROUP BY source, source_id
                )
                """)
            )
            existing_indexes = {
                r[0]
                for r in db.execute(
                    text(
                        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='outbreak_snapshots'"
                    )
                )
            }
            if "uq_outbreak_snapshot_source_id" not in existing_indexes:
                db.execute(
                    text(
                        "CREATE UNIQUE INDEX uq_outbreak_snapshot_source_id ON outbreak_snapshots(source, source_id)"
                    )
                )
            if "ix_outbreak_snapshots_report_date_desc" not in existing_indexes:
                db.execute(
                    text(
                        "CREATE INDEX ix_outbreak_snapshots_report_date_desc ON outbreak_snapshots(report_date DESC)"
                    )
                )
        elif dialect == "postgresql":
            db.execute(
                text("""
                DELETE FROM outbreak_snapshots a
                USING outbreak_snapshots b
                WHERE a.id < b.id
                  AND a.source = b.source
                  AND a.source_id = b.source_id;
                """)
            )
            db.execute(
                text("""
                DO $$
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM pg_constraint
                        WHERE conname = 'uq_outbreak_snapshot_source_id'
                    ) THEN
                        ALTER TABLE outbreak_snapshots
                        ADD CONSTRAINT uq_outbreak_snapshot_source_id
                        UNIQUE (source, source_id);
                    END IF;
                END $$;
                """)
            )
            db.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_outbreak_snapshots_report_date_desc "
                    "ON outbreak_snapshots (report_date DESC);"
                )
            )

        # Ensure the weekly_count column exists on existing tables.
        if dialect == "sqlite":
            columns = {
                row[1]
                for row in db.execute(text("PRAGMA table_info(outbreak_snapshots)"))
            }
            if "weekly_count" not in columns:
                db.execute(
                    text("ALTER TABLE outbreak_snapshots ADD COLUMN weekly_count INTEGER")
                )
        elif dialect == "postgresql":
            db.execute(
                text(
                    "ALTER TABLE outbreak_snapshots ADD COLUMN IF NOT EXISTS weekly_count INTEGER;"
                )
            )

        db.commit()
    finally:
        db.close()


# Create tables on startup (safe for local dev; Cloud SQL should use migrations)
Base.metadata.create_all(bind=engine)

# One-time safety net for databases created before the model evolved.
try:
    _ensure_database_constraints()
except Exception as exc:
    logger.warning(f"Could not ensure database constraints: {exc}")

settings = get_settings()


VALID_INGEST_SOURCES = sorted(SOURCE_FETCHERS.keys())


def _persist_snapshots(db: Session, snapshots: List[dict]) -> tuple[int, dict[str, int]]:
    """Idempotent upsert by (source, source_id). Returns total count and per-source counts."""
    if not snapshots:
        return 0, {}

    counts: Counter = Counter(s["source"] for s in snapshots)
    table = models.OutbreakSnapshot.__table__
    column_names = {c.name for c in table.columns}

    # Normalize each snapshot to columns that exist on the model.
    rows = [
        {k: v for k, v in snap.items() if k in column_names}
        for snap in snapshots
    ]

    dialect_name = db.bind.dialect.name if db.bind else "sqlite"
    if dialect_name == "postgresql":
        insert_func = pg_insert
    elif dialect_name == "sqlite":
        insert_func = sqlite_insert
    else:
        insert_func = None

    if insert_func is not None:
        update_cols = [
            c.name
            for c in table.columns
            if c.name not in ("source", "source_id", "id", "created_at")
        ]
        # PostgreSQL protocol limit: 65535 parameters per query. SQLite limit:
        # 999 parameters per query. With ~20 columns, cap SQLite batches at 40
        # rows and PostgreSQL batches at 1000 rows.
        batch_size = 1000 if dialect_name == "postgresql" else 40
        for i in range(0, len(rows), batch_size):
            batch = rows[i : i + batch_size]
            stmt = insert_func(table).values(batch)
            stmt = stmt.on_conflict_do_update(
                index_elements=["source", "source_id"],
                set_={col: stmt.excluded[col] for col in update_cols},
            )
            db.execute(stmt)
        db.commit()
        return len(snapshots), dict(counts)

    # Fallback for unsupported dialects: one-by-one upsert.
    for row in rows:
        existing = db.query(models.OutbreakSnapshot).filter_by(
            source=row["source"], source_id=row["source_id"]
        ).first()
        if existing:
            for key, value in row.items():
                if hasattr(existing, key):
                    setattr(existing, key, value)
        else:
            db.add(models.OutbreakSnapshot(**row))
    db.commit()
    return len(snapshots), dict(counts)


def run_ingestion():
    import asyncio

    snapshots = asyncio.run(ingest_all())
    db = SessionLocal()
    try:
        total, by_source = _persist_snapshots(db, snapshots)
        print(f"Scheduled ingestion completed: {total} snapshots {by_source}")
    finally:
        db.close()


# In-process scheduler is acceptable for local development only. In Cloud Run,
# use Cloud Scheduler calling POST /admin/ingest (see DEPLOYMENT.md Part 2.10).
# Detect production by the presence of a Cloud SQL connection name.
scheduler = BackgroundScheduler()
if not settings.cloud_sql_connection_name:
    scheduler.add_job(run_ingestion, "interval", minutes=settings.ingestion_interval_minutes)
    scheduler.start()
else:
    print("Cloud SQL detected; skipping in-process scheduler. Use /admin/ingest or Cloud Scheduler.")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Ensure unique indexes/columns exist for bulk upserts. This is a one-time
    # safety net for databases created before the model evolved.
    if settings.cloud_sql_connection_name:
        try:
            import asyncio
            await asyncio.to_thread(_ensure_database_constraints)
        except Exception as exc:
            logger.warning(f"Could not ensure database constraints: {exc}")
    yield
    if scheduler.running:
        scheduler.shutdown()


app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    lifespan=lifespan,
)

# Allow the Firebase-hosted web demo and local development to call the API.
# Credentials are not used by the public endpoints, but allowing them keeps
# the middleware permissive for future authenticated routes.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://do.jasinteractive.com",
        "https://diagnosis-odyssey.web.app",
        "http://localhost:8000",
        "http://localhost:5000",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(classify.router)


@app.get("/health")
def health():
    return {"status": "ok", "app": settings.app_name}


@app.post("/admin/ingest")
async def admin_ingest(
    x_ingest_secret: Optional[str] = Header(None, alias="X-Ingest-Secret"),
    source: Optional[str] = Query(
        None,
        description="Comma-separated source names to ingest. Omit to ingest all sources. Examples: cdc_nndss, who_covid, ecdc_respiratory.",
    ),
    db: Session = Depends(get_db),
):
    """Trigger ingestion from configured public-health sources.

    By default all sources are fetched. Pass `?source=cdc_nndss` (or a
    comma-separated list) to ingest only specific sources. This is the
    recommended pattern for Cloud Scheduler jobs to avoid request timeouts.
    """
    if settings.ingest_secret and x_ingest_secret != settings.ingest_secret:
        raise HTTPException(status_code=403, detail="Invalid ingest secret")

    sources = None
    if source:
        sources = [s.strip() for s in source.split(",") if s.strip()]
        unknown = [s for s in sources if s not in SOURCE_FETCHERS]
        if unknown:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown source(s): {unknown}. Valid sources: {VALID_INGEST_SOURCES}",
            )

    snapshots = await ingest_all(sources=sources)
    total, by_source = _persist_snapshots(db, snapshots)
    return {"ingested": total, "by_source": by_source, "sources": sources or VALID_INGEST_SOURCES}


@app.get("/outbreaks", response_model=List[schemas.OutbreakSnapshotResponse])
def list_outbreaks(
    region: Optional[str] = None,
    country: Optional[str] = None,
    state: Optional[str] = None,
    county: Optional[str] = None,
    city: Optional[str] = None,
    condition_name: Optional[str] = None,
    source: Optional[str] = None,
    date_from: Optional[datetime] = None,
    date_to: Optional[datetime] = None,
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
):
    query = db.query(models.OutbreakSnapshot)
    if region:
        query = query.filter(models.OutbreakSnapshot.region == region)
    if country:
        query = query.filter(models.OutbreakSnapshot.country == country)
    if state:
        query = query.filter(models.OutbreakSnapshot.state == state)
    if county:
        query = query.filter(models.OutbreakSnapshot.county == county)
    if city:
        query = query.filter(models.OutbreakSnapshot.city == city)
    if condition_name:
        query = query.filter(models.OutbreakSnapshot.condition_name == condition_name)
    if source:
        query = query.filter(models.OutbreakSnapshot.source == source)
    if date_from:
        query = query.filter(models.OutbreakSnapshot.report_date >= date_from)
    if date_to:
        query = query.filter(models.OutbreakSnapshot.report_date <= date_to)
    return query.order_by(models.OutbreakSnapshot.report_date.desc()).limit(limit).all()


@app.get("/outbreaks/recent", response_model=List[schemas.OutbreakSnapshotResponse])
def recent_outbreaks(
    days: int = Query(90, ge=1, le=365),
    limit: int = Query(1000, ge=1, le=2000),
    db: Session = Depends(get_db),
):
    """Return recent snapshots across all sources in a single request.

    This is the preferred endpoint for the live map because it avoids the
    mobile-timeout problems caused by firing one request per ingestion source.
    """
    cutoff = datetime.utcnow() - timedelta(days=days)
    return (
        db.query(models.OutbreakSnapshot)
        .filter(models.OutbreakSnapshot.report_date >= cutoff)
        .order_by(models.OutbreakSnapshot.report_date.desc())
        .limit(limit)
        .all()
    )


_AGGREGATE_WINDOW_DAYS = 365


@app.get("/outbreaks/aggregate")
def aggregate_outbreaks(db: Session = Depends(get_db)):
    """Return pre-aggregated US and global stats per disease.

    This powers the carousel cards so the Flutter app only needs one backend
    call instead of one call per ingestion source.
    """
    cutoff = datetime.utcnow() - timedelta(days=_AGGREGATE_WINDOW_DAYS)
    rows = (
        db.query(models.OutbreakSnapshot)
        .filter(models.OutbreakSnapshot.report_date >= cutoff)
        .all()
    )

    diseases: Dict[str, Dict[str, Any]] = {}

    for row in rows:
        condition = canonical_condition_name(row.condition_name)
        if not condition:
            continue
        diseases.setdefault(condition, {"condition_name": condition})

    for condition, bucket in diseases.items():
        bucket["us"] = _aggregate_us(rows, condition)
        bucket["global"] = _aggregate_global(rows, condition)

    return {
        "aggregated_at": datetime.utcnow().isoformat(),
        "diseases": diseases,
    }


_US_NATIONAL_NAMES = {"u.s. residents", "united states", "usa", "us residents", "national"}


def _is_us_national(region: Optional[str]) -> bool:
    if not region:
        return False
    return region.strip().lower() in _US_NATIONAL_NAMES


def _metric_priority(metric_name: Optional[str]) -> int:
    """Lower number = more representative for a carousel card."""
    return {
        "cases": 0,
        "new_cases": 1,
        "new_admissions": 2,
        "admissions": 2,
        "percent_positivity": 3,
        "percent_visits": 3,
        "wastewater_level": 4,
        "pcr_target_avg_conc": 4,
        "activity_level": 4,
    }.get((metric_name or "").lower(), 5)


def _primary_metric_name(rows: List[models.OutbreakSnapshot]) -> Optional[str]:
    names = Counter(r.metric_name for r in rows if r.metric_name)
    if not names:
        return None
    return names.most_common(1)[0][0]


def _make_aggregate_block(
    latest_rows: List[models.OutbreakSnapshot],
    weekly_new: Optional[int],
    ytd: Optional[int],
    weekly_change: Optional[int],
    report_date: Optional[datetime] = None,
    is_admissions: bool = False,
) -> Dict[str, Any]:
    """Build the standardized aggregate block returned by the API."""
    sources = sorted({r.source for r in latest_rows})
    primary_source = Counter(r.source for r in latest_rows).most_common(1)[0][0]
    if report_date is None:
        report_date = latest_rows[0].report_date
    return {
        "weekly_new": weekly_new,
        "weekly_new_label": "weekly",
        "ytd": ytd,
        "ytd_label": "YTD",
        "weekly_change": weekly_change,
        "weekly_change_label": "change",
        "is_admissions": is_admissions,
        "source": primary_source,
        "sources": sources,
        "report_date": report_date.isoformat() if report_date else None,
    }


def _safe_int(value: Optional[float]) -> Optional[int]:
    if value is None:
        return None
    return int(value)


def _add_counts(a: Optional[int], b: Optional[int]) -> Optional[int]:
    """Add two optional counts, returning None only when both are None."""
    if a is None and b is None:
        return None
    return (a or 0) + (b or 0)


def _aggregate_us(rows: List[models.OutbreakSnapshot], condition: str) -> Optional[Dict[str, Any]]:
    # Canonicalize condition names so stale rows with non-canonical labels
    # (e.g. "RSV", "SARS-CoV-2", "ARI") are merged into the representative bucket.
    us_rows = [
        r
        for r in rows
        if canonical_condition_name(r.condition_name) == condition and r.country == "United States"
    ]
    if not us_rows:
        return None

    def _group_by_date(rows_subset: List[models.OutbreakSnapshot]):
        groups: Dict[datetime, List[models.OutbreakSnapshot]] = defaultdict(list)
        for r in rows_subset:
            if r.report_date:
                groups[r.report_date].append(r)
        return groups

    def _row_value(r: models.OutbreakSnapshot) -> float:
        if r.case_count is not None:
            return float(r.case_count)
        if r.metric_value is not None:
            return r.metric_value
        return 0.0

    def _preferred_activity_rows(rows_subset: List[models.OutbreakSnapshot]):
        """Pick the single best non-case source, preferring clearer time periods.

        Ranking: weekly admissions > daily new cases > percentage/activity > wastewater.
        Tie-break by most recent report date, then by row count.
        """
        by_source: Dict[str, List[models.OutbreakSnapshot]] = defaultdict(list)
        for r in rows_subset:
            if r.metric_value is not None or r.metric_value_text is not None:
                by_source[r.source].append(r)
        if not by_source:
            return rows_subset

        def _sort_key(item):
            source, source_rows = item
            primary = _primary_metric_name(source_rows)
            priority = _metric_priority(primary)
            latest = max((r.report_date for r in source_rows if r.report_date), default=None)
            return (priority, latest is None, latest or datetime.min, -len(source_rows))

        chosen = sorted(by_source.items(), key=_sort_key)[0][0]
        return by_source[chosen]

    def _best_source_rows(rows_subset: List[models.OutbreakSnapshot]):
        """Pick the single best source, balancing metric priority and recency.

        A much fresher lower-priority source wins over a stale high-priority
        source (threshold: >30 days newer). This prevents stale NNDSS case-count
        snapshots from shadowing current hospital-admissions or ED data.
        """
        by_source: Dict[str, List[models.OutbreakSnapshot]] = defaultdict(list)
        for r in rows_subset:
            by_source[r.source].append(r)
        if not by_source:
            return rows_subset

        def _latest_date(source_rows: List[models.OutbreakSnapshot]) -> Optional[datetime]:
            return max((r.report_date for r in source_rows if r.report_date), default=None)

        def _sort_key(item):
            source, source_rows = item
            primary = _primary_metric_name(source_rows)
            priority = _metric_priority(primary)
            latest = _latest_date(source_rows)
            return (priority, latest is None, latest or datetime.min, -len(source_rows))

        ranked = sorted(by_source.items(), key=_sort_key)
        best_source, best_rows = ranked[0]
        best_latest = _latest_date(best_rows)
        for source, source_rows in ranked[1:]:
            latest = _latest_date(source_rows)
            if (
                best_latest
                and latest
                and (latest - best_latest).days > 30
            ):
                return source_rows
        return best_rows

    def _build_block(
        latest_rows: List[models.OutbreakSnapshot],
        prior_rows: Optional[List[models.OutbreakSnapshot]] = None,
        all_rows: Optional[List[models.OutbreakSnapshot]] = None,
    ):
        has_case_count = any(r.case_count is not None for r in latest_rows)
        primary_metric = _primary_metric_name(latest_rows)

        # CDC NNDSS-style case counts: m1 = current week, m3 = YTD cumulative.
        if has_case_count:
            weekly_new = sum(r.weekly_count or 0 for r in latest_rows)
            ytd = int(sum(_row_value(r) for r in latest_rows))
            prior_weekly = sum(r.weekly_count or 0 for r in prior_rows) if prior_rows else 0
            if weekly_new == 0 and prior_rows is not None:
                # Fallback when m1 is missing: derive weekly from YTD difference.
                prior_ytd = int(sum(_row_value(r) for r in prior_rows))
                weekly_new = max(ytd - prior_ytd, 0)
            weekly_change = weekly_new - prior_weekly
            return _make_aggregate_block(latest_rows, weekly_new, ytd, weekly_change)

        # Daily new cases (e.g., a hypothetical US daily feed).
        if primary_metric == "new_cases" and all_rows:
            by_date: Dict[datetime, float] = defaultdict(float)
            for r in all_rows:
                if r.report_date and r.metric_value is not None:
                    by_date[r.report_date] += r.metric_value
            sorted_dates = sorted(by_date.keys(), reverse=True)
            latest_7 = sum(by_date[d] for d in sorted_dates[:7])
            prior_7 = sum(by_date[d] for d in sorted_dates[7:14])
            weekly_new = int(latest_7)
            weekly_change = int(latest_7 - prior_7)
            primary_source = Counter(r.source for r in latest_rows).most_common(1)[0][0]
            ytd = _ytd_sum_us(all_rows, primary_source, primary_metric)
            return _make_aggregate_block(latest_rows, weekly_new, ytd, weekly_change)

        # Hospital admissions are a countable outcome. When no true case-count
        # feed is available, use admissions as the accounting basis so the cards
        # remain informative. The frontend uses the is_admissions flag to label
        # the numbers as "admissions" rather than "cases".
        if primary_metric in {"new_admissions", "admissions"}:
            weekly_new = int(sum(r.metric_value or 0 for r in latest_rows))
            prior_weekly = (
                int(sum(r.metric_value or 0 for r in prior_rows)) if prior_rows else 0
            )
            primary_source = Counter(r.source for r in latest_rows).most_common(1)[0][0]
            ytd = _ytd_sum_us(all_rows or latest_rows, primary_source, primary_metric)
            return _make_aggregate_block(
                latest_rows,
                weekly_new,
                ytd,
                weekly_new - prior_weekly,
                is_admissions=True,
            )

        # Activity, percentage, and wastewater metrics are intentionally not
        # surfaced as case counts to keep the four-card metrics consistent.
        return _make_aggregate_block(latest_rows, None, None, None)

    # Pick the single best US source for this condition. Rank sources by metric
    # priority (real cases > admissions > percentages > wastewater), but do not
    # let a stale high-priority source override a much fresher lower-priority
    # source. This prevents stale 2022 NNDSS case-count rows from beating
    # current CDC hospital-admissions or NSSP ED data for Influenza A/ARI.
    target_rows = _best_source_rows(us_rows)

    national = [r for r in target_rows if _is_us_national(r.region)]
    if national:
        groups = _group_by_date(national)
        sorted_dates = sorted(groups.keys(), reverse=True)
        latest_rows = groups[sorted_dates[0]]
        prior_rows = groups[sorted_dates[1]] if len(sorted_dates) > 1 else None
        return _build_block(latest_rows, prior_rows, all_rows=target_rows)

    # No national row: sum the most recent state-level rows.
    state_rows = [r for r in target_rows if not _is_us_national(r.region)]
    if not state_rows:
        return None
    groups = _group_by_date(state_rows)
    sorted_dates = sorted(groups.keys(), reverse=True)
    latest_rows = groups[sorted_dates[0]]
    prior_rows = groups[sorted_dates[1]] if len(sorted_dates) > 1 else None
    return _build_block(latest_rows, prior_rows, all_rows=target_rows)


def _aggregate_global(rows: List[models.OutbreakSnapshot], condition: str) -> Optional[Dict[str, Any]]:
    """Return global stats for a condition, including US totals.

    The US is part of the world, so global numbers should never be zero while
    the US has reported cases. We combine the non-US/global source with the US
    source and sum numeric totals, unless the non-US source already has global
    coverage (e.g. WHO COVID-19 cases or WHO DON alerts), in which case we use
    it directly to avoid double-counting the US. Labels are fixed to
    "weekly"/"YTD"/"change" because the US/Global toggle already communicates
    the geography.
    """
    condition_rows = [
        r for r in rows if canonical_condition_name(r.condition_name) == condition
    ]
    us_block = _aggregate_us(rows, condition)
    non_us_block = _aggregate_non_us(condition_rows, condition)

    if us_block is None and non_us_block is None:
        return None
    if us_block is None:
        return non_us_block
    if non_us_block is None:
        return us_block

    us_is_admissions = bool(us_block.get("is_admissions"))
    non_us_is_admissions = bool(non_us_block.get("is_admissions"))

    coverage = non_us_block.get("coverage")
    # If the non-US source already covers the whole world with real case counts,
    # don't add the US block on top and double-count.
    if coverage == "global":
        return {**non_us_block, "is_admissions": non_us_is_admissions}
    # WHO DON alerts are worldwide event notifications, not cumulative cases.
    # Don't mix alert counts with case counts; fall back to US data for the
    # global figure so the card never shows a stale 0.
    if coverage == "global_alerts":
        return {**us_block, "is_admissions": us_is_admissions}
    # Americas-only sources (PAHO dengue) are combined with US data so the
    # global card reflects the full Region of the Americas plus the US.
    # The fetcher is responsible for excluding US rows if the source already
    # includes them, to avoid double-counting.

    # Do not mix case counts with hospital admissions. If one block is
    # case-based and the other is admissions-based, prefer the case-based
    # block so the global metric has a single consistent accounting basis.
    if us_is_admissions and not non_us_is_admissions:
        return {**non_us_block, "is_admissions": False}
    if non_us_is_admissions and not us_is_admissions:
        return {**us_block, "is_admissions": False}

    # When neither side has countable numbers (e.g. ILI activity / percent
    # visits), report the global/non-US source so the source line stays
    # geographically relevant instead of listing a US surveillance source for
    # the worldwide figure.
    if (
        us_block.get("weekly_new") is None
        and us_block.get("ytd") is None
        and non_us_block.get("weekly_new") is None
        and non_us_block.get("ytd") is None
    ):
        return non_us_block

    report_date = non_us_block.get("report_date") or us_block.get("report_date")
    source = f"{us_block.get('source')}, {non_us_block.get('source')}"
    sources = sorted(
        set((us_block.get("sources") or [])) | set((non_us_block.get("sources") or []))
    )

    return {
        "weekly_new": _add_counts(us_block.get("weekly_new"), non_us_block.get("weekly_new")),
        "weekly_new_label": "weekly",
        "ytd": _add_counts(us_block.get("ytd"), non_us_block.get("ytd")),
        "ytd_label": "YTD",
        "weekly_change": _add_counts(us_block.get("weekly_change"), non_us_block.get("weekly_change")),
        "weekly_change_label": "change",
        "is_admissions": us_is_admissions or non_us_is_admissions,
        "source": source,
        "sources": sources,
        "report_date": report_date,
    }


def _ytd_sum(rows: List[models.OutbreakSnapshot], source: str, metric_name: str) -> Optional[int]:
    """Sum metric_value from 1 Jan of the current year through today."""
    year_start = datetime(datetime.utcnow().year, 1, 1)
    total = sum(
        r.metric_value or 0
        for r in rows
        if r.source == source
        and r.metric_name == metric_name
        and r.report_date
        and r.report_date >= year_start
    )
    return int(total) if total else None


def _ytd_sum_us(rows: List[models.OutbreakSnapshot], source: str, metric_name: str) -> Optional[int]:
    """Sum a US metric year-to-date, preferring national rows when available.

    This avoids double-counting when a feed contains both a USA total and
    individual state rows for the same date.
    """
    year_start = datetime(datetime.utcnow().year, 1, 1)
    national = [
        r
        for r in rows
        if r.source == source
        and r.metric_name == metric_name
        and r.report_date
        and r.report_date >= year_start
        and _is_us_national(r.region)
    ]
    target_rows = national if national else rows
    total = sum(
        r.metric_value or 0
        for r in target_rows
        if r.source == source
        and r.metric_name == metric_name
        and r.report_date
        and r.report_date >= year_start
    )
    return int(total) if total else None


def _aggregate_non_us(rows: List[models.OutbreakSnapshot], condition: str) -> Optional[Dict[str, Any]]:
    """Return the non-US/global aggregate for a condition, or None if absent.

    Sources that already have worldwide coverage (WHO COVID-19 cases, WHO DON
    alerts, WHO FluNet, WHO Measles, WHO Mpox) include a ``coverage: "global"``
    marker so ``_aggregate_global`` does not add the US block on top and
    double-count.  Regional sources (PAHO dengue) use ``coverage: "americas"``
    so they are combined with US data for the global card.

    Rows are not filtered by country here; that lets truly global sources
    represent worldwide coverage while regional sources remain labeled.
    """
    # COVID-19: WHO weekly country-level new cases.  Each report_date in the
    # WHO CSV is a weekly snapshot, so summing 7 consecutive dates would mix
    # multiple weeks and produce an inflated total.  Use the latest single date
    # that has a meaningful global total; fall back to the highest recent date
    # if the very latest snapshot is incomplete.
    if condition == "COVID-19":
        who_covid = [
            r
            for r in rows
            if r.source == "who_covid_cases" and r.metric_name == "new_cases" and r.metric_value is not None
        ]
        if who_covid:
            by_date: Dict[datetime, float] = defaultdict(float)
            for r in who_covid:
                date = r.report_date
                if date:
                    by_date[date] += r.metric_value
            sorted_dates = sorted(by_date.keys(), reverse=True)
            candidate_dates = sorted_dates[:14]
            best_date = None
            for d in candidate_dates:
                if by_date[d] >= 1000:
                    best_date = d
                    break
            if best_date is None:
                best_date = max(candidate_dates, key=lambda d: (by_date[d], d))
            date_index = sorted_dates.index(best_date)
            prior_date = sorted_dates[date_index + 1] if date_index + 1 < len(sorted_dates) else None
            weekly_new = int(by_date[best_date])
            prior_weekly = int(by_date[prior_date]) if prior_date else 0
            ytd = _ytd_sum(who_covid, "who_covid_cases", "new_cases")
            return {
                **_make_aggregate_block(who_covid, weekly_new, ytd, weekly_new - prior_weekly, report_date=best_date),
                "coverage": "global",
            }

    # Influenza A / RSV / ARI: WHO FluNet weekly country-level data.
    # The feed covers all WHO regions (including the US), so it is treated as
    # global coverage and the US CDC block is not added on top.
    if condition in {"Influenza A", "Respiratory Syncytial Virus", "Acute Respiratory Infection"}:
        metric_map = {
            "Influenza A": ("cases", "INF_A"),
            "Respiratory Syncytial Virus": ("cases", "RSV"),
            "Acute Respiratory Infection": ("ili_activity", "ILI_ACTIVITY"),
        }
        metric_name, _column_hint = metric_map[condition]
        flunet = [
            r
            for r in rows
            if r.source == "who_flunet" and r.metric_name == metric_name and r.metric_value is not None
        ]
        if flunet:
            # Group by week.  The absolute latest week is often incomplete (only
            # a few countries have reported).  Use the most recent week among
            # the last four that has the most reporting countries.
            by_week: Dict[datetime, List[float]] = defaultdict(list)
            for r in flunet:
                if r.report_date:
                    by_week[r.report_date].append(r.metric_value)
            sorted_weeks = sorted(by_week.keys(), reverse=True)
            if sorted_weeks:
                candidate_weeks = sorted_weeks[:4]
                best_week = max(
                    candidate_weeks,
                    key=lambda d: (len(by_week[d]), d),
                )
                week_index = sorted_weeks.index(best_week)
                latest_values = by_week[best_week]
                prior_values = by_week[sorted_weeks[week_index + 1]] if week_index + 1 < len(sorted_weeks) else []

                if condition == "Acute Respiratory Infection":
                    # ILI activity is an ordinal level, not a case count.  With
                    # the new consistent metric definitions it is intentionally
                    # surfaced as unavailable rather than mixed with case counts.
                    return _make_aggregate_block(flunet, None, None, None)

                weekly_new = int(sum(latest_values))
                prior_weekly = int(sum(prior_values)) if prior_values else 0
                ytd = _ytd_sum(flunet, "who_flunet", metric_name)
                return {
                    **_make_aggregate_block(flunet, weekly_new, ytd, weekly_new - prior_weekly, report_date=best_week),
                    "coverage": "global",
                }

        # Fallback to ECDC for Influenza A and RSV when WHO FluNet is absent.
        if condition in {"Influenza A", "Respiratory Syncytial Virus"}:
            ecdc = [r for r in rows if r.source == "ecdc_respiratory" and r.metric_value is not None]
            if ecdc:
                by_week: Dict[datetime, List[float]] = defaultdict(list)
                for r in ecdc:
                    if r.report_date:
                        by_week[r.report_date].append(r.metric_value)
                sorted_weeks = sorted(by_week.keys(), reverse=True)
                if sorted_weeks:
                    weekly_new = int(sum(by_week[sorted_weeks[0]]))
                    prior_weekly = (
                        int(sum(by_week[sorted_weeks[1]]))
                        if len(sorted_weeks) > 1 else 0
                    )
                    return {
                        **_make_aggregate_block(ecdc, weekly_new, None, weekly_new - prior_weekly, report_date=sorted_weeks[0]),
                        "coverage": "europe",
                    }

    # Measles: WHO monthly country-level case counts.
    if condition == "Measles":
        who_measles = [
            r
            for r in rows
            if r.source == "who_measles_monthly" and r.metric_name == "cases" and r.metric_value is not None
        ]
        if who_measles:
            # Group by month.  The latest month is often incomplete; use the
            # latest month among the last three that has at least 10 reporting
            # countries (non-zero case counts).  This keeps the number close to
            # real time without showing a nearly empty partial month.
            by_month: Dict[datetime, List[float]] = defaultdict(list)
            for r in who_measles:
                if r.report_date:
                    by_month[r.report_date].append(r.metric_value)
            sorted_months = sorted(by_month.keys(), reverse=True)
            if sorted_months:
                candidate_months = sorted_months[:3]
                best_month = None
                for d in candidate_months:
                    reporters = len([v for v in by_month[d] if v])
                    if reporters >= 10:
                        best_month = d
                        break
                if best_month is None:
                    best_month = max(
                        candidate_months,
                        key=lambda d: (len([v for v in by_month[d] if v]), d),
                    )
                month_index = sorted_months.index(best_month)
                weekly_new = int(sum(by_month[best_month]))
                prior_weekly = (
                    int(sum(by_month[sorted_months[month_index + 1]]))
                    if month_index + 1 < len(sorted_months)
                    else 0
                )
                ytd = _ytd_sum(who_measles, "who_measles_monthly", "cases")
                return {
                    **_make_aggregate_block(who_measles, weekly_new, ytd, weekly_new - prior_weekly, report_date=best_month),
                    "coverage": "global",
                }

    # Mpox: WHO daily/weekly country-level new confirmed cases.  The latest
    # date is often sparse, so use the latest single date in the last 14 days
    # that has a meaningful global total; fall back to the highest recent date
    # otherwise.
    if condition == "Mpox":
        who_mpox = [
            r
            for r in rows
            if r.source == "who_mpox" and r.metric_name == "new_cases" and r.metric_value is not None
        ]
        if who_mpox:
            by_date: Dict[datetime, float] = defaultdict(float)
            for r in who_mpox:
                if r.report_date:
                    by_date[r.report_date] += r.metric_value
            sorted_dates = sorted(by_date.keys(), reverse=True)
            candidate_dates = sorted_dates[:14]
            best_date = None
            for d in candidate_dates:
                if by_date[d] >= 10:
                    best_date = d
                    break
            if best_date is None:
                best_date = max(candidate_dates, key=lambda d: (by_date[d], d))
            date_index = sorted_dates.index(best_date)
            prior_date = sorted_dates[date_index + 1] if date_index + 1 < len(sorted_dates) else None
            weekly_new = int(by_date[best_date])
            prior_weekly = int(by_date[prior_date]) if prior_date else 0
            ytd = _ytd_sum(who_mpox, "who_mpox", "new_cases")
            return {
                **_make_aggregate_block(who_mpox, weekly_new, ytd, weekly_new - prior_weekly, report_date=best_date),
                "coverage": "global",
            }

    # Dengue fever: PAHO Americas dengue indicators.
    # PAHO covers the Americas (including the US), but the feed is currently
    # dashboard-based and often unavailable.  When data is present, treat it as
    # Americas coverage and combine it with US CDC dengue data for the global
    # card so the global figure reflects the Americas region.
    if condition == "Dengue fever":
        paho = [
            r
            for r in rows
            if r.source == "paho_dengue" and r.metric_name == "cases" and r.metric_value is not None
        ]
        if paho:
            by_week: Dict[datetime, float] = defaultdict(float)
            for r in paho:
                if r.report_date:
                    by_week[r.report_date] += r.metric_value
            sorted_weeks = sorted(by_week.keys(), reverse=True)
            if sorted_weeks:
                weekly_new = int(by_week[sorted_weeks[0]])
                prior_weekly = int(by_week[sorted_weeks[1]]) if len(sorted_weeks) > 1 else 0
                return {
                    **_make_aggregate_block(paho, weekly_new, None, weekly_new - prior_weekly, report_date=sorted_weeks[0]),
                    "coverage": "americas",
                }

    # Everything else: WHO DON outbreak alerts.
    # DON alerts are worldwide event notifications, not cumulative case counts.
    # With the new metric definitions they are intentionally not surfaced as
    # case counts, so they are treated as unavailable.
    return None


@app.post("/signals", response_model=schemas.CommunitySignalResponse)
def create_signal(signal: schemas.CommunitySignalCreate, db: Session = Depends(get_db)):
    db_signal = models.CommunitySignal(**signal.model_dump())
    db.add(db_signal)
    db.commit()
    db.refresh(db_signal)
    return db_signal


@app.get("/signals/aggregate")
def aggregate_signals(
    region: Optional[str] = None,
    country: Optional[str] = None,
    state: Optional[str] = None,
    county: Optional[str] = None,
    city: Optional[str] = None,
    db: Session = Depends(get_db),
):
    query = db.query(models.CommunitySignal)
    if region:
        query = query.filter(models.CommunitySignal.region == region)
    if country:
        query = query.filter(models.CommunitySignal.country == country)
    if state:
        query = query.filter(models.CommunitySignal.state == state)
    if county:
        query = query.filter(models.CommunitySignal.county == county)
    if city:
        query = query.filter(models.CommunitySignal.city == city)
    rows = query.all()
    by_risk_level = {}
    for row in rows:
        by_risk_level[row.risk_level] = by_risk_level.get(row.risk_level, 0) + 1
    return {
        "count": len(rows),
        "by_risk_level": by_risk_level,
        "signals": [schemas.CommunitySignalResponse.model_validate(r).model_dump() for r in rows],
    }


ONLINE_WINDOW_MINUTES = 5


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


@app.post("/heartbeat")
def heartbeat(
    request: schemas.HeartbeatRequest,
    db: Session = Depends(get_db),
):
    """Receive an anonymized heartbeat from a client session.

    Only a one-way hash of the client token is stored. No IP, location, or
    personal data is kept. The token should be a random UUID generated on the
    device and rotated periodically.
    """
    token_hash = _hash_token(request.token)
    existing = (
        db.query(models.OnlineHeartbeat)
        .filter(models.OnlineHeartbeat.session_token_hash == token_hash)
        .first()
    )
    if existing:
        existing.last_seen_at = datetime.utcnow()
    else:
        db.add(
            models.OnlineHeartbeat(
                session_token_hash=token_hash,
                last_seen_at=datetime.utcnow(),
            )
        )
    db.commit()
    return {"status": "ok"}


@app.get("/online", response_model=schemas.OnlineCountResponse)
def online_count(db: Session = Depends(get_db)):
    """Return the approximate number of active users in the last N minutes."""
    cutoff = datetime.utcnow() - timedelta(minutes=ONLINE_WINDOW_MINUTES)
    count = (
        db.query(models.OnlineHeartbeat)
        .filter(models.OnlineHeartbeat.last_seen_at >= cutoff)
        .count()
    )
    return {"count": count, "window_minutes": ONLINE_WINDOW_MINUTES}
