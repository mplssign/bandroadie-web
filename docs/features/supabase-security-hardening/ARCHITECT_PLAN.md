# ARCHITECT_PLAN.md

## Feature Slug

`bug/supabase-security-hardening`

---

## Problem Summary

Five independent security gaps in the Supabase backend, all confirmed via live security linter + direct code inspection:

1. **IDOR on `regenerate_calendar_token`** — any authenticated user can regenerate another user's calendar token and subscribe to their private calendar feed
2. **`financial_entries` SELECT policy ignores `can_view_financials` permission** — contributors with the flag off can still read financial data via direct DB queries
3. **Four setlist-related RPCs missing from migrations** — `reorder_setlist_songs`, `reorder_setlist_items`, `add_special_item_to_setlist`, and `delete_setlist` (partially — exists but missing `SET search_path`) exist live but aren't tracked, breaking schema reproducibility
4. **34 `SECURITY DEFINER` functions have mutable `search_path`** — privilege escalation risk from search_path hijacking
5. **59 `SECURITY DEFINER` functions are executable by `anon` role** — violates least-privilege principle (mitigated by `auth.uid()` checks in destructive RPCs, but still needs explicit revocation)

All five are independent of each other but all resolved via SQL migrations with no Dart/client changes required.

---

## Root Cause

### Finding #1 — IDOR on `regenerate_calendar_token`

**Cause:** Function accepts `p_user_id UUID` parameter with no validation that `p_user_id = auth.uid()`. Any authenticated user can pass another user's UUID, receive that victim's new calendar token, and subscribe to their calendar feed. The function is `SECURITY DEFINER` and granted to `authenticated`, but performs no authorization check before regenerating the token.

**Location:** `supabase/migrations/20260204_calendar_subscription.sql:12-31`

**Confidence:** HIGH (direct observation)

### Finding #2 — `financial_entries_select` policy ignores `can_view_financials`

**Cause:** Policy is `USING (public.check_band_member(band_id))` — only checks active band membership, no role or permission check. A follow-up migration (`20260711081810_tighten_financial_entries_rbac.sql`) tightened INSERT/UPDATE/DELETE to admin/member and includes a comment stating "Contributors with can_view_financials = true can still view entries" — but the SELECT policy has no clause that actually distinguishes `can_view_financials = true` from `false`.

**Location:** `supabase/migrations/20260601000000_create_financial_entries.sql:65-69`

**Confidence:** HIGH (direct observation + migration comment confirms intent/implementation mismatch)

### Finding #3 — Setlist RPC definitions missing from migrations

**Cause:** Three RPCs exist in live production DB but were never tracked in version control: `reorder_setlist_songs`, `reorder_setlist_items`, `add_special_item_to_setlist`. Fourth RPC `delete_setlist` is tracked but missing `SET search_path = public`. Confirmed via full-repo grep of 88 migration files + Dart call sites exist at `lib/features/setlists/setlist_repository.dart:1089` and `lib/features/setlists/special_item_repository.dart:123,307`.

**Impact:** If any environment is rebuilt from migrations alone, these RPCs won't exist and the app's client-side fallback ordering logic (non-atomic, known to be fragile) silently takes over.

**Confidence:** HIGH (confirmed via grep + live linter + Dart call sites)

### Finding #4 — Mutable `search_path` on `SECURITY DEFINER` functions

**Cause:** Functions have `SET search_path = public;` inside the function body (first line of BEGIN block) instead of in the function definition. The secure pattern is:

```sql
CREATE OR REPLACE FUNCTION ...
SECURITY DEFINER
SET search_path = public
AS $$
```

**Affected:** 34 functions including `delete_band`, `update_member_role`, `remove_band_member`, `delete_setlist`, plus 30 others (full list from live linter output).

**Already correct:** `delete_user_account` has `SET search_path = public` in the function definition.

**Impact:** An attacker who can create objects in a schema earlier in the search_path (e.g., `pg_temp`) can hijack function calls to their malicious implementations, escalating privileges.

**Confidence:** HIGH (live linter output + direct observation in migration files)

### Finding #5 — `SECURITY DEFINER` functions executable by `anon`

**Cause:** PostgreSQL grants `EXECUTE` to `PUBLIC` by default unless explicitly revoked. 59 functions are callable by unauthenticated (`anon`) requests.

**Actual risk:** MITIGATED for the 4 destructive RPCs (`delete_band`, `update_member_role`, `remove_band_member`, `delete_user_account`) — all check `auth.uid()` internally and will fail for anon (returns NULL). However, this is defense-in-depth failure — the functions should have `PUBLIC` revoked and `authenticated` granted explicitly per best practice.

**Confidence:** HIGH (direct observation of auth checks + live linter output)

---

## Reference Docs Consulted

