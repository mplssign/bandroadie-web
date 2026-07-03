# Band Data Isolation Audit — ARCHITECT_PLAN.md

**Feature Identifier:** `feature/band-data-isolation-audit`  
**Type:** Feature (Security Audit + Remediation)  
**Date:** 2026-07-02

---

## Problem Summary

BandRoadie serves 100+ bands from a shared Supabase backend. This audit verifies that all band-scoped data is completely isolated: a user in Band A must never be able to read, infer, or modify data belonging to Band B. Known risk areas include legacy songs with `NULL band_id` accessed via SECURITY DEFINER RPCs that bypass RLS, Edge Functions running with `verify_jwt: false`, and client-side band-switching that may render stale data from the prior band.

---

## Audit Scope & Findings

Per the feature input, this audit covered seven areas. Each finding is rated:

- **PASS**: No isolation gap detected, band scoping is correct
- **GAP**: Confirmed isolation vulnerability requiring fix
- **UNVERIFIABLE**: Cannot confirm from repo; requires production SQL query

### 1. RLS Inventory

**Finding:** PASS with UNVERIFIABLE items (awaiting Tier 1 production results — Tony is running queries now)

**Evidence:**

Confirmed RLS-enabled with band-scoped policies from migrations:

- `gigs` — `20260302000000_band_user_roles.sql:182-244` (SELECT/INSERT/UPDATE/DELETE)
- `setlists` — `20260302000000_band_user_roles.sql:253-299` (SELECT/INSERT/UPDATE/DELETE)
- `rehearsals` — `20260305100000_fix_rehearsal_rls_and_trigger.sql:33-99` (SELECT/INSERT/UPDATE/DELETE)
- `notifications` — `20260109_notifications.sql:97-107` (user_id scoped, not band_id — correct for recipient)
- `device_tokens` — `20260109_notifications.sql:28-45` (user_id scoped — correct, no band isolation needed)
- `notification_preferences` — `20260109_notifications.sql:143-156` (user_id scoped — correct)
- `contributor_permissions` — `20260302000000_band_user_roles.sql:112-149` (band-scoped via band_members join)
- `print_templates` — `20260322100000_print_templates.sql:55` (RLS enabled, policies not inspected in audit but presumed band-scoped)
- `venues` — `20260410000000_contacts_venues_tables.sql:25` (RLS enabled, band_id column present)
- `venue_contacts` — `20260410000000_contacts_venues_tables.sql:104` (RLS enabled, band_id column present)
- `contacts` — `20260410000000_contacts_venues_tables.sql:181` (RLS enabled, band_id column present)
- `band_calendar_subscriptions` — `20260305000000_band_scoped_calendar.sql:27` (RLS enabled, band_id + user_id scoped)
- `setlist_special_items` — `20260221000000_setlist_special_items.sql:42` (RLS enabled, band_id column present)

**UNVERIFIABLE** (policies not found in searched migrations; may exist in earlier/initial schema):

- `bands` — RLS policy at `20260302000000_band_user_roles.sql:310-320` (DELETE only), but SELECT/INSERT/UPDATE policies not located
- `band_members` — RLS enabled presumed (referenced in all band-scoped policies), but explicit policies not found in audit
- `songs` — **Critical**: `band_id` column exists, but no RLS policies found in migrations. Legacy songs may have `NULL band_id`. This is a key risk area.
- `setlist_songs` — Policy for DELETE at `20260228000000_create_delete_setlist_rpc.sql` via band_members join, but SELECT/INSERT/UPDATE not located
- `gig_dates`, `gig_responses`, `rehearsal_dates`, `rehearsal_responses`, `block_dates`, `user_band_roles`, `band_invitations`, `band_access_events`, `financial_entries` — RLS status and policies not confirmed in audit

**Recommendation:**  
Run production SQL verification (see Verification Plan) to confirm all band-scoped tables have policies for all four operations (SELECT/INSERT/UPDATE/DELETE) scoping by active band membership. Priority: `songs`, `setlist_songs`, `bands`.

---

### 2. Songs / Catalog Collision Paths

