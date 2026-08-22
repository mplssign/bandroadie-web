# Architect Plan — bug/setlist-rpc-missing-membership-check

## Feature Slug

`bug/setlist-rpc-missing-membership-check`

## Problem Summary

Four SECURITY DEFINER RPC functions in the setlist domain perform real writes against setlist/catalog data with no internal authorization check at all — not even a null check on `auth.uid()`. They act on whatever `setlist_id` or `band_id` the caller passes, with no verification that the caller belongs to the band that owns the target row. This is independent of the C6 security-definer-revoke-public grants issue: revoking anon/PUBLIC execute does not fix this, because `authenticated` retains execute on all four and the gap lives inside the function body, not the grants.

Any logged-in BandRoadie user, in any band, can call these RPCs today against a setlist_id/band_id belonging to a band they have no membership in, and the write succeeds. This is a cross-tenant data-tampering vulnerability.

**Affected functions:**

1. `add_special_item_to_setlist(p_setlist_id, p_special_item_id, p_item_type)` — inserts into `setlist_songs` for whatever `p_setlist_id` is passed; no membership check
2. `ensure_catalog_setlist(p_band_id)` — creates/merges catalog setlists for whatever `p_band_id` is passed, including deleting duplicate catalog rows; no membership check
3. `increment_setlist_positions(p_setlist_id)` — bumps every song's position in whatever setlist is passed; no membership check
4. `reorder_setlist_items(p_setlist_id, p_row_ids)` and its thin wrapper `reorder_setlist_songs` — validates the row ids belong to the setlist, but never validates the caller belongs to the band; no membership check

All four are called directly from the Flutter app today (`special_item_repository.dart`, `setlist_repository.dart`) — live, reachable production code, not dead surface. It has worked correctly in practice only because callers have so far been legitimate band members; nothing in the function body enforces that.

## Root Cause

**Cause:** Function bodies perform writes with SECURITY DEFINER (bypassing RLS) but contain no internal authorization logic to verify the caller (`auth.uid()`) is an active member of the band that owns the target setlist/band_id. The functions trust the caller-supplied IDs unconditionally.

**Confidence:** `HIGH` — confirmed via direct inspection of all 4 function bodies:

- `add_special_item_to_setlist` and `reorder_setlist_items` from migration `20260814120002_restore_setlist_rpc_definitions.sql`
- `ensure_catalog_setlist` and `increment_setlist_positions` via `pg_get_functiondef` query against production database (Supabase project `nekwjxvgbveheooyorjo`) on 2026-08-22

Cross-referenced against correct pattern from `clear_song_metadata` (migration `20260811120002_revert_clear_song_metadata_single_value.sql`) which implements proper `auth.uid()` + `band_members` check. **No function body in this plan is inferred or reconstructed — all are verified current production code.**

## Reference Docs Consulted

- `docs/features/security-definer-revoke-public/CLASSIFICATION_NOTES.md` — §3e documents ~21 functions with correct authorization pattern (auth.uid() check + is_band_member check); §3f identifies the 4 vulnerable functions as having no internal authorization check
- `docs/features/security-definer-revoke-public/ARCHITECT_PLAN.md` — "Out of Scope" §1 explicitly deferred this fix to a separate feature, since it requires function-body changes (not just grants)
- No setlist-specific reference documentation exists in `docs/reference/` — this gap is noted

## Existing System Analysis

### Current Function Behavior (Vulnerable Pattern)

**Example: add_special_item_to_setlist** (from migration `20260814120002_restore_setlist_rpc_definitions.sql`):

```plpgsql
CREATE OR REPLACE FUNCTION public.add_special_item_to_setlist(
  p_setlist_id uuid,
  p_special_item_id uuid,
  p_item_type text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_existing_count INT;
  v_max_position   INT;
  v_new_position   INT;
  v_new_row_id     UUID;
BEGIN
  -- NO AUTH CHECK HERE
  -- Count existing items and find the max position
  SELECT COUNT(*), COALESCE(MAX(position), -1)
    INTO v_existing_count, v_max_position
    FROM public.setlist_songs
   WHERE setlist_id = p_setlist_id;

  v_new_position := v_max_position + 1;

  -- Insert the new special item at the end
  INSERT INTO public.setlist_songs (
    setlist_id, song_id, special_item_id, item_type, position
  ) VALUES (
    p_setlist_id, NULL, p_special_item_id, p_item_type, v_new_position
  )
  RETURNING id INTO v_new_row_id;

  RETURN jsonb_build_object(
    'success', true,
    'new_row_id', v_new_row_id,
    'new_position', v_new_position,
    'existing_count', v_existing_count
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;
```

**What's missing:** No `auth.uid()` check, no query to `band_members` table, no verification that the caller belongs to the band that owns `p_setlist_id`.

**Same pattern in:**

- `reorder_setlist_items` — validates row IDs belong to setlist but never checks caller is a band member
- `reorder_setlist_songs` — wrapper calling `reorder_setlist_items`, inherits same gap
- `ensure_catalog_setlist` — function body captured from production (see Task 2 below)
- `increment_setlist_positions` — function body captured from production (see Task 3 below)

### Correct Pattern (from clear_song_metadata)

From migration `20260811120002_revert_clear_song_metadata_single_value.sql`:

```plpgsql
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  v_song_band_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RETURN json_build_object('success', false, 'error', 'Access denied: not an active member of this band');
  END IF;

  -- Proceed with operation only after authorization passes
```