- `docs/reference/architecture/architecture.md` — states destructive RPCs "use `SECURITY DEFINER` with `SET search_path = public`" (confirmed not actually true for most)
- `docs/reference/architecture/database_schema.md` — RLS policy inventory, RPC list
- `docs/reference/architecture/supabase_functions.md` — Edge function inventory (not relevant to this ticket)
- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` — comprehensive feature/architecture doc, confirms `SET search_path = public` is documented but not implemented
- `docs/reference/general/AI_DECISIONS.md` — documents SECURITY DEFINER hardening requirements for new functions
- `docs/agents/GUARDRAILS.md` — prohibits RLS policies that query the table they protect (42P17 infinite recursion), mandates `SET search_path = public` for all SECURITY DEFINER functions

---

## Existing System Analysis

### Calendar Token System

- `users.calendar_token` stores a UUID per user for iCal feed subscription
- `regenerate_calendar_token(p_user_id UUID)` is `SECURITY DEFINER`, granted to `authenticated`, takes a user ID parameter with no validation
- `get_my_calendar_token()` correctly uses `auth.uid()` to only return the current user's token
- **Client code exists:** `lib/features/calendar/calendar_subscription_service.dart:224-227` calls it with `params: {'p_user_id': userId}` (inside deprecated, currently-uncalled `regenerateToken()` method)
- IDOR allows attacker to: call `regenerate_calendar_token(victim_uuid)` → receive new token → construct calendar feed URL → subscribe to victim's private calendar (gigs, rehearsals, block-outs across all bands)

### Financial Entries System

- `financial_entries` table stores income/expense records per band
- RLS policies:
  - SELECT: `check_band_member(band_id)` — active membership only
  - INSERT/UPDATE/DELETE: admin/member only (tightened in migration `20260711081810`)
- `contributor_permissions.can_view_financials` column exists (added in `20260604000001`), defaults to FALSE
- Client code (`lib/features/financials/financials_screen.dart`, `lib/features/home/home_tab_content.dart:999-1004`) hides the UI for contributors with `can_view_financials = false`
- Repository (`lib/features/financials/financial_entry_repository.dart`) does an unfiltered `.select()` — relies entirely on RLS
- **Gap:** SELECT policy doesn't check `can_view_financials`, so a contributor with the flag off can still read financial entries via direct DB query (e.g., Supabase client with debug access, or pgAdmin if they gain credentials)

### Setlist Reordering System

- Client uses atomic RPC calls when available, falls back to sequential client-side updates if RPC not found (error code `PGRST202` or `42883`)
- Three RPCs exist live (confirmed by client fallback never triggering in production) but aren't in migrations:
  - `reorder_setlist_songs(p_setlist_id UUID, p_row_ids UUID[])` — **one-line delegate** that calls `reorder_setlist_items`, returns `JSON`
  - `reorder_setlist_items(p_setlist_id UUID, p_row_ids UUID[])` — returns `{success: bool, reordered_count: int, error?: string}`
  - `add_special_item_to_setlist(p_setlist_id UUID, p_special_item_id UUID, p_item_type TEXT)` — returns `{success: bool, new_position: int, error?: string}`
- Fourth RPC `delete_setlist(p_band_id UUID, p_setlist_id UUID)` is tracked in `20260228000000_create_delete_setlist_rpc.sql` but missing `SET search_path = public` in function definition
- Live linter confirms all four exist and are missing `SET search_path`

### Destructive RBAC RPCs

- `delete_band(band_uuid UUID)` — latest definition in `20260607000000_fix_delete_band_cascade.sql`
- `update_member_role(p_member_id UUID, p_band_id UUID, p_new_role TEXT, p_sub_permissions JSONB)` — latest definition in `20260711120000_fix_update_member_role_can_view_financials.sql`
- `remove_band_member(p_member_id UUID, p_band_id UUID)` — latest definition in `20260302000000_band_user_roles.sql`
- `delete_user_account(user_id_to_delete UUID)` — defined in `075_delete_user_account_rpc.sql` with correct `SET search_path = public` in function definition
- All four check `auth.uid()` internally and reject calls where `auth.uid() IS NULL` (anon) or doesn't match required role/permissions
- All four are granted to `authenticated`, but PostgreSQL's default `PUBLIC` grant is not explicitly revoked

---

## Proposed Solution

**Five independent migrations, applied in sequence:**

### Migration 1: Fix `regenerate_calendar_token` IDOR

**File:** `20260814120000_fix_regenerate_calendar_token_idor.sql`

- **Keep existing signature** `regenerate_calendar_token(p_user_id UUID)` — client code exists at `lib/features/calendar/calendar_subscription_service.dart:224-227`
- **Add authorization check as first statement in function body:**
  ```sql
  IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Permission denied: cannot regenerate another user''s calendar token';
  END IF;
  ```
- Add `SET search_path = public` to function definition
- Keep return type `UUID`
- **No signature change** — zero Dart changes required

### Migration 2: Fix `financial_entries_select` RLS policy

**File:** `20260814120001_fix_financial_entries_select_rbac.sql`

- **Create `check_financial_view_permission(p_band_id UUID)` helper:**
  - `SECURITY DEFINER`, `SET search_path = public`
  - Returns TRUE if: role IN ('admin','member') OR (role='contributor' AND can_view_financials=true)
  - Queries `band_members` + `contributor_permissions` only (never queries `financial_entries` — prevents infinite recursion per GUARDRAILS.md)
- **Replace `financial_entries_select` policy:**
  - `USING (public.check_financial_view_permission(band_id))`
- **Grant helper to authenticated:**
  - `GRANT EXECUTE ON FUNCTION check_financial_view_permission(UUID) TO authenticated;`

### Migration 3: Restore missing setlist RPC definitions

**File:** `20260814120002_restore_setlist_rpc_definitions.sql`

- **`CREATE OR REPLACE FUNCTION reorder_setlist_songs`:**
  - **Signature:** `(p_setlist_id UUID, p_row_ids UUID[])` — note parameter is `p_row_ids`, not `p_song_ids`
  - **Return type:** `JSON` (not JSONB)
  - **Body:** One-line delegate: `SELECT public.reorder_setlist_items(p_setlist_id, p_row_ids);`
  - `LANGUAGE sql`, `SECURITY DEFINER`, `SET search_path = public` in function definition
- **`CREATE OR REPLACE FUNCTION reorder_setlist_items`:**
  - Signature: `(p_setlist_id UUID, p_row_ids UUID[])`
  - Return type: `JSON`
  - `SECURITY DEFINER`, `SET search_path = public` in function definition
  - Body: two-phase position update (temp negative positions, then final positions) to avoid UNIQUE constraint violations, handles both `song_id` and `special_item_id` rows
- **`CREATE OR REPLACE FUNCTION add_special_item_to_setlist`:**
  - Signature: `(p_setlist_id UUID, p_special_item_id UUID, p_item_type TEXT)`
  - Return type: `JSONB`
  - `SECURITY DEFINER`, `SET search_path = public` in function definition
  - Body: increment positions of existing items, insert new item at position, return new position
- **`CREATE OR REPLACE FUNCTION delete_setlist`:**
  - Re-issue existing definition from `20260228000000_create_delete_setlist_rpc.sql` with `SET search_path = public` added to function definition
  - No logic changes, only hardening
- **Grant all four to authenticated**

**Engineer task:** Use the exact live definitions provided by Manager/Tony. Do NOT modify signatures or logic.

### Migration 4: Bulk `ALTER FUNCTION ... SET search_path = public`

**File:** `20260814120003_harden_security_definer_search_path.sql`

- **ALTER 27 functions** (excludes the 4 from migration 3 + `regenerate_calendar_token` from migration 1 + `delete_user_account`, `check_band_member`, `get_user_band_role`)
- **Pattern:** `ALTER FUNCTION <name>(<arg_types>) SET search_path = public;`
- **Full list of 27 (verified against live `pg_proc`):**
  1. `generate_invite_token()`
  2. `increment_setlist_positions(p_setlist_id uuid)`
  3. `get_my_calendar_token()`
  4. `prevent_catalog_deletion()`
  5. `update_print_templates_updated_at()`
  6. `check_gig_response_access(p_gig_id uuid)`
  7. `update_song_notes_updated_at()`
  8. `notify_new_band_member()`
  9. `update_updated_at_column()`
  10. `recompute_setlist_stats(UUID)`
  11. `trigger_recompute_setlist_stats()`
  12. `auto_create_catalog_for_band()`
  13. `ensure_catalog_setlist(UUID)`
  14. `prevent_catalog_rename()`
  15. `get_user_band_ids(user_uuid uuid)`
  16. `get_bandmate_user_ids(UUID)`
  17. `is_band_member_with_role(p_band_id uuid, p_roles text[])`
  18. `get_or_create_notification_preferences()`
  19. `mark_all_notifications_read()`
  20. `get_unread_notification_count()`
  21. `update_notification_preferences_updated_at()`
  22. `should_receive_notification(UUID, TEXT)`
  23. `get_band_full_state(UUID)`
  24. `update_user_calendar_preferences_updated_at()`
  25. `update_setlist_duration()`
  26. `delete_band(UUID)` — migration 3 does NOT touch this (only setlist RPCs), include here
  27. `update_member_role(UUID, UUID, TEXT, JSONB)` — migration 3 does NOT touch this, include here
  28. `remove_band_member(UUID, UUID)` — migration 3 does NOT touch this, include here

**Note:** `regenerate_calendar_token` excluded — migration 1 already adds `SET search_path = public` to its definition. `get_user_band_role` is `SECURITY INVOKER`, not DEFINER — excluded. `check_band_member` already has `SET search_path = public` — excluded.

**Engineer task:** Use the exact 27-function list provided by Manager/Tony with verified signatures from live `pg_proc` query.

### Migration 5: Revoke anon access from destructive RPCs

**File:** `20260814120004_revoke_anon_destructive_rpcs.sql`

- **Scope:** 4 destructive RPCs only (not all 59 — the other 55 are flagged as follow-up)
- **Pattern for each:**
  ```sql
  REVOKE EXECUTE ON FUNCTION <name>(<args>) FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION <name>(<args>) TO authenticated;
  ```
- **Functions:**
  1. `delete_band(UUID)`
  2. `update_member_role(UUID, UUID, TEXT, JSONB)`
  3. `remove_band_member(UUID, UUID)`
  4. `delete_user_account(UUID)`

---

## Database Impact

### Migrations

**Required:** 5 new migrations, applied in sequence.

### RLS Policies

**Affected:** `financial_entries_select` policy replaced with new helper function.

**Constraint satisfied:** New helper `check_financial_view_permission` queries `band_members` + `contributor_permissions` only, never `financial_entries` itself, preventing infinite recursion (PostgreSQL error 42P17) per GUARDRAILS.md.

### RPC Functions

**Affected:**

- 1 hardened definition: `regenerate_calendar_token` adds auth check + search_path (signature unchanged)
- 1 new helper: `check_financial_view_permission`
- 3 restored definitions: `reorder_setlist_songs`, `reorder_setlist_items`, `add_special_item_to_setlist`
- 1 re-issued definition: `delete_setlist`
- 27 `ALTER FUNCTION` statements for existing functions (excluding `regenerate_calendar_token`, including destructive RBAC RPCs)
- 4 `REVOKE`+`GRANT` statements

### Triggers

**Unaffected.**

### Auth/Session

**Unaffected** — RPC logic preserved, only security hardening.

---

## Flutter Architecture Changes

**None.** Backend-only changes, zero client code modifications required.

**Client impact:** Transparent. `regenerate_calendar_token` signature is unchanged — existing client code at `lib/features/calendar/calendar_subscription_service.dart:224-227` (deprecated, currently uncalled) will continue to work without modification. The authorization check now prevents IDOR but does not affect legitimate usage where `p_user_id` matches `auth.uid()`.

---

## Files to Create

| Path                                                                         | Justification                                                            |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `supabase/migrations/20260814120000_fix_regenerate_calendar_token_idor.sql`  | Fix finding #1 — IDOR on calendar token regeneration                     |
| `supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql`   | Fix finding #2 — SELECT policy ignores `can_view_financials`             |
| `supabase/migrations/20260814120002_restore_setlist_rpc_definitions.sql`     | Fix finding #3 — restore missing RPC definitions                         |
| `supabase/migrations/20260814120003_harden_security_definer_search_path.sql` | Fix finding #4 — bulk ALTER FUNCTION for mutable search_path             |
| `supabase/migrations/20260814120004_revoke_anon_destructive_rpcs.sql`        | Fix finding #5 — revoke PUBLIC, grant authenticated for destructive RPCs |

---

## Files to Modify

**None.** All changes are additive migrations. No existing migrations are modified (per guardrail). No Dart files modified.

---

## Files Off-Limits

| File                                                              | Reason                                                         |
| ----------------------------------------------------------------- | -------------------------------------------------------------- |
| All files in `lib/`                                               | Backend-only fix, client behavior unchanged                    |
| All existing migration files                                      | Never modify applied migrations                                |
| `supabase/migrations/20260204_calendar_subscription.sql`          | Never modify applied migrations — create new migration instead |
| `supabase/migrations/20260601000000_create_financial_entries.sql` | Never modify applied migrations — create new migration instead |

---

## System Impact Map

| System                                 | Impact                                                                                                      |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                                  |
| Rehearsals                             | unaffected                                                                                                  |
| Setlists / Catalog                     | **affected** — RPC definitions restored, search_path hardened, drag-and-drop reordering integrity preserved |
| Members / RBAC                         | **affected** — destructive RPCs hardened, financial view permissions now enforced at DB layer               |
| Auth / Session                         | unaffected                                                                                                  |
| Routing                                | unaffected                                                                                                  |
| Notifications                          | unaffected                                                                                                  |
| Platform (iOS / Android / Web / macOS) | unaffected — backend only, transparent to clients                                                           |

---

## Regression Risk

**MEDIUM**

### Rationale:

- **Setlists system affected** — 3 RPC definitions restored + 1 re-issued with search_path. Moderate usage, high-value feature (drag-and-drop reordering). If RPCs fail, client falls back to sequential updates (fragile but tested).
- **RBAC affected** — destructive RPCs hardened (`delete_band`, `update_member_role`, `remove_band_member`) via `ALTER FUNCTION` for search_path + `REVOKE`/`GRANT` for anon access. High-value but low-frequency operations. All have `auth.uid()` checks, so anon revocation is defense-in-depth only.
- **Financial entries affected** — SELECT policy tightened. Contributors with `can_view_financials = false` will now correctly be blocked from reading financial data. Client UI already hides this case, so no UI-visible regression expected.
- **Calendar token regeneration** — auth check added + search_path hardened in migration 1. Signature unchanged. Existing client code (deprecated, currently uncalled) continues to work; IDOR now prevented.
- **27 `ALTER FUNCTION` statements** — mechanical, low-risk, high-value. No logic changes, only search_path hardening.
- **No auth/session/init order changes** — preserves initialization guardrails.
- **All changes are additive hardening** — no behavioral changes to existing logic except closing security gaps.

### Risk mitigation:

- Tier 1 tests (pre-deploy) verify helper functions in isolation without calling migrated RPCs
- Tier 2 tests (post-deploy) verify each RPC's hardened behavior + regression coverage for existing functionality
- QA regression testing on setlist reordering (primary affected feature) + financial entry access (contributor vs admin/member)

---

## Engineer Task Breakdown

### Task 1: Create migration files (5 files)

1. Create `supabase/migrations/20260814120000_fix_regenerate_calendar_token_idor.sql`
2. Create `supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql`
3. Create `supabase/migrations/20260814120002_restore_setlist_rpc_definitions.sql`
4. Create `supabase/migrations/20260814120003_harden_security_definer_search_path.sql`
5. Create `supabase/migrations/20260814120004_revoke_anon_destructive_rpcs.sql`

### Task 2: Implement migration 1 — Fix `regenerate_calendar_token` IDOR

- **File:** `20260814120000_fix_regenerate_calendar_token_idor.sql`
- **Content:**
  - `CREATE OR REPLACE FUNCTION regenerate_calendar_token(p_user_id UUID)` — keep existing signature
  - Add as first statement in body: `IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN RAISE EXCEPTION 'Permission denied: cannot regenerate another user''s calendar token'; END IF;`
  - Add `SET search_path = public` to function definition (after `SECURITY DEFINER`)
  - Preserve existing function body after auth check
  - `GRANT EXECUTE ... TO authenticated;`
- **Success criteria:** Function signature unchanged, IDOR prevented via auth check, returns UUID, has immutable search_path

### Task 3: Implement migration 2 — Fix `financial_entries_select` RLS

- **File:** `20260814120001_fix_financial_entries_select_rbac.sql`
- **Content:**
  - `CREATE OR REPLACE FUNCTION check_financial_view_permission(p_band_id UUID) RETURNS BOOLEAN`
  - Body: check role IN ('admin','member') OR (role='contributor' AND EXISTS contributor_permissions with can_view_financials=true)
  - Add `SECURITY DEFINER`, `SET search_path = public` to function definition
  - `GRANT EXECUTE ... TO authenticated;`
  - `DROP POLICY IF EXISTS "financial_entries_select" ON public.financial_entries;`
  - `CREATE POLICY "financial_entries_select" ... USING (public.check_financial_view_permission(band_id));`
- **Success criteria:** Contributor with `can_view_financials = false` cannot SELECT from financial_entries, admin/member can always SELECT

### Task 4: Implement migration 3 — Restore setlist RPC definitions

- **File:** `20260814120002_restore_setlist_rpc_definitions.sql`
- **Content:**
  - Use exact live definitions provided by Manager/Tony — do NOT modify
  - `CREATE OR REPLACE FUNCTION reorder_setlist_songs(p_setlist_id UUID, p_row_ids UUID[]) RETURNS JSON` — **one-line delegate**, parameter is `p_row_ids` not `p_song_ids`
  - `CREATE OR REPLACE FUNCTION reorder_setlist_items(p_setlist_id UUID, p_row_ids UUID[]) RETURNS JSON`
  - `CREATE OR REPLACE FUNCTION add_special_item_to_setlist(p_setlist_id UUID, p_special_item_id UUID, p_item_type TEXT) RETURNS JSONB`
  - `CREATE OR REPLACE FUNCTION delete_setlist(p_band_id UUID, p_setlist_id UUID) RETURNS void` (copy from existing migration, add `SET search_path = public` to definition)
  - All four: `SECURITY DEFINER`, `SET search_path = public` in function definition
  - `GRANT EXECUTE ... TO authenticated;` for all four
- **Success criteria:** All four RPCs callable, `reorder_setlist_songs` delegates to `reorder_setlist_items`, positions persist correctly

### Task 5: Implement migration 4 — Bulk `ALTER FUNCTION` for search_path

- **File:** `20260814120003_harden_security_definer_search_path.sql`
- **Content:**
  - Use exact 27-function list with verified signatures provided by Manager/Tony
  - Generate `ALTER FUNCTION <name>(<args>) SET search_path = public;` for each
  - **Includes:** `delete_band(UUID)`, `update_member_role(UUID, UUID, TEXT, JSONB)`, `remove_band_member(UUID, UUID)`, plus 24 others
  - **Excludes:** 4 from migration 3 (setlist RPCs), `regenerate_calendar_token` from migration 1, `delete_user_account`, `check_band_member`, `get_user_band_role`
- **Success criteria:** All 27 functions have immutable search_path, no function calls fail

### Task 6: Implement migration 5 — Revoke anon access from destructive RPCs

- **File:** `20260814120004_revoke_anon_destructive_rpcs.sql`
- **Content:**
  - `REVOKE EXECUTE ON FUNCTION delete_band(UUID) FROM PUBLIC;`
  - `REVOKE EXECUTE ON FUNCTION update_member_role(UUID, UUID, TEXT, JSONB) FROM PUBLIC;`
  - `REVOKE EXECUTE ON FUNCTION remove_band_member(UUID, UUID) FROM PUBLIC;`
  - `REVOKE EXECUTE ON FUNCTION delete_user_account(UUID) FROM PUBLIC;`
  - `GRANT EXECUTE ON FUNCTION delete_band(UUID) TO authenticated;`
  - `GRANT EXECUTE ON FUNCTION update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;`
  - `GRANT EXECUTE ON FUNCTION remove_band_member(UUID, UUID) TO authenticated;`
  - `GRANT EXECUTE ON FUNCTION delete_user_account(UUID) TO authenticated;`
- **Success criteria:** Anon requests to these RPCs are rejected with permission denied, authenticated requests succeed (if auth checks pass)

### Task 7: Validate migrations locally

- Run `supabase db reset --linked` (if allowed) or `supabase db push --linked` (if reset blocked by remote-only migrations per repo memory)
- Confirm all 5 migrations apply without error
- If `db push` is blocked by migration history drift, escalate to Manager

### Task 8: Write ENGINEER_REPORT.md

- Document each migration's purpose, SQL strategy, and test results
- Include `git diff` of new migration files
- Report any blockers or deviations from plan

---

## Verification Plan

### Tier 1 — Pre-deployment (run BEFORE `supabase db push`)

**Context:** Test functions/objects that already exist in the database unchanged. Do NOT call any function being replaced — it has not been updated yet. All Tier 1 tests must be runnable with zero schema changes applied.

#### Tier 1.1: Verify existing `check_band_member` helper (used by new `check_financial_view_permission`)

```sql
-- PRE-DEPLOY TEST 1.1: Verify check_band_member returns TRUE for active member
DO $$
DECLARE
  v_test_band_id UUID;
  v_test_user_id UUID;
  v_result BOOLEAN;
