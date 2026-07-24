# ARCHITECT_PLAN.md

## 1. Feature Slug

`feature/db-index-optimization`

---

## 2. Problem Summary

The full-stack performance audit (docs/features/full-stack-performance-audit/ARCHITECT_PLAN.md) identified three independent, low-risk database index issues that can be bundled into a single migration:

- **DB-3:** `device_tokens.last_seen` has no covering index despite being used in a 48-hour freshness filter query. Table has grown from 132 rows to 604 rows (4.6× in 3 months), confirming this as a scaling concern.
- **DB-4:** 10 foreign key columns across various tables have no covering indexes, forcing sequential scans on join/delete paths and locking larger tables than necessary during writes.
- **DB-6:** Two pairs of duplicate indexes exist (`band_members`, `gig_responses`), maintained redundantly on every write for zero query-planning benefit.

All three are additive/subtractive index-only changes with no query logic or RLS changes.

---

## 3. Root Cause

**Confidence: HIGH** — all three findings confirmed via `get_advisors(type=performance)` and validated against live project `nekwjxvgbveheooyorjo` during the performance audit.

- **DB-3:** `device_tokens.last_seen` filter (≥48 hours freshness) scans all 604 rows. While currently only 0.3ms, the table's 4.6× growth rate over 3 months confirms this will become a bottleneck.
- **DB-4:** Standard missing FK index pattern — forces full-table scans on the referencing table whenever referenced rows are deleted/updated (e.g., `delete_band` must scan all of `band_calendar_subscriptions` to check for orphans on `band_id` FK).
- **DB-6:** Duplicate indexes identified by advisor — two identical unique indexes per affected table, both maintained on every INSERT/UPDATE.

---

## 4. Reference Docs Consulted

- `docs/features/full-stack-performance-audit/ARCHITECT_PLAN.md` (findings DB-3, DB-4, DB-6)
- `docs/agents/PROJECT_CONTEXT.md` (migration naming convention, database tables)
- `docs/agents/GUARDRAILS.md` (Supabase safety rules)
- `supabase/migrations/20260109_notifications.sql` (device_tokens table schema)

Notification domain reference docs (docs/reference/notifications/) were not loaded — this is database optimization only, no notification behavior changes.

---

## 5. Existing System Analysis

### Database Schema

All three affected areas are production tables with RLS enabled:

- **device_tokens:** 604 rows, 3 existing indexes (`device_tokens_pkey`, `device_tokens_fcm_token_key`, `idx_device_tokens_user_id`). No index on `last_seen`.
- **10 unindexed FK columns:** Advisor flagged these as INFO-level lints. Each column is a valid FK constraint but lacks a covering index:
  - `band_calendar_subscriptions.band_id`
  - `band_invitations.invited_by`
  - `bands.created_by`
  - `bands.last_used_print_template_id`
  - `gig_responses.user_id`
  - `gigs.created_by`
  - `notifications.actor_user_id`
  - `rehearsal_responses.rehearsal_date_id`
  - `rehearsal_responses.user_id`
  - `setlists.created_by`
- **Duplicate indexes:**
  - `band_members`: `band_members_band_id_user_id_key` and `band_members_band_user_unique` are identical.
  - `gig_responses`: `gig_responses_gig_user_date_unique` and `gig_responses_unique_user_gig_date` are identical.

### Current Query Impact

Per the audit's EXPLAIN ANALYZE measurements:

- Device tokens scan: 0.3ms now, but will grow linearly with table size (already 4.6× in 3 months).
- FK scans: Not directly measured, but standard pattern — worst during `delete_band` or `remove_band_member` operations where FK checks can lock entire referencing tables.
- Duplicate indexes: Pure write-time overhead — every `INSERT`/`UPDATE` maintains both indexes redundantly.

---

## 6. Proposed Solution

Create a single migration containing three independent index operations:

