-- Drop untracked composite index created outside migration pipeline
-- Restores schema alignment with migration directory
-- Rationale: Composite (last_seen DESC, user_id) index doesn't address
-- the actual bottleneck (band_members LATERAL join per DB-3 finding).
-- The simple idx_device_tokens_last_seen (already tracked) is sufficient.
DROP INDEX IF EXISTS idx_device_tokens_last_seen_user_id;