BEGIN
  -- Find an active band member (any band, any user)
  SELECT bm.band_id, bm.user_id INTO v_test_band_id, v_test_user_id
  FROM band_members bm
  WHERE bm.status = 'active'
  LIMIT 1;

  IF v_test_band_id IS NULL THEN
    RAISE EXCEPTION 'PRE-DEPLOY TEST 1.1 FAILED: No active band member found';
  END IF;

  -- Simulate the user context (hack for testing — normally set by auth.uid())
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_test_user_id)::text, true);

  -- Call existing helper
  SELECT public.check_band_member(v_test_band_id) INTO v_result;

  IF v_result IS NOT TRUE THEN
    RAISE EXCEPTION 'PRE-DEPLOY TEST 1.1 FAILED: check_band_member should return TRUE for active member';
  END IF;

  RAISE NOTICE 'PRE-DEPLOY TEST 1.1 PASSED: check_band_member works for active member';
END $$;
```

#### Tier 1.2: Verify `contributor_permissions` table schema

```sql
-- PRE-DEPLOY TEST 1.2: Verify contributor_permissions has can_view_financials column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'contributor_permissions'
      AND column_name = 'can_view_financials'
  ) THEN
    RAISE EXCEPTION 'PRE-DEPLOY TEST 1.2 FAILED: contributor_permissions.can_view_financials column missing';
  END IF;

  RAISE NOTICE 'PRE-DEPLOY TEST 1.2 PASSED: contributor_permissions.can_view_financials exists';