This pattern appears in ~21 functions documented in CLASSIFICATION_NOTES.md §3e:

- `bulk_add_songs_to_setlist`
- `clear_song_metadata`
- `create_band`
- `delete_setlist`
- `delete_song_from_catalog`
- `delete_song_from_setlist`
- `move_song_between_setlists`
- `reorder_band_members`
- `reorder_setlists`
- `update_song_metadata`
- And others

## Proposed Solution

**Core Changes:**

Add internal authorization check to each of the 4 distinct function bodies (5 function signatures total including wrapper) following the established pattern from `clear_song_metadata`:

1. **At function start:** Verify `auth.uid()` is not null
2. **Resolve band_id:**
   - For functions taking `setlist_id`: `SELECT band_id FROM setlists WHERE id = p_setlist_id`
   - For functions taking `band_id`: use `p_band_id` directly
3. **Check band membership:** `SELECT EXISTS(SELECT 1 FROM band_members WHERE band_id = v_band_id AND user_id = v_user_id AND status = 'active')`
4. **Reject unauthorized callers:**
   - Functions returning `jsonb`: `RETURN jsonb_build_object('success', false, 'error', '...')`
   - Functions returning `uuid` or `void`: `RAISE EXCEPTION '...'`
5. **Proceed with existing operation logic only after authorization passes**

**Pattern Template:**

```plpgsql
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  v_band_id UUID;
  -- ... existing declares
BEGIN
  -- AUTHORIZATION CHECK (add at start)
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
    -- OR for non-jsonb returns: RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- For setlist_id functions: resolve band_id
  SELECT band_id INTO v_band_id FROM setlists WHERE id = p_setlist_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Setlist not found');
    -- OR for non-jsonb returns: RAISE EXCEPTION 'Setlist not found';
  END IF;

  -- For band_id functions: use p_band_id directly as v_band_id

  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = v_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RETURN json_build_object('success', false, 'error', 'Access denied: not an active member of this band');
    -- OR for non-jsonb returns: RAISE EXCEPTION 'Access denied: not an active member of this band';
  END IF;

  -- EXISTING LOGIC (unchanged below this point)
  -- ...
END;
```

**Decision on reorder_setlist_songs wrapper:**
Since it's a one-line SQL function delegating to `reorder_setlist_items`, the check added to `reorder_setlist_items` will protect both. No separate modification needed for the wrapper.

## Database Impact

**RPC Functions:** 4 functions modified (body changes to add authorization):

- `add_special_item_to_setlist(p_setlist_id uuid, p_special_item_id uuid, p_item_type text)`
- `ensure_catalog_setlist(p_band_id uuid)`
- `increment_setlist_positions(p_setlist_id uuid)`
- `reorder_setlist_items(p_setlist_id uuid, p_row_ids uuid[])`

**Wrapper function:** `reorder_setlist_songs` inherits protection from `reorder_setlist_items` — no modification required

**Migrations:** 4 new migration files required (one per function body change)

**RLS Policies:** Not modified — existing policies on `setlist_songs` and `setlists` tables remain unchanged. Adding internal authorization to SECURITY DEFINER functions adds defense-in-depth but does not change RLS logic.

**Triggers:** Not applicable — no trigger logic changes

**Edge Functions:** Not modified — no edge functions call these RPCs

**Grant Changes:** Not required — `authenticated` retain execute access (grants were already corrected in security-definer-revoke-public feature)

## Flutter Architecture Changes

None — this is a database-only change. No Dart code modifications required. Flutter code continues calling the same RPC signatures with the same parameters; legitimate calls (caller is a member) succeed, unauthorized calls (caller not a member) now return error JSON or raise exception.

## Files to Create

| File                                                                              | Justification                                                 |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `docs/features/setlist-rpc-missing-membership-check/ARCHITECT_PLAN.md`            | Required architecture documentation per ARCHITECT.md Phase 12 |
| `supabase/migrations/20260822120100_add_membership_check_add_special_item.sql`    | Add authorization to `add_special_item_to_setlist`            |
| `supabase/migrations/20260822120101_add_membership_check_ensure_catalog.sql`      | Add authorization to `ensure_catalog_setlist`                 |
| `supabase/migrations/20260822120102_add_membership_check_increment_positions.sql` | Add authorization to `increment_setlist_positions`            |
| `supabase/migrations/20260822120103_add_membership_check_reorder_items.sql`       | Add authorization to `reorder_setlist_items`                  |

## Files to Modify

| File | What changes                                                 |
| ---- | ------------------------------------------------------------ |
| None | Database-only changes — all modifications via new migrations |

**Optional (not required for fix):**
| File | What changes |
|------|-------------|
| `docs/agents/GUARDRAILS.md` | Could document this as precedent for SECURITY DEFINER authorization pattern, but not strictly required |

## Files Off-Limits

| File                                     | Reason                                                                          |
| ---------------------------------------- | ------------------------------------------------------------------------------- |
| All files under `lib/`                   | Backend-only fix, no Dart code changes required                                 |
| All files under `supabase/functions/`    | No edge functions call these RPCs                                               |
| `lib/main.dart`                          | Init order must not change (GUARDRAILS.md §1)                                   |
| Existing migrations (pre-20260822120100) | Approved migrations — do not modify                                             |
| `reorder_setlist_songs` function         | Inherits protection from `reorder_setlist_items` check — no modification needed |