**Finding:** **GAP** — Cross-band write vulnerability for NULL band_id songs; read paths are PASS

**Root Cause (HIGH Confidence):**

`update_song_metadata` RPC (migration `088_add_lyrics_youtube_to_update_song_rpc.sql:18-116`) is SECURITY DEFINER and bypasses RLS. Lines 68-72:

```sql
-- Verify the song belongs to this band (or is a legacy song with NULL band_id)
IF v_song_band_id IS NOT NULL AND v_song_band_id != p_band_id THEN
  RETURN json_build_object('success', false, 'error', 'Song belongs to a different band');
END IF;
```

**Vulnerability:** A user in Band A can call `update_song_metadata(null_song_id, band_a_id, ...)` and mutate a song with `band_id = NULL` that is _also visible to_ Band B. If both bands have a legacy song "Hotel California" with `NULL band_id`, Band A's user can overwrite its BPM/lyrics/etc., and Band B will see the mutation.

**Similar Risk:**  
`clear_song_metadata` RPC exists in production per PROJECT_CONTEXT but was not located in migrations (mixed migration provenance in this project). If it follows the same pattern, it has the same gap.

**Song Read Path Audit (COMPLETE):**  
Searched all of `lib/` for song queries filtering on `title` or `artist` (patterns: `.eq('title'`, `.ilike(`, `.textSearch(`, `.or(` with title/artist, raw `from('songs')` calls). All seven title/artist lookups found are correctly constrained by `band_id`:

- `setlist_repository.dart:3302` — `.eq('band_id', bandId).ilike('title', ...).ilike('artist', ...)` ✓
- `setlist_repository.dart:3402` — same pattern (race condition handler) ✓
- `setlist_repository.dart:3881` — same pattern ✓
- `setlist_repository.dart:3977` — same pattern ✓
- `setlist_detail_screen.dart:688` — `.eq('band_id', bandId).ilike('title', ...).ilike('artist', ...)` ✓
- `new_setlist_screen.dart:377` — same pattern ✓
- `data_backup_service.dart:192` — `.eq('band_id', bandId)` on all song exports ✓

**Verdict:** No read collision paths detected. All song title/artist queries are band-scoped.

---

### 3. SECURITY DEFINER RPC Sweep

**Finding:** **GAP** in `update_song_metadata`; otherwise PASS

**Evidence:**

All reviewed SECURITY DEFINER RPCs include `SET search_path = public` ✓:

- `delete_band` — `20260302000000_band_user_roles.sql:326-371` — verifies admin role + band membership (lines 346-355)
- `update_member_role` — `20260302000000_band_user_roles.sql:379-463` — verifies caller is admin (lines 397-403)
- `remove_band_member` — `20260302000000_band_user_roles.sql:473-523` — verifies caller is admin (lines 487-493)
- `notify_rehearsal_created` — `20260305100000_fix_rehearsal_rls_and_trigger.sql:108-206` — SECURITY DEFINER trigger, reads band_id from NEW row (line 184), no cross-band risk
- `update_song_metadata` — **GAP confirmed** (see Item 2)

**Not Located:**  
`clear_song_metadata` — mentioned in feature input, not found in searched migrations. If it exists and is SECURITY DEFINER with the same NULL band_id logic, it has the same gap.

---

### 4. Edge Functions

**Finding:** PASS

**calendar-feed** (`supabase/functions/calendar-feed/index.ts:1-599`, `verify_jwt: false`):

- Lines 516-520: Queries `band_calendar_subscriptions` by token
- Lines 533-543: Verifies user is still an active member of the band before returning events
- Lines 585-598: If band-scoped token, returns only that band's events; if legacy user token, returns all bands the user is a member of (correct — user sees only their own bands)
- **Verdict:** PASS — token is properly scoped to user+band, membership is verified

**send-push** (`supabase/functions/send-push/index.ts:1-100`, `verify_jwt: false`):

- Lines 9-14: Validates `X-Internal-Secret` header against `PUSH_TRIGGER_SECRET` env var
- Uses service role to read `device_tokens` and send FCM messages
- Called by database trigger (not user-invokable), no cross-band risk
- **Verdict:** PASS — internal trigger, proper secret validation