END $$;
```

#### Tier 1.3: Verify `regenerate_calendar_token` exists in current form (about to be replaced)

```sql
-- PRE-DEPLOY TEST 1.3: Confirm current regenerate_calendar_token signature (1 param)
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS args,
  p.prosecdef AS is_security_definer
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'regenerate_calendar_token';

-- Expected: regenerate_calendar_token(p_user_id uuid), is_security_definer = true
-- If not found or signature is different, FAIL — migration assumptions are wrong
```

---

### Tier 2 — Post-deployment (run AFTER `supabase db push` succeeds)

#### Tier 2.1: Verify `regenerate_calendar_token` signature unchanged + search_path added

```sql
-- POST-DEPLOY TEST 2.1: Verify signature unchanged (still has p_user_id) + search_path
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS args,
  p.prosecdef AS is_security_definer,
  pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'regenerate_calendar_token';

-- Expected: args = 'p_user_id uuid', is_security_definer = true, definition LIKE '%SET search_path = public%'
-- If not, FAIL
```

#### Tier 2.2: Verify `regenerate_calendar_token` auth check (IDOR fix)

```sql
-- POST-DEPLOY TEST 2.2: Verify function body contains auth check
SELECT
  pg_get_functiondef('public.regenerate_calendar_token(uuid)'::regprocedure) LIKE '%auth.uid()%' AS contains_auth_check,
  pg_get_functiondef('public.regenerate_calendar_token(uuid)'::regprocedure) LIKE '%Permission denied%' AS contains_exception;

