# Architect Plan

## Feature Slug

bug/device-tokens-index-drift

---

## Problem Summary

Untracked schema drift on `device_tokens` table. Supabase AI (a tool used outside this project's Architect/Engineer/QA pipeline) reported creating two indexes directly on the live production database: `idx_device_tokens_last_seen` on (last_seen DESC) and `idx_device_tokens_last_seen_user_id` on (last_seen DESC, user_id). This occurred after PR #75 (`feature/db-index-optimization`, migration `20260723192724_add_missing_indexes_remove_duplicates.sql`) had already shipped, which created `idx_device_tokens_last_seen` on (last_seen) without DESC ordering.

Direct database inspection via `pg_indexes` confirms:

- `idx_device_tokens_last_seen` exists on (last_seen) ascending — matches our migration
- `idx_device_tokens_last_seen_user_id` exists on (last_seen DESC, user_id) — untracked

The composite index is not tracked in `supabase/migrations/`, creating drift between the migration directory and the actual production schema. This violates the principle that migrations are the single source of truth for database schema.

**Process note:** This occurred because Supabase AI's schema changes were applied directly to production instead of being routed through the Architect → Engineer → QA pipeline. For Tony's awareness: future Supabase AI recommendations should be captured as Feature Inputs and go through the normal pipeline rather than being applied directly.

---

## Root Cause

**Confidence:** HIGH (confirmed via direct database query)

Supabase AI created `idx_device_tokens_last_seen_user_id` on (last_seen DESC, user_id) directly against the production database outside the migration pipeline. This index was never added to `supabase/migrations/`, so:

- Fresh database environments created via `supabase db push` will not have this index
- The migration directory no longer reflects the actual production state
- The composite index is untracked and unversioned

There was no name collision with the existing `idx_device_tokens_last_seen` because the ordering differs (ASC vs DESC).

---

## Reference Docs Consulted

- `docs/reference/notifications/NOTIFICATION_SYSTEM.md` — device_tokens schema and usage patterns
- `docs/features/full-stack-performance-audit/ARCHITECT_PLAN.md` — DB-3 finding on device_tokens × band_members query performance
- `docs/features/db-index-optimization/QA_REPORT.md` — PR #75 verification, confirmed idx_device_tokens_last_seen creation

---

## Existing System Analysis

### Current Database State (verified via pg_indexes on nekwjxvgbveheooyorjo)

Indexes on `device_tokens`:

1. `device_tokens_pkey` — PRIMARY KEY on (id)
2. `device_tokens_fcm_token_key` — UNIQUE INDEX on (fcm_token)
3. `idx_device_tokens_user_id` — INDEX on (user_id)
4. `idx_device_tokens_last_seen` — INDEX on (last_seen) [ascending, tracked in migration 20260723192724]
5. `idx_device_tokens_last_seen_user_id` — INDEX on (last_seen DESC, user_id) [untracked, created by Supabase AI]

### Tracked Migration State

Migration `20260723192724_add_missing_indexes_remove_duplicates.sql` (line 2) created:

```sql
CREATE INDEX idx_device_tokens_last_seen ON device_tokens(last_seen);
```

This matches what exists in production (ascending order).

### Performance Context from DB-3 Finding

The full-stack performance audit (DB-3) measured the `device_tokens` × `band_members` LATERAL query and found:

- `device_tokens` sequential scan: **0.3ms** of 19.4ms total query time
- `band_members` LATERAL nested loop: **~18ms** (>90% of total)
- **The band_members LATERAL join is the bottleneck, not the device_tokens scan**

A composite (last_seen, user_id) index does not address the dominant cost driver. The simple `idx_device_tokens_last_seen` we already created is sufficient for the device_tokens scan portion. The composite index adds write-time maintenance overhead without materially improving the query that drove the original investigation.

---

## Proposed Solution

Drop the untracked composite index `idx_device_tokens_last_seen_user_id` via a new migration. This restores alignment between the migration directory and production schema, eliminates redundant index maintenance overhead, and ensures fresh environments (created via `supabase db push`) match production.

**Why drop instead of keeping:**

- The composite index doesn't address the actual performance bottleneck (band_members LATERAL join per DB-3)
- The simple `idx_device_tokens_last_seen` we already have is sufficient for the 0.3ms device_tokens scan portion
- Maintaining both indexes adds write-time overhead on every INSERT/UPDATE to device_tokens
- The composite index provides minimal incremental value given the current query patterns

---

## Database Impact

**Migration:** Required

**New migration file:**

```sql
-- Drop untracked composite index created outside migration pipeline
-- Restores schema alignment with migration directory
-- Rationale: Composite (last_seen DESC, user_id) index doesn't address
-- the actual bottleneck (band_members LATERAL join per DB-3 finding).
-- The simple idx_device_tokens_last_seen (already tracked) is sufficient.
DROP INDEX IF EXISTS idx_device_tokens_last_seen_user_id;
```

**RLS policies:** Not affected  
**RPC functions:** Not affected  
**Triggers:** Not affected  
**Edge functions:** Not affected

---

## Flutter Architecture Changes

Not applicable — database-only change.

---

## Files to Create

| File                                                                                 | Justification                                         |
| ------------------------------------------------------------------------------------ | ----------------------------------------------------- |
| `supabase/migrations/<timestamp>_remove_untracked_device_tokens_composite_index.sql` | Drops the untracked index to restore schema alignment |

---

## Files to Modify

None — this is a purely additive migration with no client code or existing migration changes.

---

## Files Off-Limits

| File                                                                           | Reason                                                         |
| ------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| All files in `lib/`                                                            | No Flutter code changes required                               |
| All files in `supabase/functions/`                                             | No edge function changes required                              |
| `supabase/migrations/20260723192724_add_missing_indexes_remove_duplicates.sql` | Already shipped and applied; do not modify existing migrations |

---

## System Impact Map

| System                                 | Impact                                                                        |
| -------------------------------------- | ----------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                    |
| Rehearsals                             | unaffected                                                                    |
| Setlists / Catalog                     | unaffected                                                                    |
| Members / RBAC                         | unaffected                                                                    |
| Auth / Session                         | unaffected                                                                    |
| Routing                                | unaffected                                                                    |
| Notifications                          | unaffected (device_tokens writes continue to use idx_device_tokens_last_seen) |
| Platform (iOS / Android / Web / macOS) | unaffected                                                                    |

---

## Regression Risk

**Level:** LOW

**Rationale:**

- Dropping an index is non-breaking — queries that could use it will fall back to the simple `idx_device_tokens_last_seen` or sequential scan
- The composite index was created recently and is not referenced by any application queries (DB-3's query originates from external tooling, not this codebase)
- No RLS, RPC, trigger, or application code changes
- The simple `idx_device_tokens_last_seen` remains in place to cover the 48-hour freshness query pattern
- Standard Postgres transaction semantics ensure atomic migration application

---

## Engineer Task Breakdown

1. **Create migration file** with timestamp format `<YYYYMMDDHHmmss>_remove_untracked_device_tokens_composite_index.sql`
2. **Write SQL** to drop `idx_device_tokens_last_seen_user_id` with `IF EXISTS` guard
3. **Run Tier 1 pre-deploy verification** (see Verification Plan below)
4. **Apply migration** via `npx supabase db push --project-ref nekwjxvgbveheooyorjo`
5. **Run Tier 2 post-deploy verification** (see Verification Plan below)
6. **Report completion** with verification results in `ENGINEER_REPORT.md`

---

## Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

These tests verify the current state before changes and confirm the index exists.

```sql
-- PRE-DEPLOY TEST 1: Verify composite index currently exists
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'device_tokens'
  AND indexname = 'idx_device_tokens_last_seen_user_id';
-- Expected: 1 row with indexdef showing (last_seen DESC, user_id)

-- PRE-DEPLOY TEST 2: Verify simple index (tracked) exists and will remain
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'device_tokens'
  AND indexname = 'idx_device_tokens_last_seen';
-- Expected: 1 row with indexdef showing (last_seen) without DESC

-- PRE-DEPLOY TEST 3: Count total indexes on device_tokens before drop
SELECT count(*) as index_count
FROM pg_indexes
WHERE tablename = 'device_tokens';
-- Expected: 5 (pkey, fcm_token_key, user_id, last_seen, last_seen_user_id)
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

These tests verify the migration succeeded and schema is now aligned.

```sql
-- POST-DEPLOY TEST 1: Verify composite index was dropped
SELECT indexname
FROM pg_indexes
WHERE tablename = 'device_tokens'
  AND indexname = 'idx_device_tokens_last_seen_user_id';
-- Expected: 0 rows (index no longer exists)

-- POST-DEPLOY TEST 2: Verify simple index still exists
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'device_tokens'
  AND indexname = 'idx_device_tokens_last_seen';
-- Expected: 1 row with indexdef showing (last_seen) without DESC

-- POST-DEPLOY TEST 3: Count total indexes on device_tokens after drop
SELECT count(*) as index_count
FROM pg_indexes
WHERE tablename = 'device_tokens';
-- Expected: 4 (pkey, fcm_token_key, user_id, last_seen)

-- POST-DEPLOY TEST 4: Verify all tracked indexes from migration 20260723192724 still exist
SELECT
  'idx_device_tokens_last_seen' as expected_index,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE tablename = 'device_tokens'
      AND indexname = 'idx_device_tokens_last_seen'
  ) THEN 'EXISTS' ELSE 'MISSING' END as status;
-- Expected: status = 'EXISTS'

-- POST-DEPLOY TEST 5: Verify migration is recorded in schema_migrations
SELECT version
FROM supabase_migrations.schema_migrations
WHERE version LIKE '%_remove_untracked_device_tokens_composite_index'
ORDER BY version DESC
LIMIT 1;
-- Expected: 1 row with the new migration version
```

---

## QA Regression Areas

### Primary Verification

- Database schema alignment: `pg_indexes` output matches migration directory state
- Index count on device_tokens: exactly 4 indexes remain (pkey, fcm_token_key, user_id, last_seen)
- No application errors after deployment (device_tokens INSERT/UPDATE operations succeed)

### Notification System

- Device token registration on login/app launch succeeds
- Device token cleanup on logout succeeds
- Push notification delivery continues to work (notifications reach devices)
- No performance regression in notification delivery (Edge Function logs show no new errors)

### No Impact Expected

- Gig/rehearsal/block-out creation (notifications are a separate concern from index drop)
- Settings → Notifications preference changes
- All other device_tokens table operations (the simple index covers existing query patterns)

---

## Rollout / Migration Strategy

Standard single-migration deploy:

1. **Pre-deploy:** Run Tier 1 verification tests to confirm current state
2. **Deploy:** Apply migration via `supabase db push` to production project `nekwjxvgbveheooyorjo`
3. **Post-deploy:** Run Tier 2 verification tests to confirm index dropped successfully
4. **Monitor:** Check Edge Function logs (`supabase functions logs send-push`) for 24 hours to confirm no notification delivery regressions

**Rollback plan:** If needed, the index can be recreated with:

```sql
CREATE INDEX idx_device_tokens_last_seen_user_id
  ON device_tokens(last_seen DESC, user_id);
```

However, rollback should only be necessary if unexpected query patterns emerge that genuinely benefit from the composite index (not anticipated based on DB-3 analysis).

---

## Out of Scope

- Addressing the actual DB-3 performance bottleneck (band_members LATERAL join) — that requires a separate feature to optimize the query shape, not an index change
- Retroactively tracking the composite index in migrations — we're dropping it instead because it doesn't materially help performance
- Creating process automation to prevent future direct schema changes — this is a one-time reconciliation; the process note in Problem Summary addresses awareness for future work
- Investigating the external query that uses device_tokens × band_members LATERAL — DB-3 notes it originates from external reporting tooling, not this codebase
