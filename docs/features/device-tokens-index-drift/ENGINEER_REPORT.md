# Engineer Report

## Feature Slug

device-tokens-index-drift

## Feature Title

Fix device_tokens index drift - drop untracked composite index

## Goal

Drop the untracked composite index `idx_device_tokens_last_seen_user_id` that was created directly on production outside the migration pipeline. This restores alignment between the migration directory and the actual production schema, ensuring migration tracking integrity.

## Architect Tasks Completed

- [x] Task 1 — Created migration file with DROP INDEX statement
- [x] Task 2 — Wrote SQL to drop idx_device_tokens_last_seen_user_id with IF EXISTS guard
- [x] Task 3 — Ran Tier 1 pre-deploy verification queries
- [x] Task 4 — Applied migration via Supabase MCP tool
- [x] Task 5 — Ran Tier 2 post-deploy verification queries
- [x] Task 6 — Reported completion with verification results

## Files Created

- supabase/migrations/20260724035503_remove_untracked_device_tokens_composite_index.sql

## Files Modified

None

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings
Output: "No issues found! (ran in 5.1s)"

## Test Results

Not run (database-only change, no Flutter code modified)

## Verification

### Tier 1 Pre-Deploy Tests (all passed)

**PRE-DEPLOY TEST 1:** Verify composite index currently exists

- Result: 1 row returned
- indexname: idx_device_tokens_last_seen_user_id
- indexdef: CREATE INDEX idx_device_tokens_last_seen_user_id ON public.device_tokens USING btree (last_seen DESC, user_id)

**PRE-DEPLOY TEST 2:** Verify simple index (tracked) exists and will remain

- Result: 1 row returned
- indexname: idx_device_tokens_last_seen
- indexdef: CREATE INDEX idx_device_tokens_last_seen ON public.device_tokens USING btree (last_seen)

**PRE-DEPLOY TEST 3:** Count total indexes on device_tokens before drop

- Result: index_count = 5

### Tier 2 Post-Deploy Tests (all passed)

**POST-DEPLOY TEST 1:** Verify composite index was dropped

- Result: 0 rows returned (index successfully removed)

**POST-DEPLOY TEST 2:** Verify simple index still exists

- Result: 1 row returned
- indexname: idx_device_tokens_last_seen
- indexdef: CREATE INDEX idx_device_tokens_last_seen ON public.device_tokens USING btree (last_seen)

**POST-DEPLOY TEST 3:** Count total indexes on device_tokens after drop

- Result: index_count = 4 (reduced from 5)

**POST-DEPLOY TEST 4:** Verify all tracked indexes from migration 20260723192724 still exist

- Result: expected_index = idx_device_tokens_last_seen, status = EXISTS

**POST-DEPLOY TEST 5:** Verify migration is recorded in schema_migrations

- Result: version = 20260724035503 (migration successfully recorded)

## Deviations From Architect Plan

Minor deviation: The Supabase MCP apply_migration tool generated timestamp 20260724035503 (UTC) instead of using the local timestamp 20260723225434 (local time). The migration file was renamed from 20260723225434_remove_untracked_device_tokens_composite_index.sql to 20260724035503_remove_untracked_device_tokens_composite_index.sql to match the database version for consistency. This ensures the migration directory and schema_migrations table remain aligned.

## Blockers Encountered

None

## Ready For QA

Yes