-- Expected: both true
-- If false, FAIL — IDOR not fixed
```

#### Tier 2.3: Verify `check_financial_view_permission` helper exists + search_path

```sql
-- POST-DEPLOY TEST 2.3: Verify helper function exists
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS args,
  p.prosecdef AS is_security_definer,
  pg_get_functiondef(p.oid) LIKE '%SET search_path = public%' AS has_search_path
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'check_financial_view_permission';

-- Expected: args = 'p_band_id uuid', is_security_definer = true, has_search_path = true
-- If not found or incorrect, FAIL
```

#### Tier 2.4: Verify `financial_entries_select` policy uses new helper

```sql
-- POST-DEPLOY TEST 2.4: Verify SELECT policy references check_financial_view_permission
SELECT
  schemaname,
  tablename,
  policyname,
  qual::text AS using_clause
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'financial_entries'
  AND policyname = 'financial_entries_select';

-- Expected: using_clause LIKE '%check_financial_view_permission%'
-- If not, FAIL
```

#### Tier 2.5: Integration test — contributor with `can_view_financials = false` cannot SELECT

```sql
-- POST-DEPLOY TEST 2.5: Contributor with can_view_financials = false blocked
DO $$
DECLARE
  v_test_band_id UUID;
  v_contributor_user_id UUID;
  v_contributor_member_id UUID;
  v_result_count INT;