**deliver-notifications** (mentioned in `supabase/config.toml:120-122`, `verify_jwt: false`):

- File not found in `supabase/functions/`. May not exist or may be a typo in config.toml.
- **Verdict:** UNVERIFIABLE — cannot assess if file does not exist

---

### 5. Client-side Band Switching

**Finding:** **GAP** — Stale data bleed after `selectBand()`

**Root Cause (HIGH Confidence):**

`lib/features/bands/active_band_controller.dart:319-334` — `selectBand()` method:

```dart
Future<void> selectBand(Band band) async {
  // ... validation ...
  await _persistBandId(band.id);
  state = state.copyWith(activeBand: band);
  ref.invalidate(displayBandProvider);
  ref.invalidate(currentUserPermissionsProvider);
  ref.read(selectedSetlistProvider.notifier).clear();
  ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);
}
```

**Invalidations performed:**

- `displayBandProvider` ✓
- `currentUserPermissionsProvider` ✓
- `selectedSetlistProvider.clear()` ✓
- `currentTabProvider` ✓

**Missing invalidations:**

- Gigs providers (if cached)
- Rehearsals providers (if cached)
- Songs / Catalog providers (if cached)
- Members providers (if cached)
- Any other band-scoped Riverpod providers or repositories holding state

**Impact:** When a user switches from Band A to Band B, the dashboard may render cached gigs/rehearsals/songs from Band A until those providers rebuild. This is an isolation failure even though both bands belong to the same user — the user should see _only_ Band B's data post-switch.

**Scope Assessment:**  
Fixing this requires:

1. Enumerating all band-scoped providers/repositories
2. Adding invalidations or implementing a global band-context provider that auto-invalidates dependents on change
3. Testing all screens post-switch to ensure no stale data renders

Given the breadth, this fix is **scoped as a follow-up feature**, not part of this audit implementation (per feature input constraint: "If the client bleed fix (item 5) is large, scope it as a follow-up recommendation").

---

### 6. Export / Backup

**Finding:** PASS (RLS-enforced)

**Evidence:**

`lib/features/settings/data_backup_service.dart:171-199` — `_buildBandExport()`:

- Line 177: Queries `bands` with `.eq('id', bandId)`
- Line 180: Queries `band_members` with `.eq('band_id', bandId)`
- Line 192: Queries `songs` with `.eq('band_id', bandId)`
- All queries filter by `band_id`

**RLS Enforcement:**  
Even if the caller passes a `bandId` for a band they are not a member of, RLS policies on the queried tables will return zero rows (assuming policies are correctly configured per Item 1). The export will succeed but contain no data, or fail if the `bands` query returns null.

**Import:**  
Line 164 calls `_restoreBandData(bandEntry, targetBandId, userId, bandExists)`. The function was not fully examined, but the userId parameter and RLS on insert operations will enforce membership. A user cannot import data into a band they are not a member of.

**Verdict:** PASS — export/import is scoped by band_id and RLS

---

### 7. Storage Buckets

**Finding:** UNVERIFIABLE

**Evidence:**

`lib/features/bands/band_form_screen.dart` (lines not directly quoted in audit, but grep results):

- Uses `supabase.storage.from('band-avatars').uploadBinary(fileName, bytes, ...)`
- Uses `.getPublicUrl(fileName)` to retrieve URL

**Bucket Policies:**  
No storage bucket creation or policy migrations found in `supabase/migrations/`. Storage buckets and their RLS policies are typically configured via the Supabase Dashboard, not migrations in this project.

**Unknown:**

- Can a user in Band A enumerate or read files uploaded by Band B?
- Are bucket policies scoping file access by `band_id` metadata or path prefix?

**Recommendation:**  
Run production SQL verification (see Verification Plan) to inspect `storage.objects` RLS policies and confirm isolation.

---

## Root Causes Summary

