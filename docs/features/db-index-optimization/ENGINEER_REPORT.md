# Engineer Report

## Feature Slug

db-index-optimization

## Feature Title

Database Index Optimization — Add Missing Indexes and Remove Duplicates

## Goal

Bundle three independent, low-risk database index optimizations into a single migration: add covering index on device_tokens.last_seen for 48-hour freshness queries, add 10 missing FK column indexes to optimize joins and FK constraint checks, and remove 2 pairs of duplicate indexes to eliminate redundant write-time overhead.

## Architect Tasks Completed

- [x] Task 1 — Create migration file with timestamp: 20260723192724_add_missing_indexes_remove_duplicates.sql
- [x] Task 2 — Copy exact SQL from Section 7 (11 CREATE INDEX + 2 DROP statements)
- [x] Task 3 — Run Tier 1 pre-deploy verification (discovered FK constraint dependency on band_members_band_id_user_id_key)
- [x] Task 4 — Apply migration via supabase db push
- [x] Task 5 — Run Tier 2 post-deploy verification (all 13 index operations succeeded)
- [x] Task 6 — Report completion with verification results

## Files Created

- supabase/migrations/20260723192724_add_missing_indexes_remove_duplicates.sql

## Files Modified

None — migration-only change

## Analyzer Results

Command: `flutter analyze`
Result: No issues found! (ran in 2.9s)

## Test Results

Not run (no Dart code modified; database-only change)

## Verification

### Tier 1 Pre-Deploy Verification (before migration applied)

**PRE-DEPLOY TEST 1**: Verify duplicate indexes exist and are truly identical

```
Result: 4 rows returned — confirmed both index pairs exist and are identical
- band_members: band_members_band_id_user_id_key, band_members_band_user_unique
- gig_responses: gig_responses_gig_user_date_unique, gig_responses_unique_user_gig_date
```

**PRE-DEPLOY TEST 2**: Verify no FK constraints reference the specific index names we plan to drop

```
Result: 1 row returned
- band_members_band_id_user_id_key is referenced by constraint band_members_band_id_user_id_key

Action taken: Changed migration to drop band_members_band_user_unique (the OTHER index) instead.
Also discovered band_members_band_user_unique has its own constraint, so changed migration to:
  ALTER TABLE band_members DROP CONSTRAINT IF EXISTS band_members_band_user_unique;
```

**PRE-DEPLOY TEST 3**: Confirm none of the 10 FK columns already have indexes

```
Result: 4 rows returned, but all are UNIQUE constraint indexes, not plain FK indexes
- gig_responses: gig_responses_unique_user_gig_date, gig_responses_gig_user_date_unique (duplicates we're handling)
- band_calendar_subscriptions: band_calendar_subscriptions_user_id_band_id_key (different columns)
- rehearsal_responses: rehearsal_responses_rehearsal_user_date_unique (multi-column unique, not FK index)

Confirmed: None of the 10 FK columns have plain indexes — safe to proceed.
```

**PRE-DEPLOY TEST 4**: Confirm device_tokens.last_seen has no index

```
Result: 0 rows returned — confirmed no index exists
```

### Tier 2 Post-Deploy Verification (after migration applied)

**POST-DEPLOY TEST 1**: Verify device_tokens.last_seen index was created

```
Result: 1 row returned
indexname: idx_device_tokens_last_seen
indexdef: CREATE INDEX idx_device_tokens_last_seen ON public.device_tokens USING btree (last_seen)
✓ PASS
```

**POST-DEPLOY TEST 2**: Verify all 10 FK indexes were created

```
Result: 10 rows returned
✓ idx_band_calendar_subscriptions_band_id
✓ idx_band_invitations_invited_by
✓ idx_bands_created_by
✓ idx_bands_last_used_print_template_id
✓ idx_gig_responses_user_id
✓ idx_gigs_created_by
✓ idx_notifications_actor_user_id
✓ idx_rehearsal_responses_rehearsal_date_id
✓ idx_rehearsal_responses_user_id
✓ idx_setlists_created_by
✓ PASS
```

**POST-DEPLOY TEST 3**: Verify duplicate indexes were dropped

```
Result: 2 rows returned (only the kept indexes remain)
✓ band_members: band_members_band_id_user_id_key (kept)
✓ gig_responses: gig_responses_unique_user_gig_date (kept)
✓ PASS
```

**POST-DEPLOY TEST 4**: Verify query plan uses new device_tokens.last_seen index

```
Result: Index Scan using idx_device_tokens_last_seen on device_tokens
✓ PASS
```

**POST-DEPLOY TEST 5**: Verify query plan uses new gig_responses.user_id index

```
Result: Index Scan using idx_gig_responses_user_id on gig_responses
✓ PASS
```

**POST-DEPLOY TEST 6**: Production data integrity check (no duplicate index pairs remain)

```
Result: 0 rows returned — no duplicate index pairs remain
✓ PASS
```

## Deviations From Architect Plan

One deviation required during implementation:

**Deviation 1**: Changed duplicate index removal strategy for band_members table

- **Original plan**: `DROP INDEX IF EXISTS band_members_band_id_user_id_key;`
- **Actual implementation**: `ALTER TABLE band_members DROP CONSTRAINT IF EXISTS band_members_band_user_unique;`
- **Reason**: Tier 1 PRE-DEPLOY TEST 2 revealed that BOTH duplicate indexes are backed by UNIQUE constraints (not just plain indexes). Both `band_members_band_id_user_id_key` and `band_members_band_user_unique` have their own constraint objects. Attempting to drop the index directly failed with error "cannot drop index because constraint requires it". The correct approach is to drop the constraint, which automatically drops its associated index.
- **Justification**: This is the safe and correct way to remove duplicate UNIQUE constraints in PostgreSQL. The end result is identical to the Architect's intent (one duplicate removed, one kept), and follows PostgreSQL best practices.

## Blockers Encountered

**Blocker 1**: Temporary Supabase API 502 error during initial migration push attempt

- **Resolution**: Waited 60 seconds and retried per Cloudflare error guidance. Second attempt succeeded.
- **Impact**: None — migration applied successfully on retry.

## Ready For QA

Yes

All 13 index operations (1 device_tokens index + 10 FK indexes + 2 duplicate index removals) completed successfully. All Tier 1 and Tier 2 verification queries passed. Flutter analyzer passed with 0 errors and 0 warnings. No client-side code modified (database-only change).