1. **Add `last_seen` index:** `CREATE INDEX` on `device_tokens.last_seen` to accelerate the 48-hour freshness filter.
2. **Add FK indexes:** `CREATE INDEX` on each of the 10 unindexed FK columns.
3. **Remove duplicate indexes:** `DROP INDEX` on one of each duplicate pair, after verifying via `pg_depend`/`pg_constraint` that no FK or application code references the specific index name being removed.

Standard `CREATE INDEX` (not `CONCURRENTLY`) is used for all 11 index additions. Rationale: `CREATE INDEX CONCURRENTLY` cannot execute inside a transaction block, which creates risk of partial migration application and potentially-`INVALID` indexes if `supabase db push` runs migrations transactionally. At current table sizes (largest is `device_tokens` at 604 rows), standard index creation completes in well under a second with brief locks that have no meaningful production impact.

---

## 7. Database Impact

**Affected:** Indexes only. No schema changes, no RLS policy changes, no RPC changes, no query logic changes.

### Exact SQL Statements

#### DB-3: device_tokens.last_seen index

```sql
-- Add index on device_tokens.last_seen for 48-hour freshness queries
CREATE INDEX idx_device_tokens_last_seen ON device_tokens(last_seen);
```

**Rationale:** The `last_seen >= now() - interval '48 hours'` filter is used in reporting queries. While currently fast (0.3ms scan over 604 rows), the table's 4.6× growth in 3 months warrants a covering index now. Standard `CREATE INDEX` (not `CONCURRENTLY`) is safe at this table size (604 rows) — index build completes in well under a second.

---

#### DB-4: Unindexed foreign key columns (10 indexes)

```sql
-- Add indexes on unindexed FK columns to optimize joins and FK constraint checks during deletes

-- 1. band_calendar_subscriptions.band_id
CREATE INDEX idx_band_calendar_subscriptions_band_id
  ON band_calendar_subscriptions(band_id);

-- 2. band_invitations.invited_by
CREATE INDEX idx_band_invitations_invited_by
  ON band_invitations(invited_by);

-- 3. bands.created_by
CREATE INDEX idx_bands_created_by
  ON bands(created_by);

-- 4. bands.last_used_print_template_id
CREATE INDEX idx_bands_last_used_print_template_id
  ON bands(last_used_print_template_id);

-- 5. gig_responses.user_id
CREATE INDEX idx_gig_responses_user_id
  ON gig_responses(user_id);

-- 6. gigs.created_by
CREATE INDEX idx_gigs_created_by
  ON gigs(created_by);

-- 7. notifications.actor_user_id
CREATE INDEX idx_notifications_actor_user_id
  ON notifications(actor_user_id);

-- 8. rehearsal_responses.rehearsal_date_id
CREATE INDEX idx_rehearsal_responses_rehearsal_date_id
  ON rehearsal_responses(rehearsal_date_id);

-- 9. rehearsal_responses.user_id
CREATE INDEX idx_rehearsal_responses_user_id
  ON rehearsal_responses(user_id);

-- 10. setlists.created_by
CREATE INDEX idx_setlists_created_by
  ON setlists(created_by);
```

**Rationale:** FK columns without indexes force sequential scans on the referencing table during `JOIN`/`WHERE` operations and during FK constraint validation on `DELETE`/`UPDATE` of the referenced row. This is most problematic during operations like `delete_band` or `remove_band_member`, which must scan all referencing tables to check for orphans. Standard `CREATE INDEX` is used (not `CONCURRENTLY`) to avoid transaction-block restrictions and simplify migration execution — all affected tables are small (hundreds to low thousands of rows), so index builds complete in under a second each with negligible lock impact.

---

#### DB-6: Remove duplicate indexes

```sql
-- Remove duplicate indexes after verifying dependencies

-- Before dropping, verify these indexes are not referenced by constraints or application code:
-- SELECT conname, conindid::regclass
-- FROM pg_constraint
-- WHERE conindid IN (
--   'band_members_band_id_user_id_key'::regclass,
--   'gig_responses_gig_user_date_unique'::regclass
-- );

-- Drop one index from each identical pair (keep the more descriptive name)
DROP INDEX IF EXISTS band_members_band_id_user_id_key;
DROP INDEX IF EXISTS gig_responses_gig_user_date_unique;
```

