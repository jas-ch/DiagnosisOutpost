-- Migration: expand outbreak_snapshots and community_signals for real public-data ingestion.
-- Run this against the Cloud SQL PostgreSQL instance after deploying the updated models.
-- For local SQLite development, it is easier to delete the local .db/.sqlite3 file and let
-- Base.metadata.create_all() recreate the tables.

ALTER TABLE outbreak_snapshots
    ADD COLUMN IF NOT EXISTS source_id VARCHAR NOT NULL DEFAULT 'legacy';

-- Enforce idempotency for bulk upserts. Deduplicate first so the constraint
-- can be added safely on existing data.
DELETE FROM outbreak_snapshots a
USING outbreak_snapshots b
WHERE a.id < b.id
  AND a.source = b.source
  AND a.source_id = b.source_id;

ALTER TABLE outbreak_snapshots
    ADD CONSTRAINT IF NOT EXISTS uq_outbreak_snapshot_source_id
    UNIQUE (source, source_id);

-- Speed up the API's default ORDER BY report_date DESC LIMIT N query.
CREATE INDEX IF NOT EXISTS ix_outbreak_snapshots_report_date_desc
    ON outbreak_snapshots (report_date DESC);

ALTER TABLE outbreak_snapshots
    ADD COLUMN IF NOT EXISTS country VARCHAR,
    ADD COLUMN IF NOT EXISTS state VARCHAR,
    ADD COLUMN IF NOT EXISTS county VARCHAR,
    ADD COLUMN IF NOT EXISTS city VARCHAR,
    ADD COLUMN IF NOT EXISTS site VARCHAR,
    ADD COLUMN IF NOT EXISTS region_type VARCHAR,
    ADD COLUMN IF NOT EXISTS region_code VARCHAR,
    ADD COLUMN IF NOT EXISTS case_count INTEGER,
    ADD COLUMN IF NOT EXISTS metric_name VARCHAR,
    ADD COLUMN IF NOT EXISTS metric_value DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS metric_value_text VARCHAR,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW();

-- Drop the legacy default after existing rows have a value.
ALTER TABLE outbreak_snapshots ALTER COLUMN source_id DROP DEFAULT;

-- Backfill region from the legacy column when hierarchy is empty.
UPDATE outbreak_snapshots
SET region_type = 'region', region_code = region
WHERE region IS NOT NULL AND region_type IS NULL;

ALTER TABLE community_signals
    ADD COLUMN IF NOT EXISTS country VARCHAR,
    ADD COLUMN IF NOT EXISTS state VARCHAR,
    ADD COLUMN IF NOT EXISTS county VARCHAR,
    ADD COLUMN IF NOT EXISTS city VARCHAR,
    ADD COLUMN IF NOT EXISTS site VARCHAR,
    ADD COLUMN IF NOT EXISTS region_type VARCHAR,
    ADD COLUMN IF NOT EXISTS region_code VARCHAR;

UPDATE community_signals
SET region_type = 'region', region_code = region
WHERE region IS NOT NULL AND region_type IS NULL;