## System Impact Map

| System                                 | Impact                                                                                                                                                                     |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected — no gig-related RPCs modified                                                                                                                                  |
| Rehearsals                             | unaffected — no rehearsal-related RPCs modified                                                                                                                            |
| Setlists / Catalog                     | **affected** — all 4 functions are setlist/catalog mutation operations; legitimate authenticated flows preserved but now properly gated                                    |
| Members / RBAC                         | **affected** — adding `band_members` authorization checks to verify active membership                                                                                      |
| Auth / Session                         | unaffected — no authentication flow changes                                                                                                                                |
| Routing                                | unaffected — no routing logic changes                                                                                                                                      |
| Notifications                          | unaffected — no notification-related RPCs modified                                                                                                                         |
| Platform (iOS / Android / Web / macOS) | **affected (all)** — all platforms call these RPCs from `special_item_repository.dart` and `setlist_repository.dart`; authenticated flows preserved but now properly gated |

## Regression Risk

**Level:** `MEDIUM`

**Rationale:**

**+Risk (HIGH factors):**

- **Zero automated test coverage** on repository/controller layer (0/18 repositories, 0/15 controllers per 2026-08-21 audit) — manual verification is the only safety net
- **Known error-swallowing pattern in repositories** (`catch (e) { return []; }` — GUARDRAILS.md) — if this breaks an authenticated call path, likely symptom is empty data quietly, not visible error
- **Function body changes to live production code** — unlike the security-definer-revoke-public feature (grants-only, no behavior change for legitimate callers), this changes function _bodies_ that the app calls directly today
- **4 functions touched** — multiple surface areas increase risk of implementation error

**-Risk (LOW factors):**

- **Defense-in-depth fix** — functions are currently exploitable but not actively exploited (no evidence of malicious use in practice)
- **Established pattern to follow** — ~21 existing functions implement the same authorization pattern correctly (clear_song_metadata, delete_song_from_catalog, etc.)
- **Clear boundary** — only setlist/catalog domain affected, no cross-system dependencies
- **No schema changes** — only function body logic changes, no table structure changes
- **No signature changes** — Flutter code calls the same functions with the same parameters; legitimate calls succeed, unauthorized calls return error JSON or raise exception
- **Single failure mode** — if authorization check is too strict, legitimate calls fail visibly with error JSON/exception; if too loose, vulnerability remains (but no worse than current state)

**Risk is not HIGH because:**

- No auth flow changes, no session changes, no init order changes
- Clear precedent pattern exists in ~21 functions already deployed
- No table schema changes, no RLS policy changes
- Legitimate callers are preserved explicitly (status = 'active' members)
- Single failure mode (authorization logic) with visible error path

**Risk is not LOW because:**

- Zero automated test coverage to catch regressions
- Repositories may silently fail rather than throw visible errors
- 4 functions with distinct call paths and logic — implementation error could affect one without affecting others
- Function body changes to live production code paths (higher risk than grants-only changes)

## Engineer Task Breakdown

### Task 1: Add Authorization to add_special_item_to_setlist

**Goal:** Add `auth.uid()` + `band_members` check to `add_special_item_to_setlist` function body

**Steps:**

1. Create `supabase/migrations/20260822120100_add_membership_check_add_special_item.sql`
2. Read existing function body from migration `20260814120002_restore_setlist_rpc_definitions.sql`
3. Add authorization block at start of BEGIN block:

   ```plpgsql
   v_user_id := auth.uid();
   IF v_user_id IS NULL THEN
     RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
   END IF;

   SELECT band_id INTO v_band_id FROM setlists WHERE id = p_setlist_id;
   IF NOT FOUND THEN
     RETURN jsonb_build_object('success', false, 'error', 'Setlist not found');
   END IF;

   SELECT EXISTS(
     SELECT 1 FROM band_members
     WHERE band_id = v_band_id AND user_id = v_user_id AND status = 'active'
   ) INTO v_is_member;

   IF NOT v_is_member THEN
     RETURN jsonb_build_object('success', false, 'error', 'Access denied: not an active member of this band');
   END IF;
   ```

4. Add `v_user_id UUID; v_is_member BOOLEAN; v_band_id UUID;` to DECLARE block
5. Preserve all existing logic below authorization block unchanged
6. Include rollback: `DROP FUNCTION IF EXISTS add_special_item_to_setlist(UUID, UUID, TEXT);` then recreate old version from migration `20260814120002_restore_setlist_rpc_definitions.sql`

### Task 2: Add Authorization to ensure_catalog_setlist

**Goal:** Add `auth.uid()` + `band_members` check to `ensure_catalog_setlist` function body

**PRE-IMPLEMENTATION GATE:**

Run this exact query against production:
```sql
SELECT pg_get_functiondef('ensure_catalog_setlist'::regproc);
```

The result of that query — exactly as returned, not retyped or reformatted — is the base you build the authorization-check version from. Do not use the "REFERENCE BODY" block below as your literal source text; it is a structural reference only, provided so you can confirm nothing has substantively changed since this plan was written.

Compare your fresh query result against the reference block below for **substantive** differences: different SQL statements, different WHERE/JOIN conditions, different table or column references, different control flow, added or removed logic. Do not compare whitespace, line breaks, or blank-line spacing — `pg_get_functiondef` output commonly carries incidental trailing whitespace that has no bearing on behavior, and is not a signal of drift.