BEGIN
  -- Find a band with at least one financial entry
  SELECT DISTINCT band_id INTO v_test_band_id
  FROM financial_entries
  LIMIT 1;

  IF v_test_band_id IS NULL THEN
    RAISE NOTICE 'POST-DEPLOY TEST 2.5 SKIPPED: No financial entries found';
    RETURN;
  END IF;

  -- Create a test contributor user (or find existing)
  INSERT INTO users (id, first_name, last_name)
  VALUES (gen_random_uuid(), 'Test', 'Contributor')
  RETURNING id INTO v_contributor_user_id;

  -- Add as contributor with can_view_financials = false
  INSERT INTO band_members (id, band_id, user_id, role, status)
  VALUES (gen_random_uuid(), v_test_band_id, v_contributor_user_id, 'contributor', 'active')
  RETURNING id INTO v_contributor_member_id;

  INSERT INTO contributor_permissions (band_member_id, can_view_financials)
  VALUES (v_contributor_member_id, FALSE);

  -- Simulate contributor auth context
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_contributor_user_id)::text, true);

  -- Attempt SELECT (should return 0 rows due to RLS)
  SELECT COUNT(*) INTO v_result_count
  FROM financial_entries
  WHERE band_id = v_test_band_id;

  -- Cleanup
  DELETE FROM contributor_permissions WHERE band_member_id = v_contributor_member_id;
  DELETE FROM band_members WHERE id = v_contributor_member_id;
  DELETE FROM users WHERE id = v_contributor_user_id;

  IF v_result_count > 0 THEN
    RAISE EXCEPTION 'POST-DEPLOY TEST 2.5 FAILED: Contributor with can_view_financials=false can still SELECT (got % rows)', v_result_count;
  END IF;

  RAISE NOTICE 'POST-DEPLOY TEST 2.5 PASSED: Contributor with can_view_financials=false blocked from SELECT';
