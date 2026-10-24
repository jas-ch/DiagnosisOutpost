from sqlalchemy import Column, Index, Integer, String, Float, DateTime, JSON, UniqueConstraint, func

from app.database import Base


class OutbreakSnapshot(Base):
    __tablename__ = "outbreak_snapshots"

    id = Column(Integer, primary_key=True, index=True)

    # Source and idempotency
    source = Column(String, index=True, nullable=False)  # e.g., 'cdc_nndss', 'who_covid', 'ecdc_respiratory'
    source_id = Column(String, index=True, nullable=False)  # unique identifier from the source dataset

    # Geographic hierarchy (finest active granularity depends on source)
    country = Column(String, index=True, nullable=True)
    state = Column(String, index=True, nullable=True)  # U.S. state or equivalent first-level division
    county = Column(String, index=True, nullable=True)
    city = Column(String, index=True, nullable=True)
    site = Column(String, index=True, nullable=True)  # reserved for future wastewater/site-level sources; not used by MVP API

    # Normalized region helpers
    region_type = Column(String, index=True, nullable=True)  # 'country', 'state', 'county', 'city', 'site'
    region_code = Column(String, index=True, nullable=True)  # ISO code, FIPS code, or source-specific code

    # Legacy single-region column kept for backward compatibility during transition
    region = Column(String, index=True, nullable=True)

    # Condition / metric
    condition_name = Column(String, index=True, nullable=True)  # human-readable condition label
    case_count = Column(Integer, nullable=True)  # legacy numeric field; prefer metric_value for new data
    weekly_count = Column(Integer, nullable=True)  # current-week new cases (e.g., CDC NNDSS m1)
    metric_name = Column(String, index=True, nullable=True)  # e.g., 'cases', 'admissions', 'percent_positivity', 'wastewater_level'
    metric_value = Column(Float, nullable=True)  # numeric value when applicable
    metric_value_text = Column(String, nullable=True)  # original text value when numeric is not meaningful (e.g., 'Low', 'Moderate')

    # Timing
    report_date = Column(DateTime, nullable=True, index=True)  # date the metric was reported by the source
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())

    # Indexes for common API queries.
    __table_args__ = (
        UniqueConstraint("source", "source_id", name="uq_outbreak_snapshot_source_id"),
        Index("ix_outbreak_snapshots_report_date_desc", report_date.desc()),
    )

    # Raw payload and bookkeeping
    metadata_json = Column(JSON, default=dict)
    created_at = Column(DateTime, default=func.now())


class CommunitySignal(Base):
    __tablename__ = "community_signals"

    id = Column(Integer, primary_key=True, index=True)
    anonymous_id = Column(String, index=True, nullable=False)

    # Geographic hierarchy (MVP API accepts state/county/city; site is reserved)
    country = Column(String, index=True, nullable=True)
    state = Column(String, index=True, nullable=True)
    county = Column(String, index=True, nullable=True)
    city = Column(String, index=True, nullable=True)
    site = Column(String, index=True, nullable=True)  # reserved; rejected by MVP API

    region_type = Column(String, index=True, nullable=True)
    region_code = Column(String, index=True, nullable=True)

    # Legacy single-region column kept for backward compatibility during transition
    region = Column(String, index=True, nullable=True)

    symptom_summary = Column(String, nullable=True)
    risk_level = Column(String, nullable=True)
    reported_at = Column(DateTime, default=func.now())
    metadata_json = Column(JSON, default=dict)


class OnlineHeartbeat(Base):
    """Privacy-first active-session heartbeat.

    Stores only a one-way hash of a client-generated session token and the
    last seen timestamp. No IP, location, or user-identifying data is kept.
    """

    __tablename__ = "online_heartbeats"

    id = Column(Integer, primary_key=True, index=True)
    session_token_hash = Column(String, index=True, nullable=False, unique=True)
    last_seen_at = Column(DateTime, default=func.now(), onupdate=func.now(), index=True)