If you find a substantive difference: STOP. Do not proceed, do not reconcile it yourself, and do not guess which version is correct — report the mismatch to the Manager. Production has drifted since this plan was written and needs Architect re-review.

If there is no substantive difference (including if there is none at all): proceed, using your own freshly-queried result — not the reference block below — as the literal "before" text for the migration.

**REFERENCE BODY (captured 2026-08-22 — structural reference only, not a literal-match requirement; see PRE-IMPLEMENTATION GATE):**

```plpgsql
CREATE OR REPLACE FUNCTION public.ensure_catalog_setlist(p_band_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  catalog_id UUID;
  catalog_count INTEGER;
  oldest_catalog RECORD;
BEGIN
  -- Check how many Catalogs exist for this band
  SELECT COUNT(*) INTO catalog_count
  FROM public.setlists
  WHERE band_id = p_band_id
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'));

  -- If exactly one exists, return it
  IF catalog_count = 1 THEN
    SELECT id INTO catalog_id
    FROM public.setlists
    WHERE band_id = p_band_id
      AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
    LIMIT 1;

    -- Ensure metadata is correct
    UPDATE public.setlists
    SET name = 'Catalog', setlist_type = 'catalog', is_catalog = true
    WHERE id = catalog_id AND (name != 'Catalog' OR setlist_type != 'catalog' OR is_catalog != true);

    RETURN catalog_id;
  END IF;

  -- If none exists, create one
  IF catalog_count = 0 THEN
    INSERT INTO public.setlists (band_id, name, setlist_type, is_catalog, total_duration)
    VALUES (p_band_id, 'Catalog', 'catalog', true, 0)
    RETURNING id INTO catalog_id;

    RETURN catalog_id;
  END IF;

  -- If multiple exist, keep the oldest one and merge songs from others
  SELECT id, name INTO oldest_catalog
  FROM public.setlists
  WHERE band_id = p_band_id
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
  ORDER BY created_at ASC
  LIMIT 1;

  catalog_id := oldest_catalog.id;

  -- Move songs from duplicate Catalogs to the primary one
  INSERT INTO public.setlist_songs (setlist_id, song_id, position, bpm, tuning, duration_seconds)
  SELECT
    catalog_id,
    ss.song_id,
    COALESCE((SELECT MAX(position) FROM public.setlist_songs WHERE setlist_id = catalog_id), 0) + ROW_NUMBER() OVER (ORDER BY ss.position),
    ss.bpm,
    ss.tuning,
    ss.duration_seconds
  FROM public.setlist_songs ss
  JOIN public.setlists sl ON ss.setlist_id = sl.id
  WHERE sl.band_id = p_band_id
    AND sl.id != catalog_id
    AND (sl.setlist_type = 'catalog' OR sl.is_catalog = true OR LOWER(sl.name) IN ('catalog', 'all songs'))
    AND NOT EXISTS (
      SELECT 1 FROM public.setlist_songs existing
      WHERE existing.setlist_id = catalog_id AND existing.song_id = ss.song_id
    );

  -- Delete songs from duplicate Catalogs
  DELETE FROM public.setlist_songs
  WHERE setlist_id IN (
    SELECT id FROM public.setlists
    WHERE band_id = p_band_id
      AND id != catalog_id
      AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
  );

  -- Delete duplicate Catalogs
  DELETE FROM public.setlists
  WHERE band_id = p_band_id
    AND id != catalog_id
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'));

  -- Ensure primary Catalog has correct metadata
  UPDATE public.setlists
  SET name = 'Catalog', setlist_type = 'catalog', is_catalog = true
  WHERE id = catalog_id;

  RETURN catalog_id;
END;
$function$;
```

**Steps:**

1. Create `supabase/migrations/20260822120101_add_membership_check_ensure_catalog.sql`
2. Run PRE-IMPLEMENTATION GATE (query production, compare against reference block for substantive differences)
3. Add authorization block immediately after `BEGIN`, before the first existing statement (`-- Check how many Catalogs exist for this band`):

   ```plpgsql
   -- AUTHORIZATION CHECK
   v_user_id := auth.uid();
   IF v_user_id IS NULL THEN
     RAISE EXCEPTION 'Not authenticated';
   END IF;

   SELECT EXISTS(
     SELECT 1 FROM band_members
     WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
   ) INTO v_is_member;

   IF NOT v_is_member THEN
     RAISE EXCEPTION 'Access denied: not an active member of this band';
   END IF;
   ```

4. Add `v_user_id UUID; v_is_member BOOLEAN;` to DECLARE block
5. Preserve all existing logic below authorization block completely unchanged, byte-for-byte
6. Include rollback: `DROP FUNCTION IF EXISTS ensure_catalog_setlist(UUID);` then recreate using your own freshly-queried result from the PRE-IMPLEMENTATION GATE step (verbatim, as returned by the query — not the reference block above)

**Error handling decision:** Functions returning `uuid` cannot carry JSON error payloads. Use `RAISE EXCEPTION` to reject unauthorized callers — this produces a visible Postgres error that surfaces to the client, preventing silent failures. A bare `NULL` return would risk being interpreted as a legitimate "no catalog" result by callers not checking for it carefully.

### Task 3: Add Authorization to increment_setlist_positions

**Goal:** Add `auth.uid()` + `band_members` check to `increment_setlist_positions` function body

**PRE-IMPLEMENTATION GATE:**