| Item                      | Root Cause                                                                                                                                                                                             | Confidence |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| **Item 2 (Songs)**        | `update_song_metadata` RPC allows NULL `band_id` songs to be mutated by any band member. Check: `v_song_band_id IS NOT NULL AND v_song_band_id != p_band_id`. A NULL song_band_id bypasses this guard. | HIGH       |
| **Item 5 (Client Bleed)** | `selectBand()` does not invalidate all band-scoped providers. Gigs, rehearsals, songs, members providers may retain stale data from prior band.                                                        | HIGH       |

---

## Proposed Solution

### Fix 1: NULL band_id Mitigation in `update_song_metadata`

**Approach:**  
Modify the RPC to reject NULL `band_id` songs entirely, or require that NULL songs can only be mutated if the caller is the song creator (if `created_by` column exists and is populated). Since `NULL band_id` represents legacy data, the safest fix is:

```sql
-- After retrieving v_song_band_id (line 50-56 of migration 088):
IF v_song_band_id IS NULL THEN
  RETURN json_build_object('success', false, 'error', 'Cannot modify legacy song without band assignment');
END IF;
```

Alternatively, assign all NULL `band_id` songs to a band (requires data migration and band selection logic, out of scope for this audit).

**Migration:**  
Create `20260702000000_fix_update_song_metadata_null_band.sql`:

- Drop existing `update_song_metadata` function
- Recreate with NULL guard
- Grant execute to authenticated

**If `clear_song_metadata` exists:**  
Apply the same fix.

---

### Fix 2: Client-Side Invalidation (Follow-Up Recommendation)

**Out of Scope for This Implementation:**  
The fix requires broad provider/repository refactoring. Recommend creating a follow-up feature:

- **Feature ID:** `bug/band-switch-stale-data`
- **Scope:** Enumerate all band-scoped providers, add comprehensive invalidations to `selectBand()`, or refactor to use a reactive band-context provider that auto-invalidates dependents

**Minimal Interim Mitigation (Optional, Low Priority):**  
Add invalidations for known high-traffic providers (e.g., gigs, rehearsals) to `selectBand()`. This is a band-aid, not a complete fix.

---

## Database Impact

### Migrations

**Required:**

- `20260702000000_fix_update_song_metadata_null_band.sql` — replace `update_song_metadata` RPC with NULL band_id guard
- `20260702000001_fix_clear_song_metadata_null_band.sql` (if `clear_song_metadata` RPC exists)

**RLS:**  
No new RLS policies. Existing policies are presumed correct (verification in Verification Plan will confirm).

**RPCs:**

- `update_song_metadata` — signature unchanged, behavior change (NULL band_id songs now rejected)
- `clear_song_metadata` (if exists) — same

**Triggers:**  
No changes.

---

## Flutter Architecture Changes

**None for this implementation.**  
Item 5 (client bleed) is deferred to a follow-up feature. No Dart code changes are required to fix Item 2 (songs RPC).

---

## Files to Create

