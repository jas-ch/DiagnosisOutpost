-- v2: Add online-user heartbeat table (privacy-first, anonymized).
-- Stores only a SHA-256 hash of a client-generated session token and the
-- last-seen timestamp. No IP, location, or user-identifying data.

CREATE TABLE IF NOT EXISTS online_heartbeats (
    id SERIAL PRIMARY KEY,
    session_token_hash VARCHAR(64) NOT NULL UNIQUE,
    last_seen_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_online_heartbeats_last_seen
    ON online_heartbeats (last_seen_at);

CREATE INDEX IF NOT EXISTS idx_online_heartbeats_token_hash
    ON online_heartbeats (session_token_hash);