**Rationale:** Advisor confirmed these are identical unique indexes. Both indexes in each pair cover the same columns in the same order. Keeping one per table eliminates redundant maintenance overhead on every `INSERT`/`UPDATE` with zero query-planning cost.

**Pre-drop verification required:** Engineer must verify via `pg_depend`/`pg_constraint` that the specific index name being dropped is not referenced by a FK constraint definition or any application code. If either index in a pair is referenced, drop the _other_ one instead.

---

### Migration File

**Path:** `supabase/migrations/20260723HHMMSS_add_missing_indexes_remove_duplicates.sql`  
(Replace `HHMMSS` with actual timestamp at creation time, per PROJECT_CONTEXT migration naming convention.)

**Migration policy:** Required  
**Edge function deploy:** Not required  
**RLS impact:** None  
**RPC impact:** None

---

## 8. Flutter Architecture Changes

Not applicable — database optimization only, no client-side changes.

---

## 9. Files to Create

- `supabase/migrations/20260723HHMMSS_add_missing_indexes_remove_duplicates.sql` — single migration containing all 13 index operations (1 device_tokens index + 10 FK indexes + 2 duplicate index drops)

---

## 10. Files to Modify

None — this is a migration-only change.

---

## 11. Files Off-Limits

All files are off-limits except the single new migration file listed in Section 9.

---

## 12. System Impact Map

| System                           | Impact     |
| -------------------------------- | ---------- |
| Gigs                             | affected   |
| Rehearsals                       | affected   |
| Setlists / Catalog               | affected   |
| Members / RBAC                   | affected   |
| Auth / Session                   | unaffected |
| Routing                          | unaffected |
| Notifications                    | affected   |
| Platform (iOS/Android/Web/macOS) | unaffected |

**Impact rationale:**

- Gigs: `gigs.created_by`, `gig_responses.user_id` indexes added; `gig_responses` duplicate index removed.
- Rehearsals: `rehearsal_responses.rehearsal_date_id`, `rehearsal_responses.user_id` indexes added.
- Setlists: `setlists.created_by` index added.
- Members: `band_invitations.invited_by` index added; `band_members` duplicate index removed.
- Notifications: `device_tokens.last_seen`, `notifications.actor_user_id` indexes added.

All impacts are **query-plan optimizations only** — no behavior changes, no client-side impact.

---

## 13. Regression Risk

**Level: LOW**

**Rationale:**

- Additive indexes cannot break existing queries — they only make them faster or leave them unchanged.
- Standard `CREATE INDEX` will acquire brief locks during index creation (sub-second at current table sizes: largest is 604 rows), but these complete so quickly that production impact is negligible.
- Duplicate index removal is safe as long as the pre-drop verification (Section 7) confirms no FK or application code references the specific index name being dropped. The audit confirmed these are identical indexes — Postgres will continue using the remaining index transparently.
- No RLS policies, RPCs, or application code are touched.

**Risk mitigation:**

- Pre-drop verification query (Section 7, DB-6) must be run in Tier 1 testing before `supabase db push`.
- Tier 2 testing will confirm all 13 index operations succeeded and query plans use the new indexes where expected.

---

## 14. Engineer Task Breakdown

1. **Create migration file** with timestamp: `supabase/migrations/20260723HHMMSS_add_missing_indexes_remove_duplicates.sql`
2. **Copy exact SQL** from Section 7 into the migration file, preserving all three sections (DB-3, DB-4, DB-6) with their comments.
3. **Run Tier 1 pre-deploy verification** (Section 15) — specifically the duplicate index dependency check for DB-6.
4. **Apply migration:** `supabase db push` (this will run all 11 `CREATE INDEX` and 2 `DROP INDEX` operations in a single transaction).
5. **Run Tier 2 post-deploy verification** (Section 15) — confirm all 13 indexes were created/dropped successfully and query plans use the new indexes.
6. **Report completion** with verification results.

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