END $$;
```

#### Tier 2.6: Integration test — admin/member can SELECT financial entries

```sql
-- POST-DEPLOY TEST 2.6: Admin/member can SELECT financial entries
DO $$
DECLARE
  v_test_band_id UUID;
  v_admin_user_id UUID;
  v_result_count INT;
BEGIN
  -- Find a band with at least one financial entry
  SELECT DISTINCT band_id INTO v_test_band_id
  FROM financial_entries
  LIMIT 1;

  IF v_test_band_id IS NULL THEN
    RAISE NOTICE 'POST-DEPLOY TEST 2.6 SKIPPED: No financial entries found';
    RETURN;
  END IF;

  -- Find an admin or member in that band
  SELECT bm.user_id INTO v_admin_user_id
  FROM band_members bm
  WHERE bm.band_id = v_test_band_id
    AND bm.role IN ('admin', 'member')
    AND bm.status = 'active'
  LIMIT 1;

  IF v_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'POST-DEPLOY TEST 2.6 FAILED: No admin/member found in test band';
  END IF;

  -- Simulate admin/member auth context
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_user_id)::text, true);

  -- Attempt SELECT (should succeed)
  SELECT COUNT(*) INTO v_result_count
  FROM financial_entries
  WHERE band_id = v_test_band_id;

  IF v_result_count = 0 THEN
    RAISE EXCEPTION 'POST-DEPLOY TEST 2.6 FAILED: Admin/member cannot SELECT financial entries';
  END IF;

  RAISE NOTICE 'POST-DEPLOY TEST 2.6 PASSED: Admin/member can SELECT financial entries (% rows)', v_result_count;
END $$;
```

#### Tier 2.7: Verify restored setlist RPCs exist + search_path

```sql
-- POST-DEPLOY TEST 2.7: Verify all 4 setlist RPCs exist with SET search_path
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS args,
  p.prosecdef AS is_security_definer,
  pg_get_functiondef(p.oid) LIKE '%SET search_path = public%' AS has_search_path
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('reorder_setlist_songs', 'reorder_setlist_items', 'add_special_item_to_setlist', 'delete_setlist');

-- Expected: 4 rows, all with is_security_definer = true, has_search_path = true
-- If any missing or incorrect, FAIL
```

#### Tier 2.8: Verify destructive RPCs have PUBLIC revoked

```sql
-- POST-DEPLOY TEST 2.8: Verify anon cannot execute destructive RPCs
SELECT
  p.proname,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('delete_band', 'update_member_role', 'remove_band_member', 'delete_user_account');

-- Expected: all rows have anon_can_execute = false, authenticated_can_execute = true
-- If any anon_can_execute = true, FAIL
```

#### Tier 2.9: Integration test — setlist reorder RPC (smoke test)

```sql
-- POST-DEPLOY TEST 2.9: Smoke test reorder_setlist_songs RPC
DO $$
DECLARE
  v_test_setlist_id UUID;
  v_row_ids UUID[];
  v_response JSONB;