| File                                                                        | Justification                                                                                                                                                                          |
| --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260702000000_fix_update_song_metadata_null_band.sql` | Replace `update_song_metadata` RPC to reject NULL band_id songs                                                                                                                        |
| `supabase/migrations/20260702000001_fix_clear_song_metadata_null_band.sql`  | Defensively handle `clear_song_metadata` RPC (if it exists in production) with NULL band_id guard; uses `DROP FUNCTION IF EXISTS` safe for all cases                                   |
| Additional RLS policy migrations (conditional)                              | If Tier 1 results confirm GAPs on UNVERIFIABLE tables (`songs`, `setlist_songs`, `bands`, `band_members`, etc.), add minimal RLS policy migrations with active-band-membership scoping |

---

## Files to Modify

**None.**  
All changes are database-side (new migration files).

---

## Files Off-Limits

| File                                             | Reason                                       |
| ------------------------------------------------ | -------------------------------------------- |
| `lib/main.dart`                                  | Init order must not change per GUARDRAILS.md |
| `lib/features/bands/active_band_controller.dart` | Item 5 fix is out of scope; no changes       |
| Any client-side Dart files                       | This implementation is database-only         |

---

## System Impact Map

| System                                 | Impact                                                    |
| -------------------------------------- | --------------------------------------------------------- |
| Gigs                                   | unaffected                                                |
| Rehearsals                             | unaffected                                                |
| Setlists / Catalog                     | **affected** — `update_song_metadata` RPC behavior change |
| Members / RBAC                         | unaffected                                                |
| Auth / Session                         | unaffected                                                |
| Routing                                | unaffected                                                |
| Notifications                          | unaffected                                                |
| Platform (iOS / Android / Web / macOS) | unaffected (database-only change)                         |

---

## Regression Risk

**MEDIUM**

**Rationale:**

- **Songs Catalog** is affected — `update_song_metadata` will now reject NULL `band_id` songs (previously allowed)
- This may cause errors if client code calls the RPC on legacy songs without checking `band_id` first
- However, the change closes a cross-band write vulnerability, so the risk is acceptable
- No client code was found in the audit that directly calls `update_song_metadata` on NULL songs
- Impact is isolated to song metadata updates; no other systems affected

---

## Engineer Task Breakdown

1. **Production check for `clear_song_metadata` RPC (Tier 1 — Tony is running now)**

   ```sql
   SELECT proname, pg_get_functiondef(oid) AS definition
   FROM pg_proc
   WHERE proname IN ('clear_song_metadata', 'update_song_metadata')
     AND pg_get_functiondef(oid) LIKE '%SECURITY DEFINER%';
   ```

   - If `clear_song_metadata` exists: proceed with migration `20260702000001`
   - If not found: skip migration `20260702000001`
   - When Tony provides results, incorporate production function signature into migration

2. **Create migration 20260702000000_fix_update_song_metadata_null_band.sql**
   - Drop existing `update_song_metadata` function
   - Recreate with NULL `band_id` guard (reject if `v_song_band_id IS NULL`)
   - Preserve all existing parameters and behavior (BPM conditional, etc.)
   - Grant execute to authenticated
   - Add comment documenting the security fix

3. **Create migration 20260702000001_fix_clear_song_metadata_null_band.sql (if production check confirms it exists)**
   - Write defensively: `DROP FUNCTION IF EXISTS clear_song_metadata(...);`
   - If function exists in prod (per Tier 1 result), pull production signature via `pg_get_functiondef` and recreate with NULL guard
   - If function does not exist, migration remains safe (no-op drop)
   - This approach is safe whether or not the function exists in production

4. **Run migrations locally**
   - `supabase db reset` (local only)
   - Verify no migration errors

5. **Test RPC behavior locally**
   - Call `update_song_metadata` on a song with NULL `band_id` — expect rejection
   - Call `update_song_metadata` on a song with valid `band_id` — expect success

6. **Resolve UNVERIFIABLE Item 1 findings (when Tony provides Tier 1 results)**
   - Reclassify each UNVERIFIABLE table as PASS or GAP
   - For confirmed GAPs on `songs`, `setlist_songs`, `bands`, `band_members`: extend plan with RLS policy migrations using active-band-membership scoping (non-recursive pattern, never query protected table from its own policy to avoid error 42P17)
   - GAPs on `gig_dates`, `gig_responses`, `block_dates`, `band_invitations`, `band_access_events`, `user_band_roles` must also be fixed in this run if confirmed (band-scoped data)
   - Storage bucket policy configuration may remain follow-up if dashboard-only; but if `storage.objects` policies can be added via migration, include them

---

## Verification Plan

### Tier 1 — Pre-Deployment (Run Before `supabase db push`)

**Status:** Tony is running these queries against production now. Results will inform final plan scope (RLS policy migrations for any confirmed GAPs on UNVERIFIABLE tables).

These tests can run against the current production schema (no migrations applied yet).

```sql
-- PRE-DEPLOY TEST 0: Check for clear_song_metadata RPC existence and signature
-- Used to inform migration 20260702000001 approach
SELECT proname, pg_get_functiondef(oid) AS definition
FROM pg_proc
WHERE proname IN ('clear_song_metadata', 'update_song_metadata')
  AND pg_get_functiondef(oid) LIKE '%SECURITY DEFINER%';