**Tier 1 tests verify that the indexes we're about to drop are safe to drop. All tests run against the current schema with zero changes applied.**

```sql
-- PRE-DEPLOY TEST 1: Verify duplicate indexes exist and are truly identical
-- Expected: 2 rows returned showing both indexes in each pair cover the same columns

SELECT
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE indexname IN (
  'band_members_band_id_user_id_key',
  'band_members_band_user_unique',
  'gig_responses_gig_user_date_unique',
  'gig_responses_unique_user_gig_date'
)
ORDER BY tablename, indexname;
```

```sql
-- PRE-DEPLOY TEST 2: Verify no FK constraints reference the specific index names we plan to drop
-- Expected: 0 rows returned (if any rows are returned, drop the OTHER index in the pair instead)

SELECT
  conname AS constraint_name,
  conrelid::regclass AS table_name,
  conindid::regclass AS index_name
FROM pg_constraint
WHERE conindid IN (
  'band_members_band_id_user_id_key'::regclass,
  'gig_responses_gig_user_date_unique'::regclass
);
```

```sql
-- PRE-DEPLOY TEST 3: Confirm none of the 10 FK columns already have indexes
-- Expected: 0 rows returned (if any are returned, remove that column from the migration)

SELECT
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND (
    (tablename = 'band_calendar_subscriptions' AND indexdef LIKE '%band_id%')
    OR (tablename = 'band_invitations' AND indexdef LIKE '%invited_by%')
    OR (tablename = 'bands' AND indexdef LIKE '%created_by%')
    OR (tablename = 'bands' AND indexdef LIKE '%last_used_print_template_id%')
    OR (tablename = 'gig_responses' AND indexdef LIKE '%user_id%')
    OR (tablename = 'gigs' AND indexdef LIKE '%created_by%')
    OR (tablename = 'notifications' AND indexdef LIKE '%actor_user_id%')
    OR (tablename = 'rehearsal_responses' AND indexdef LIKE '%rehearsal_date_id%')
    OR (tablename = 'rehearsal_responses' AND indexdef LIKE '%user_id%')
    OR (tablename = 'setlists' AND indexdef LIKE '%created_by%')
  )
  -- Exclude existing unique/PK indexes that happen to include these columns
  AND indexname NOT LIKE '%_pkey'
  AND indexname NOT IN (
    'band_members_band_id_user_id_key',
    'band_members_band_user_unique'
  );
```

```sql
-- PRE-DEPLOY TEST 4: Confirm device_tokens.last_seen has no index
-- Expected: 0 rows returned

SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'device_tokens'
  AND indexdef LIKE '%last_seen%';
```

---

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

**Tier 2 tests verify that all 13 index operations succeeded and query plans now use the new indexes.**

```sql
-- POST-DEPLOY TEST 1: Verify device_tokens.last_seen index was created
-- Expected: 1 row returned showing idx_device_tokens_last_seen

SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'device_tokens'
  AND indexname = 'idx_device_tokens_last_seen';
```

```sql
-- POST-DEPLOY TEST 2: Verify all 10 FK indexes were created
-- Expected: 10 rows returned, one per FK column

SELECT tablename, indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'idx_band_calendar_subscriptions_band_id',
    'idx_band_invitations_invited_by',
    'idx_bands_created_by',
    'idx_bands_last_used_print_template_id',
    'idx_gig_responses_user_id',
    'idx_gigs_created_by',
    'idx_notifications_actor_user_id',
    'idx_rehearsal_responses_rehearsal_date_id',
    'idx_rehearsal_responses_user_id',
    'idx_setlists_created_by'
  )
ORDER BY tablename, indexname;
```