BEGIN
  -- Find a setlist with at least 2 songs
  SELECT ss.setlist_id, ARRAY_AGG(ss.id ORDER BY ss.position) INTO v_test_setlist_id, v_row_ids
  FROM setlist_songs ss
  GROUP BY ss.setlist_id
  HAVING COUNT(*) >= 2
  LIMIT 1;

  IF v_test_setlist_id IS NULL THEN
    RAISE NOTICE 'POST-DEPLOY TEST 2.9 SKIPPED: No setlist with >=2 songs found';
    RETURN;
  END IF;

  -- Reverse the order
  v_row_ids := ARRAY(SELECT unnest(v_row_ids) ORDER BY 1 DESC);

  -- Call RPC (note: this will actually reorder the setlist — acceptable for testing)
  SELECT public.reorder_setlist_songs(v_test_setlist_id, v_row_ids) INTO v_response;

  IF v_response->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'POST-DEPLOY TEST 2.9 FAILED: RPC returned success=false: %', v_response->>'error';
  END IF;

  RAISE NOTICE 'POST-DEPLOY TEST 2.9 PASSED: reorder_setlist_songs RPC callable (reordered % songs)', v_response->>'reordered_count';
END $$;
```

#### Tier 2.10: Production verification — no orphaned financial entries visible to contributors

```sql
-- POST-DEPLOY TEST 2.10: Confirm no contributor can see entries they shouldn't
SELECT
  bm.band_id,
  bm.user_id,
  COUNT(fe.id) AS visible_entries,
  cp.can_view_financials
FROM band_members bm
JOIN contributor_permissions cp ON cp.band_member_id = bm.id
LEFT JOIN financial_entries fe ON fe.band_id = bm.band_id
WHERE bm.role = 'contributor'
  AND bm.status = 'active'
  AND cp.can_view_financials = FALSE
GROUP BY bm.band_id, bm.user_id, cp.can_view_financials
HAVING COUNT(fe.id) > 0;

-- Expected: 0 rows (contributors with can_view_financials=false should not see any entries)
-- If any rows returned, INVESTIGATE — RLS policy may not be working
```

---

## QA Regression Areas

### Primary validation (must test):

1. **Calendar token regeneration** — verify user can regenerate their own token, verify URL updates correctly, verify cannot regenerate another user's token
2. **Financial entry access (contributor)** — create contributor with `can_view_financials = false`, verify they cannot see financial entries in UI or via direct API call
3. **Financial entry access (admin/member)** — verify admin and member can still view/create/edit/delete financial entries
4. **Setlist reordering** — drag-and-drop reorder songs in a setlist, verify positions persist after reload, test with 2+ songs and 10+ songs
5. **Special item insertion** — add set break or pause to setlist, verify it appears in correct position, verify reordering still works
6. **Band deletion (admin)** — verify admin can still delete band
7. **Member role change (admin)** — verify admin can promote/demote members, verify contributor permissions save correctly when assigning contributor role
8. **Member removal (admin)** — verify admin can remove members (not self)
9. **User account deletion** — verify user can delete their own account via Settings

### Regression coverage (spot-check):

10. **Gig creation** — verify gigs can still be created, no permission errors
11. **Rehearsal creation** — verify rehearsals can still be created
12. **Setlist CRUD** — create, view, edit, delete setlists
13. **Song CRUD** — add song to catalog, edit BPM/tuning inline, delete from setlist
14. **Catalog integrity** — verify Catalog setlist cannot be deleted, verify duplicate song detection still works

---

## Rollout / Migration Strategy

### Deployment steps:

1. Engineer creates 5 migration files locally
2. Engineer validates migrations via Tier 1 tests (pre-deploy)
3. Manager reviews migration SQL for correctness
4. Engineer runs `supabase db push --linked` (or `supabase db query --linked -f <migration>` if push blocked per repo memory)
5. Engineer runs Tier 2 tests (post-deploy) immediately after push succeeds
6. QA performs regression testing per "QA Regression Areas"
7. Manager gates commit until QA APPROVED

### Rollback plan:

- If Tier 2 tests fail, do NOT proceed to QA
- Revert via new "undo" migrations (never modify applied migrations)
- Escalate to Manager if rollback is complex

### Migration order:

**Critical:** Migrations must apply in numeric order (120000 → 120001 → 120002 → 120003 → 120004). Do NOT reorder. Each migration is independent but logically builds on the previous one's assumptions.

---

## Out of Scope

1. **The other 55 `SECURITY DEFINER` functions callable by `anon`** — flagged for follow-up ticket, not addressed here
2. **Client-side refactoring of deprecated `regenerateToken()` method** — exists at `lib/features/calendar/calendar_subscription_service.dart:224-227` but is currently uncalled; removing it or updating call sites is out of scope (backend fix closes IDOR regardless of client behavior)
3. **Web push notifications** — not implemented, no changes needed
4. **macOS push notifications** — not implemented, no changes needed
5. **Other RLS policy gaps** — this ticket only addresses `financial_entries_select`, other tables not in scope
6. **Performance optimization** — migrations are correctness-focused, not performance-focused
7. **Test data cleanup** — Tier 2 tests clean up after themselves where possible, but pre-existing test data is not modified

---

**END OF ARCHITECT_PLAN.md**