Run this exact query against production:
```sql
SELECT pg_get_functiondef('increment_setlist_positions'::regproc);
```

The result of that query — exactly as returned, not retyped or reformatted — is the base you build the authorization-check version from. Do not use the "REFERENCE BODY" block below as your literal source text; it is a structural reference only, provided so you can confirm nothing has substantively changed since this plan was written.

Compare your fresh query result against the reference block below for **substantive** differences: different SQL statements, different WHERE/JOIN conditions, different table or column references, different control flow, added or removed logic. Do not compare whitespace, line breaks, or blank-line spacing — `pg_get_functiondef` output commonly carries incidental trailing whitespace that has no bearing on behavior, and is not a signal of drift.

If you find a substantive difference: STOP. Do not proceed, do not reconcile it yourself, and do not guess which version is correct — report the mismatch to the Manager. Production has drifted since this plan was written and needs Architect re-review.

If there is no substantive difference (including if there is none at all): proceed, using your own freshly-queried result — not the reference block below — as the literal "before" text for the migration.

**REFERENCE BODY (captured 2026-08-22 — structural reference only, not a literal-match requirement; see PRE-IMPLEMENTATION GATE):**

```plpgsql
CREATE OR REPLACE FUNCTION public.increment_setlist_positions(p_setlist_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.setlist_songs
    SET position = position + 1
  WHERE setlist_id = p_setlist_id;
END;
$function$;
```

**Steps:**

1. Create `supabase/migrations/20260822120102_add_membership_check_increment_positions.sql`
2. Run PRE-IMPLEMENTATION GATE (query production, compare against reference block for substantive differences)
3. Add authorization block immediately after `BEGIN`, before the existing `UPDATE` statement:

   ```plpgsql
   -- AUTHORIZATION CHECK
   v_user_id := auth.uid();
   IF v_user_id IS NULL THEN
     RAISE EXCEPTION 'Not authenticated';
   END IF;

   SELECT band_id INTO v_band_id FROM setlists WHERE id = p_setlist_id;
   IF NOT FOUND THEN
     RAISE EXCEPTION 'Setlist not found';
   END IF;

   SELECT EXISTS(
     SELECT 1 FROM band_members
     WHERE band_id = v_band_id AND user_id = v_user_id AND status = 'active'
   ) INTO v_is_member;

   IF NOT v_is_member THEN
     RAISE EXCEPTION 'Access denied: not an active member of this band';
   END IF;
   ```

4. Add DECLARE block (function currently has none): `DECLARE v_user_id UUID; v_is_member BOOLEAN; v_band_id UUID;`
5. Preserve existing `UPDATE` statement completely unchanged
6. Include rollback: `DROP FUNCTION IF EXISTS increment_setlist_positions(UUID);` then recreate using your own freshly-queried result from the PRE-IMPLEMENTATION GATE step (verbatim, as returned by the query — not the reference block above)

**Error handling decision:** Functions returning `void` cannot carry return values. Use `RAISE EXCEPTION` to reject unauthorized callers (consistent with `ensure_catalog_setlist` pattern) — this produces a visible Postgres error that surfaces to the client, preventing silent failures.

### Task 4: Add Authorization to reorder_setlist_items

**Goal:** Add `auth.uid()` + `band_members` check to `reorder_setlist_items` function body

**Steps:**

1. Create `supabase/migrations/20260822120103_add_membership_check_reorder_items.sql`
2. Read existing function body from migration `20260814120002_restore_setlist_rpc_definitions.sql` line 21
3. Add authorization block at start of BEGIN block (before existing validation):

   ```plpgsql
   v_user_id := auth.uid();
   IF v_user_id IS NULL THEN
     RETURN json_build_object('success', false, 'error', 'Not authenticated');
   END IF;

   SELECT band_id INTO v_band_id FROM setlists WHERE id = p_setlist_id;
   IF NOT FOUND THEN
     RETURN json_build_object('success', false, 'error', 'Setlist not found');
   END IF;

   SELECT EXISTS(
     SELECT 1 FROM band_members
     WHERE band_id = v_band_id AND user_id = v_user_id AND status = 'active'
   ) INTO v_is_member;

   IF NOT v_is_member THEN
     RETURN json_build_object('success', false, 'error', 'Access denied: not an active member of this band');
   END IF;
   ```

4. Add `v_user_id UUID; v_is_member BOOLEAN; v_band_id UUID;` to DECLARE block
5. Preserve all existing validation and update logic below authorization block
6. Include rollback: `DROP FUNCTION IF EXISTS reorder_setlist_items(UUID, UUID[]);` then recreate old version from migration `20260814120002_restore_setlist_rpc_definitions.sql`

### Task 5: Verify reorder_setlist_songs Wrapper Inheritance

**Goal:** Confirm `reorder_setlist_songs` wrapper inherits protection from `reorder_setlist_items` check

**Steps:**

1. Read wrapper function body from migration `20260814120002_restore_setlist_rpc_definitions.sql` line 9
2. Verify it's a single SELECT statement delegating to `reorder_setlist_items`
3. Document in ENGINEER_REPORT.md that wrapper requires no modification — authorization check in `reorder_setlist_items` executes for all calls through the wrapper

### Task 6: Production Verification

**Goal:** Confirm all 4 functions have authorization checks applied

**Steps:**