```sql
-- POST-DEPLOY TEST 3: Verify duplicate indexes were dropped
-- Expected: 2 rows returned (only the kept indexes: band_members_band_user_unique, gig_responses_unique_user_gig_date)

SELECT tablename, indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND (
    (tablename = 'band_members' AND indexname IN ('band_members_band_id_user_id_key', 'band_members_band_user_unique'))
    OR (tablename = 'gig_responses' AND indexname IN ('gig_responses_gig_user_date_unique', 'gig_responses_unique_user_gig_date'))
  )
ORDER BY tablename, indexname;
```

```sql
-- POST-DEPLOY TEST 4: Verify query plan uses new device_tokens.last_seen index
-- Expected: Index Scan (or Bitmap Index Scan) on idx_device_tokens_last_seen in the plan

EXPLAIN
SELECT * FROM device_tokens
WHERE last_seen >= now() - interval '48 hours';
```

```sql
-- POST-DEPLOY TEST 5: Verify query plan uses new gig_responses.user_id index
-- Expected: Index Scan (or Bitmap Index Scan) on idx_gig_responses_user_id

EXPLAIN
SELECT * FROM gig_responses
WHERE user_id = auth.uid();
```

```sql
-- POST-DEPLOY TEST 6: Production data integrity check
-- Confirm no duplicate index pairs remain (should return 0 rows)

SELECT
  schemaname,
  tablename,
  array_agg(indexname ORDER BY indexname) AS duplicate_indexes,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
GROUP BY schemaname, tablename, indexdef
HAVING count(*) > 1;
```

---

## 16. QA Regression Areas

**QA must verify that all affected operations continue to work correctly after the migration. Since this is an index-only optimization with no behavior changes, regression risk is low, but the following scenarios exercise the indexed paths:**

### Primary Verification

1. **Device token freshness queries** — any operation that filters device tokens by `last_seen` (likely admin/reporting dashboards).
2. **Band deletion** — exercises FK checks on `band_calendar_subscriptions.band_id`, `gigs.created_by`, `setlists.created_by` (must complete without hanging or timeout).
3. **Member removal** — exercises FK checks on `band_invitations.invited_by`, `gig_responses.user_id`, `rehearsal_responses.user_id`.

### Secondary Verification

4. **Gig/rehearsal RSVP updates** — write path for `gig_responses`, `rehearsal_responses` (must complete normally; no unique constraint violations from the duplicate index removal).
5. **Band member management** — write path for `band_members` (must complete normally; no unique constraint violations).
6. **Notification delivery** — exercises `notifications.actor_user_id` index on actor-based queries.
7. **Setlist/gig creation** — exercises `setlists.created_by`, `gigs.created_by` indexes.

**Expected outcome:** All operations complete with identical behavior and results as before the migration. No errors, no constraint violations, no performance regressions (query times should be equal or faster, never slower).

---

## 17. Rollout / Migration Strategy

- **Single migration file** containing all 13 index operations — safe because all three DB findings are independent and equally low-risk.
- **Brief locks during index creation** — standard `CREATE INDEX` acquires locks, but all affected tables are small (largest is 604 rows), so index builds complete in under a second each. Total lock time across all 11 index creations is negligible.
- **No rollback migration needed** — if any index creation fails, the entire migration transaction will roll back (standard Postgres behavior). Duplicate index drops are trivially reversible by recreating the dropped index if needed.
- **Deploy timing:** Can be deployed during business hours — brief locks on small tables have no meaningful user impact.

---

## 18. Out of Scope

- **DB-7 (unused indexes):** Explicitly excluded per feature input — requires 30-60 day observation window before acting.
- **DB-1, DB-2 (RLS policy optimization):** Separate findings, require their own migrations.
- **Query logic changes:** This is index-only optimization — no changes to queries, RPCs, or application code.
- **Client-side changes:** No Flutter, web, or native app changes.
- **New indexes beyond the 13 specified:** Only the indexes identified by the performance audit advisor are in scope.