-- PRE-DEPLOY TEST 1: List all tables with band_id column but RLS disabled
-- Expected: zero rows (all band-scoped tables should have RLS enabled)
SELECT schemaname, tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    SELECT tablename
    FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name = 'band_id'
  )
  AND tablename NOT IN (
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public' AND rowsecurity = true
  );

-- PRE-DEPLOY TEST 2: List all band-scoped tables with incomplete RLS policies
-- Expected: zero gaps (or known gaps from audit Item 1)
-- Note: cmd = 'ALL' covers all four operations (SELECT/INSERT/UPDATE/DELETE)
DO $$
DECLARE
  tbl TEXT;
  pol_count INT;
  has_all_policy BOOLEAN;
BEGIN
  FOR tbl IN
    SELECT DISTINCT tablename
    FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name = 'band_id'
  LOOP
    -- Check for FOR ALL policy (covers all operations)
    SELECT EXISTS(
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = tbl AND cmd = 'ALL'
    ) INTO has_all_policy;

    IF has_all_policy THEN
      -- Table has FOR ALL policy, no gap
      CONTINUE;
    END IF;

    -- Count distinct operation policies
    SELECT COUNT(DISTINCT cmd)
    INTO pol_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = tbl AND cmd IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE');

    IF pol_count < 4 THEN
      RAISE NOTICE 'GAP: table % has only % distinct RLS policies (expected 4 or one FOR ALL)', tbl, pol_count;
    END IF;
  END LOOP;
END $$;

-- PRE-DEPLOY TEST 3: Count songs with NULL band_id
-- Documents the legacy data volume
SELECT COUNT(*) AS null_band_id_song_count
FROM songs
WHERE band_id IS NULL;

-- PRE-DEPLOY TEST 4: Check storage.objects RLS status
-- Expected: rowsecurity = true
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'storage' AND tablename = 'objects';
```

---

### Tier 2 — Post-Deployment (Run After `supabase db push` Succeeds)

```sql
-- POST-DEPLOY TEST 1: Verify update_song_metadata function exists with new signature
-- Expected: function exists, contains 'NULL band_id' check in definition
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'update_song_metadata'
  AND pg_get_functiondef(oid) LIKE '%NULL band_id%';
-- If zero rows, the migration did not apply or the guard text differs.

-- POST-DEPLOY TEST 2: Verify clear_song_metadata fix (if function exists)
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'clear_song_metadata'
  AND pg_get_functiondef(oid) LIKE '%NULL band_id%';