1. Apply all 4 migrations to production: `supabase db push`
2. Verify function bodies updated: `SELECT pg_get_functiondef('add_special_item_to_setlist'::regproc);` (repeat for all 4)
3. Confirm authorization check appears at start of each function body: look for `auth.uid()` and `band_members` query
4. Test unauthorized call (JSON error response functions): attempt to call RPC with setlist_id/band_id from a different band → expect error JSON `{"success": false, "error": "Access denied..."}`
5. Test unauthorized call (RAISE EXCEPTION functions): attempt to call `ensure_catalog_setlist` or `increment_setlist_positions` with band_id/setlist_id from a different band → expect Postgres exception raised
6. Test authorized call: call RPC with setlist_id/band_id from caller's own band → expect success

### Task 7: Write ENGINEER_REPORT.md

**Goal:** Document implementation and verification results

**Steps:**

1. Create `docs/features/setlist-rpc-missing-membership-check/ENGINEER_REPORT.md`
2. Include: task completion checklist (Tasks 1-7), pre/post function body diffs (pg_get_functiondef output), production verification results (authorized vs. unauthorized call tests), any deviations from plan
3. Confirm `flutter analyze` passes (expect 0 Dart changes)
4. Generate `git diff` for review

## Verification Plan

### Tier 1 — Pre-Deployment (Static/Logic Verification)

Must pass before `supabase db push` to production. All tests runnable with zero live database changes.

**PRE-DEPLOY TEST 1: SQL syntax validation**

- Parse each migration file with `psql --dry-run` or equivalent
- Confirm no syntax errors in function body changes

**PRE-DEPLOY TEST 2: Pattern consistency check**

- Verify each function body includes:
  1. `v_user_id := auth.uid();` at start
  2. NULL check: `IF v_user_id IS NULL THEN RETURN/RAISE`
  3. band_id resolution (for setlist_id functions): `SELECT band_id INTO v_band_id FROM setlists WHERE id = p_setlist_id;`
  4. band_members check: `SELECT EXISTS(SELECT 1 FROM band_members WHERE band_id = v_band_id AND user_id = v_user_id AND status = 'active') INTO v_is_member;`
  5. Rejection: `IF NOT v_is_member THEN RETURN/RAISE`
- Cross-reference against `clear_song_metadata` pattern

**PRE-DEPLOY TEST 3: DECLARE block completeness**

- Verify each modified function's DECLARE block includes: `v_user_id UUID; v_is_member BOOLEAN;`
- For setlist_id functions, verify: `v_band_id UUID;` also declared

**PRE-DEPLOY TEST 4: Rollback completeness**

- Verify each migration includes commented rollback block with old function body captured

### Tier 2 — Post-Deployment (After supabase db push)

Run immediately after migrations applied to production.

**POST-DEPLOY TEST 1: Verify function bodies updated**

```sql
-- Confirm authorization check present in add_special_item_to_setlist
SELECT pg_get_functiondef('add_special_item_to_setlist'::regproc);
-- Expected: Function body contains "auth.uid()" and "band_members" query near start

-- Repeat for all 4 functions:
SELECT pg_get_functiondef('ensure_catalog_setlist'::regproc);
SELECT pg_get_functiondef('increment_setlist_positions'::regproc);
SELECT pg_get_functiondef('reorder_setlist_items'::regproc);
```

**POST-DEPLOY TEST 2: Unauthorized call rejection (JSON error response functions — add_special_item_to_setlist)**

```sql
-- Authenticate as user who is a member of Band A only
-- Obtain a valid setlist_id from Band B (different band)
SELECT * FROM supabase.rpc('add_special_item_to_setlist',
  '{"p_setlist_id": "<band-B-setlist-id>", "p_special_item_id": "<any-uuid>", "p_item_type": "set_break"}'::json
);
-- Expected: {"success": false, "error": "Access denied: not an active member of this band"}
```

**POST-DEPLOY TEST 3: Authorized call success (JSON error response functions — add_special_item_to_setlist)**

```sql
-- Authenticate as user who is a member of Band A
-- Use a valid setlist_id from Band A (caller's own band)
SELECT * FROM supabase.rpc('add_special_item_to_setlist',
  '{"p_setlist_id": "<band-A-setlist-id>", "p_special_item_id": "<any-uuid>", "p_item_type": "set_break"}'::json
);
-- Expected: {"success": true, "new_row_id": "<uuid>", ...}
```

**POST-DEPLOY TEST 4: Unauthorized call rejection (RAISE EXCEPTION function — ensure_catalog_setlist)**

```sql
-- Authenticate as user who is a member of Band A only
-- Use Band B's band_id
SELECT * FROM public.ensure_catalog_setlist('<band-B-id>');
-- Expected: Postgres exception raised with message "Access denied: not an active member of this band"
-- (Not JSON error response — this function returns uuid and uses RAISE EXCEPTION on auth failure)
```

**POST-DEPLOY TEST 5: Authorized call success (RAISE EXCEPTION function — ensure_catalog_setlist)**

```sql
-- Authenticate as user who is a member of Band A
-- Use Band A's band_id
SELECT * FROM public.ensure_catalog_setlist('<band-A-id>');
-- Expected: Returns catalog setlist_id (uuid value, not JSON)
```

**POST-DEPLOY TEST 6: Unauthorized call rejection (RAISE EXCEPTION function — increment_setlist_positions)**

```sql
-- Authenticate as user who is a member of Band A only
-- Use a valid setlist_id from Band B
SELECT * FROM public.increment_setlist_positions('<band-B-setlist-id>');
-- Expected: Postgres exception raised with message "Access denied: not an active member of this band"
-- (Not JSON error response — this function returns void and uses RAISE EXCEPTION on auth failure)
```

**POST-DEPLOY TEST 7: Unauthorized call rejection (JSON error response function — reorder_setlist_items)**

```sql
-- Authenticate as user who is a member of Band A only
-- Use a valid setlist_id from Band B with valid row IDs from that setlist
SELECT * FROM supabase.rpc('reorder_setlist_items',
  '{"p_setlist_id": "<band-B-setlist-id>", "p_row_ids": ["<uuid1>", "<uuid2>"]}'::json
);
-- Expected: {"success": false, "error": "Access denied: not an active member of this band"}
```

**POST-DEPLOY TEST 8: Wrapper inheritance verification**

```sql
-- Call reorder_setlist_songs (wrapper) with unauthorized setlist_id
SELECT * FROM supabase.rpc('reorder_setlist_songs',
  '{"p_setlist_id": "<band-B-setlist-id>", "p_row_ids": ["<uuid1>", "<uuid2>"]}'::json
);
-- Expected: {"success": false, "error": "Access denied: not an active member of this band"}
-- (Authorization check in reorder_setlist_items executes for wrapper calls)
```

**Manual Smoke Tests (authenticated flows):**

1. **Add special item to setlist:**
   - iOS app: Navigate to setlist, tap "Add Break"
   - Expected: Set break appears in setlist

2. **Reorder setlist items:**
   - Web app: Drag a song to a new position in setlist
   - Expected: Song position updates

3. **Ensure catalog exists:**
   - Android app: Navigate to Songs (triggers catalog ensure on load)
   - Expected: Catalog setlist visible, no errors

4. **Cross-platform verification:**
   - Test setlist reorder on iOS, Android, Web, macOS
   - Verify no platform-specific regressions

## QA Regression Areas

QA must specifically test (gate: QA approval required before merging per GUARDRAILS.md §11):

1. **Setlist reordering:**
   - Drag songs to reorder setlist on all platforms
   - Verify positions update correctly
   - No silent failures or empty data

2. **Add special items to setlist:**
   - Add set break to setlist
   - Add pause to setlist
   - Verify items appear in correct positions

3. **Catalog initialization:**
   - Fresh band creation → verify catalog created
   - Existing band with catalog → verify catalog loads
   - Legacy band without catalog → verify catalog created on first Songs access

4. **Cross-band isolation (security verification):**
   - User in Band A attempts to modify Band B's setlist via direct RPC call (requires manual Supabase SQL editor test)
   - Expected: Error returned, no modification to Band B data

5. **Error visibility:**
   - Monitor app logs for silent failures (empty arrays returned)
   - Any screen showing empty data when it should show data is regression candidate

6. **Platform coverage:**
   - Test setlist mutations on iOS, Android, Web, macOS
   - Verify consistent behavior across platforms

## Rollout / Migration Strategy

### Rollout Approach Assessment

**Prior Feature Comparison:**
The `security-definer-revoke-public` feature used **direct-to-production batched deployment** because it was grants-only (REVOKE/GRANT) — no behavior change for legitimate callers, only closing anon access holes. That feature carried minimal regression risk for authenticated users.

**This Feature is Different:**

- **Changes function bodies** that live app code calls directly today
- A bug in the added membership check could break legitimate reorder/add-item/catalog-init flows for real users, not just close a hole
- Zero automated test coverage to catch implementation errors before deployment
- Repositories swallow errors (`catch (e) { return []; }`) — silent failures expected

**Supabase Branch Testing Assessment:**

**For branch testing:**

- Allows testing function body changes in isolation before production
- Can verify authorized vs. unauthorized calls work correctly
- Can catch implementation bugs (e.g., wrong variable name, missing DECLARE) before real users hit them
- Zero risk to production data or active users

**Against branch testing:**

- Adds deployment complexity (branch preview, manual testing, branch delete)
- Requires manual test data setup in branch preview database
- Delays fix deployment

**Recommendation:** **Use Supabase branch testing for this feature.**

**Rationale:**

1. Function body changes to live production code paths (higher risk than grants-only)
2. Zero automated test coverage — manual verification is the _only_ safety net
3. Repositories swallow errors — symptom of a bug is likely silent failure (empty data), not visible error
4. 4 functions with distinct logic — implementation error could affect one without affecting others
5. One-time complexity cost (branch testing setup) vs. risk of breaking legitimate flows for 100+ active bands
6. The prior feature's direct-to-production approach was justified by its grants-only nature; that justification does not apply here

### Deployment Steps (with Supabase Branch)

**Phase 1: Pre-Deployment Verification (Local)**

1. Static verification (Tier 1 tests):
   - SQL syntax validation
   - Pattern consistency check against `clear_song_metadata`
   - DECLARE block completeness
   - Rollback block completeness
2. Code review: Engineer reads each migration line-by-line

**Phase 2: Supabase Branch Testing**

1. Create Supabase branch preview: `supabase branches create bug-setlist-rpc-fix`
2. Apply migrations to branch: `supabase db push --linked --branch bug-setlist-rpc-fix`
3. Run POST-DEPLOY TEST 1 against branch: verify function bodies updated
4. Run POST-DEPLOY TESTS 2-8 against branch:
   - Create test users in branch (User A in Band A, User B in Band B)
   - Test unauthorized call rejection (User A tries to modify Band B setlist)
   - Test authorized call success (User A modifies Band A setlist)
   - Verify wrapper inheritance
   - Test RAISE EXCEPTION behavior for `ensure_catalog_setlist` and `increment_setlist_positions`