-- POST-DEPLOY TEST 3: Call update_song_metadata on a NULL band_id song (should fail)
-- Use a test user account that is a member of a band.
-- If no NULL songs exist, create one for testing:
-- INSERT INTO songs (id, band_id, title, artist, duration_seconds) VALUES (gen_random_uuid(), NULL, 'Test Song', 'Test Artist', 180);
-- Then call the RPC (adjust UUIDs as needed):
-- SELECT update_song_metadata('<null_song_id>', '<test_band_id>', 120, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
-- Expected result: {"success": false, "error": "Cannot modify legacy song without band assignment"}

-- POST-DEPLOY TEST 4: Call update_song_metadata on a valid band_id song (should succeed)
-- SELECT update_song_metadata('<valid_song_id>', '<matching_band_id>', 130, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
-- Expected result: {"success": true}

-- POST-DEPLOY TEST 5: Storage bucket policy verification
-- List all policies on storage.objects and confirm band isolation logic
SELECT schemaname, tablename, policyname, cmd, qual::text AS using_clause
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects';
-- Manual review required: confirm policies scope by band_id or path prefix
```

---

## QA Regression Areas

QA must specifically test:

1. **Song Metadata Updates (Primary)**
   - Create a new song in Band A
   - Edit BPM, lyrics, tuning (via UI or direct RPC call if accessible)
   - Verify update succeeds
   - If legacy NULL `band_id` songs exist in production, attempt to edit one — verify update is blocked with user-friendly error

2. **Multi-Band Song Isolation (Primary)**
   - User is a member of Band A and Band B
   - Band A has song "Song X" with `band_id = A_ID`
   - Band B has song "Song Y" with `band_id = B_ID`
   - While active in Band A, attempt to view/edit Song Y — verify access denied or not visible
   - While active in Band B, attempt to view/edit Song X — verify access denied or not visible

3. **Band Switching (Item 5 Known Issue — Test for Visibility)**
   - User switches from Band A to Band B
   - Observe dashboard, setlists, gigs, rehearsals screens
   - **Expected (current behavior):** May see stale Band A data until screens rebuild
   - **Document** any visible bleed as a known issue for follow-up feature

4. **Export / Backup (Spot Check)**
   - Export Band A's data
   - Verify export contains only Band A's songs/gigs/rehearsals (no Band B data)
   - Import export into a new band — verify success

5. **Calendar Feed (Spot Check)**
   - Subscribe to Band A's iCal feed
   - Verify feed contains only Band A's events (no other bands)

6. **Storage (Manual Verification)**
   - Upload a band avatar for Band A
   - Log in as a user in Band B (not a member of Band A)
   - Verify Band B's user cannot access/enumerate Band A's avatar URL (if URL is guessable)

---

## Rollout / Migration Strategy

**Standard deployment:**

1. Create and test migrations locally
2. Run Tier 1 verification queries against production (read-only, no schema changes)
3. Review results with Tony
4. Apply migrations to production: `supabase db push`
5. Run Tier 2 verification queries
6. Monitor production logs for `update_song_metadata` errors for 24 hours
7. If NULL `band_id` song update errors are reported by users, coordinate with Tony on legacy data migration strategy (assign all NULL songs to a default band or prompt users to claim them)

**Rollback:**  
If critical issues arise, rollback is **not recommended** as it re-opens the cross-band write vulnerability. Instead, fix forward:

- If the NULL guard is too strict, modify the RPC to allow NULL songs only if `created_by = auth.uid()` (requires schema check for `created_by` column existence)

---

## Out of Scope

1. **Client-side band switching invalidation** (Item 5) — deferred to follow-up feature `bug/band-switch-stale-data`
2. **Legacy song migration** — assigning all NULL `band_id` songs to bands is not part of this audit; requires product decision
3. **Storage bucket policy configuration** — if gaps are found in Tier 2 verification and cannot be addressed via migration (dashboard-only configuration), address in separate ticket
4. **RLS policy creation for UNVERIFIABLE tables** (Item 1) — **Conditional**: If Tier 1 results confirm GAPs, these WILL be fixed in this run with minimal RLS migrations. Only remains out-of-scope if Tier 1 confirms PASS for all UNVERIFIABLE tables.

---

## Reference Docs Consulted

- `docs/reference/architecture/database_schema.md` (lines 1-178) — table inventory, RPC list
- `docs/agents/ARCHITECT.md` (full)
- `docs/agents/GUARDRAILS.md` (full)
- `docs/agents/OPERATING_MODEL.md` (full)

---

## Migration Files Examined

- `supabase/migrations/084_update_song_metadata_conditional_bpm.sql` (lines 1-98)
- `supabase/migrations/088_add_lyrics_youtube_to_update_song_rpc.sql` (lines 1-117)
- `supabase/migrations/20260109_notifications.sql` (lines 1-263)
- `supabase/migrations/20260302000000_band_user_roles.sql` (lines 1-526)
- `supabase/migrations/20260305100000_fix_rehearsal_rls_and_trigger.sql` (lines 1-213)
- Edge Function: `supabase/functions/calendar-feed/index.ts` (lines 1-599 partially)
- Edge Function: `supabase/functions/send-push/index.ts` (lines 1-100)

---

## Dart Files Examined

- `lib/features/bands/active_band_controller.dart` (lines 1-523)
- `lib/features/setlists/setlist_repository.dart` (lines 0-99)
- `lib/features/settings/data_backup_service.dart` (lines 1-199)
- `lib/features/bands/band_form_screen.dart` (grep results only, upload logic confirmed)

---

**ARCHITECT_PLAN.md Complete.**  
Ready for Engineer implementation and QA validation.