5. Manual smoke tests against branch preview:
   - Point local Flutter app at branch preview URL (temporarily override Supabase URL in config)
   - Test setlist reorder, add special item, catalog ensure
6. If any test fails: fix migration, reapply to branch, re-test
7. Delete branch after QA approval: `supabase branches delete bug-setlist-rpc-fix`

**Phase 3: Production Deployment**

**Gate: QA approval after branch testing passes**

1. Merge feature branch to main
2. Apply migrations to production: `supabase db push`
3. Monitor for errors during push
4. Run POST-DEPLOY TEST 1 against production: verify function bodies updated
5. Spot-check POST-DEPLOY TEST 3 against production: verify authorized call succeeds (use real band, careful not to corrupt data)
6. Monitor app logs for 24 hours post-deployment

**Phase 4: Post-Production Monitoring**

1. QA spot-checks key flows across platforms
2. Monitor error logs for silent failures or new error patterns
3. If regression detected: execute rollback plan

### Rollback Plan

**Per-migration rollback structure:**
Each migration includes commented rollback block with captured old function body (pre-authorization-check version).

**Example rollback (Task 1):**

```sql
-- ===========================================================================
-- ROLLBACK (restore function body without authorization check)
-- ===========================================================================
DROP FUNCTION IF EXISTS add_special_item_to_setlist(UUID, UUID, TEXT);

CREATE OR REPLACE FUNCTION public.add_special_item_to_setlist(...)
-- ... (old function body from 20260814120002_restore_setlist_rpc_definitions.sql)
```

**Full rollback (all 4 functions):**
Apply rollback blocks in reverse order (Task 4 → Task 3 → Task 2 → Task 1).

**Rollback semantics:**

- Restores function bodies to pre-authorization-check state
- Authenticated users regain full access (including cross-band tampering)
- No data loss — only function logic reverts
- Single-statement rollback per function (DROP + CREATE) executes in <1 second

## Out of Scope

### Explicitly Out of Scope for This Feature

1. **Adding SECURITY DEFINER authorization to other RPC functions:**
   - This feature addresses only the 4 setlist-related functions identified in CLASSIFICATION_NOTES.md §3f
   - Other functions with verified internal authorization (§3e list) are not modified

2. **Changing RLS policies:**
   - Existing policies on `setlist_songs` and `setlists` tables remain unchanged
   - This is defense-in-depth at the SECURITY DEFINER layer, not an RLS change

3. **Signature changes to parameterized helper functions:**
   - From CLASSIFICATION_NOTES.md §3b: 4 helper functions accept arbitrary user_id parameters without verifying they match auth.uid()
   - Those functions (`is_band_admin` 2-arg, `get_bandmate_user_ids`, `get_user_band_ids`, `check_rehearsal_response_access`) are out of scope
   - Information disclosure risk was mitigated by revoking anon access (security-definer-revoke-public feature)

4. **Automated test coverage for repository/controller layer:**
   - Current state: 0/18 repositories, 0/15 controllers have tests (per 2026-08-21 audit)
   - Would significantly reduce regression risk for future changes
   - Large undertaking → separate feature

5. **Error handling improvements in repositories:**
   - Known pattern: `catch (e) { return []; }` swallows errors quietly
   - Should be refactored to surface errors visibly
   - Separate technical debt feature

## Additional Context

### Same Vulnerability Family as Prior Fixes

This is the same root-cause pattern as the `band-export-missing-authz` issue (PR #166/#167, docs at `docs/features/band-export-missing-authz/` and `docs/features/band-export-rpc-anon-execute-gap/`): RPC trusts a caller-supplied ID with no membership check. Different function family, same pattern. Those PRs' fix approach (add auth.uid() + band_members check inside function body) is the correct pattern here.

### Discovered During C6 Classification Pass

Surfaced as a byproduct of the C6 classification pass (2026-08-21, `docs/features/security-definer-revoke-public/CLASSIFICATION_NOTES.md` §3f). Explicitly flagged as higher priority than C6 itself, and explicitly listed as Out of Scope in `docs/features/security-definer-revoke-public/ARCHITECT_PLAN.md` ("Out of Scope" #1) for the grants-only migration, since it requires function-body changes.

### Cross-Tenant Data-Tampering Vulnerability

This is a **cross-tenant data-tampering vulnerability**, not a data-exposure one. The attacker needs:

1. A valid BandRoadie account (authenticated role)
2. A valid `setlist_id` or `band_id` belonging to another band (no membership in that band)

With those two, the attacker can:

- Reorder any band's setlist songs
- Add special items (set breaks/pauses) to any band's setlist
- Force-create/merge catalog setlists for any band
- Increment positions in any band's setlist (if this function is ever called)

### Investigation-Only Prior to This

No code changed, no migration applied yet. CLASSIFICATION_NOTES.md documents the finding; ARCHITECT_PLAN.md (security-definer-revoke-public) explicitly deferred the fix. This feature is the implementation of that deferred fix.

---

**Plan Complete**

Branch: `bug/setlist-rpc-missing-membership-check` (already exists and is checked out)
Next: Engineer implements Tasks 1-7, produces ENGINEER_REPORT.md
