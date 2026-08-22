# Architect Plan — feature/security-definer-revoke-public

## Feature Slug

`feature/security-definer-revoke-public`

## Problem Summary

Every SECURITY DEFINER function in BandRoadie is created with PostgreSQL's default behavior: EXECUTE is auto-granted to PUBLIC on creation. The migration convention has been to add `GRANT EXECUTE ... TO authenticated` when shipping a new RPC, but never pair it with `REVOKE EXECUTE ... FROM PUBLIC, anon`. Since PUBLIC includes `anon`, every SECURITY DEFINER function ships anon-executable by default — allowing unauthenticated access unless someone remembers to revoke it, which nobody has.

Post-implementation Manager gate review identified **58 anon-executable SECURITY DEFINER function signatures** representing **56 unique function names**. Two names (`is_band_admin`, `update_band_calendar_preferences`) have overloaded signatures — each overload requires a separate revoke. This is a process gap that adds a new function to the backlog every time a feature ships an RPC without the revoke/grant pairing.

While a prior audit (2026-08-17) verified these functions are internally fail-closed (not directly exploitable today), relying on internal logic instead of the permission system is fragile, especially given the pace of new RPC deployment.

## Root Cause

**Cause:** PostgreSQL grants `EXECUTE` to `PUBLIC` by default when a function is created. The project's migration convention adds `GRANT EXECUTE ... TO authenticated` but never includes the corresponding `REVOKE EXECUTE ... FROM PUBLIC, anon` statement. Since `PUBLIC` includes the `anon` role, every new SECURITY DEFINER function ships with anon-executable permissions inherited from PUBLIC.

**Additional mechanism discovered (CLASSIFICATION_NOTES.md §4a):** Three functions (`accept_band_invite`, `create_band`, `is_band_member`) have explicit, direct `GRANT EXECUTE ... TO anon` statements with no PUBLIC grantee present. For these, a `REVOKE FROM PUBLIC` alone will not close the gap — anon must be explicitly named in the revoke.

**Critical for rollback planning:** The 56 functions in scope have two distinct grant patterns:

- **53 functions:** Inherit anon access from the PUBLIC default grant
- **3 functions:** Have explicit, direct `GRANT EXECUTE ... TO anon` with no PUBLIC grant

Any rollback plan must restore the exact pre-migration state per function, not use a blanket template.

**Confidence:** `HIGH` — confirmed via live `pg_proc.proacl` inspection documented in CLASSIFICATION_NOTES.md §4a and PRE_MIGRATION_ACL_STATE.md, pattern analysis of 54 migration files containing SECURITY DEFINER functions, and post-implementation verification via live production query (2026-08-22).

## Reference Docs Consulted

- `docs/features/security-definer-revoke-public/CLASSIFICATION_NOTES.md` — Manager-led investigation of all 56 functions, live ACL state, RLS policy cross-reference, and Flutter/edge function call-site verification
- No security/RLS-specific reference documentation exists in `docs/reference/` — this gap is noted and documented in this plan

## Existing System Analysis

### Current Grant Pattern (Observed in Migrations)

Typical pattern across 46+ migrations:

```sql
CREATE OR REPLACE FUNCTION some_function(...)
RETURNS ...
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- function body with auth.uid() checks
END;
$$;

GRANT EXECUTE ON FUNCTION some_function(...) TO authenticated;
```

**What's missing:** `REVOKE EXECUTE ON FUNCTION some_function(...) FROM PUBLIC, anon;` before the GRANT.

**Result:** The function remains executable by `anon` (unauthenticated users) via the PUBLIC default grant, even though only authenticated users should have access.

### Exception Cases Documented

Only 4 migrations correctly revoke PUBLIC before granting:

1. `20260328000000_accept_band_invite_rpc.sql` — revokes PUBLIC, grants to `service_role` only
2. `20260814120004_revoke_anon_destructive_rpcs.sql` — revokes PUBLIC and anon from 4 destructive functions
3. `20260821120000_add_band_export_authorization.sql` — revokes PUBLIC, grants to authenticated
4. `20260821120001_revoke_anon_check_band_export_permission.sql` — follow-up to add explicit anon revoke

### Function Categories (from CLASSIFICATION_NOTES.md §3)

**Category A: Trigger-bound (16 functions) — Zero risk, pure hygiene cleanup**

- `auto_create_catalog_for_band`, `handle_new_user`, `handle_new_user_profile`, `notify_blockout_created`, `notify_gig_created`, `notify_new_band_member`, `notify_rehearsal_created`, `prevent_catalog_deletion`, `prevent_catalog_rename`, `reorder_setlist_positions`, `sync_gig_location_from_venue`, `sync_gig_pay_from_financial_entry`, `trigger_recompute_setlist_stats`, `trigger_send_push_notification`, `update_setlist_duration`, `update_song_notes_updated_at`
- Return type `trigger` — PostgreSQL refuses to invoke these outside trigger context
- Anon grant is inert; revoke is pure hygiene

**Category B: RLS/Permission helpers (9 names, 10 signatures) — No anon dependency**

- `check_band_member`, `check_financial_view_permission`, `check_gig_response_access`, `check_rehearsal_response_access`, `is_band_admin` (2 overloads), `is_band_member`, `is_band_member_with_role`, `get_bandmate_user_ids`, `get_user_band_ids`
- Used in RLS policies USING clauses
- All RLS policies gate on `auth.uid()` matching, so anon gets zero rows regardless
- **Note:** 4 of these accept arbitrary user_id parameters without verifying they match `auth.uid()` — information disclosure risk when anon-callable. Revoking anon fixes the immediate exposure; parameter design question is out of scope.

**Category C: Action/mutation functions with verified internal auth checks (~21 functions)**

- `bulk_add_songs_to_setlist`, `clear_song_metadata`, `create_band`, `create_venue_for_gig_save`, `delete_setlist`, `delete_song_from_catalog`, `delete_song_from_setlist`, `get_or_create_calendar_preferences`, `get_or_create_notification_preferences`, `get_unread_notification_count`, `mark_all_notifications_read`, `move_song_between_setlists`, `reorder_band_members`, `reorder_setlists`, `restore_band_members`, `update_calendar_preferences`, `update_song_metadata`, `upsert_device_token`, and others
- All check `auth.uid()` is non-null and caller is an active band member before mutating
- Safe to revoke anon

**Category D: Previously hypothesized "must stay anon" — both disproven**

- `accept_band_invite` — called only by accept-invite edge function via service_role, not anon key
- Calendar token functions — called only from logged-in app via authenticated client
- `calendar-feed` edge function uses raw table selects via service_role, not RPCs
- Safe to revoke anon from all

**Category E: Functions with NO internal authorization check — out of scope for body changes**

- `add_special_item_to_setlist`, `ensure_catalog_setlist`, `increment_setlist_positions`, `reorder_setlist_items`, `reorder_setlist_songs` (5 distinct functions)
- Real cross-tenant data-tampering path for any authenticated user
- Revoking anon is appropriate and will be done, but these need body changes in a separate feature
- See Out of Scope section

**Category F: Manager gate correction — missed notification/stats functions (2 functions)**

- `notify_band_members` — called internally by `notify_gig_created`, `notify_rehearsal_created`, and `notify_blockout_created` (all SECURITY DEFINER), but also directly callable via PostgREST. No internal authorization check — anon can inject arbitrary notification (attacker-controlled title/body) into any band's members' feeds for any `p_band_id`.
- `recompute_setlist_stats` — called internally by `trigger_recompute_setlist_stats` (SECURITY DEFINER), but also directly callable. Anon can force-recompute any setlist's duration from existing data (low impact, still an unauthenticated write path outside intended boundary).
- Both return `void`, not `trigger`, so they are directly RPC-callable
- Both are called internally from SECURITY DEFINER functions, so internal calls are unaffected by revoking PUBLIC/anon (internal calls run as function owner)

### Direct Anon Grant Cases (3 functions)

From CLASSIFICATION_NOTES.md §4a:

- `accept_band_invite`, `create_band`, `is_band_member`
- Have explicit `GRANT EXECUTE ... TO anon` with no PUBLIC grantee
- `REVOKE FROM PUBLIC` alone will not close the gap — must explicitly target anon

## Proposed Solution

### Core Changes

1. **Batch migrations to revoke anon/PUBLIC execute from all 56 unique function names (58 exact signatures including overloads)**
   - Each REVOKE must explicitly target both `PUBLIC` and `anon` for every function signature
   - Use exact signature via `pg_get_function_identity_arguments()` to handle overloads correctly
   - Re-grant to authenticated where appropriate (all non-trigger, non-service-role-only functions)
2. **Capture exact pre-migration ACL state before Batch 1 runs**
   - Query `pg_proc.proacl` for all 58 signatures before any changes
   - Document which functions have PUBLIC grants vs. direct anon grants vs. both
   - Use this captured state as the rollback source of truth (not assumptions or templates)
3. **Update GUARDRAILS.md §4 to mandate revoke/grant pairing and proper ACL verification discipline**
   - Add explicit rule: "When adding SECURITY DEFINER functions, always include `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon` before targeted GRANT"
   - Add ACL discipline note: determining effective privilege must use `has_function_privilege(role, oid, 'EXECUTE')`, never string-matching the raw ACL array for a named grantee — a PUBLIC grant makes every role's effective privilege `true` even with no explicit named entry
   - Reference this feature as the correction of the historical backlog

### Batching Strategy

Migrations will be split into functional batches to minimize blast radius and enable granular rollback:

**Batch 1: Trigger-bound functions (16)**

- Zero functional risk — inert anon grants
- Validates migration mechanics with no user-facing impact

**Batch 2: RLS/permission helper functions (10 signatures)**

- Low risk — RLS policies already gate on auth.uid()
- Critical for financial_entries RBAC

**Batch 3: Calendar and invite functions (7 signatures)**

- `accept_band_invite`, `get_band_calendar_token`, `get_my_calendar_token`, `regenerate_band_calendar_token`, `regenerate_calendar_token`, `update_band_calendar_preferences` (both overloads)
- Previously hypothesized as "must stay anon" but verified safe to revoke

**Batch 4: Notification and preference functions (6)**

- `get_or_create_notification_preferences`, `get_or_create_calendar_preferences`, `update_calendar_preferences`, `get_unread_notification_count`, `mark_all_notifications_read`, `upsert_device_token`

**Batch 5: Setlist mutation functions (5 distinct function names)**

- `add_special_item_to_setlist`, `ensure_catalog_setlist`, `increment_setlist_positions`, `reorder_setlist_items`, `reorder_setlist_songs`
- Includes the Category E functions (no internal auth check) — revoking anon is correct, but they need follow-up body changes

**Batch 6: Song and setlist management functions (~9)**

- `delete_setlist`, `reorder_setlists`, `move_song_between_setlists`, `bulk_add_songs_to_setlist`, `update_song_metadata`, `clear_song_metadata`, `delete_song_from_catalog`, and remaining setlist operations

**Batch 7: Band and member management functions (~5)**

- `create_band`, `restore_band_members`, `reorder_band_members`, `create_venue_for_gig_save`, and any remaining uncategorized functions

**Batch 8: Missed notification and stats functions (2) — Manager gate correction**

- `notify_band_members` — no internal auth check, anon can inject arbitrary notifications
- `recompute_setlist_stats` — anon can force-recompute any setlist's stats
- Both are void-returning SECURITY DEFINER functions callable via PostgREST RPC
- Both have internal callers (SECURITY DEFINER trigger functions) unaffected by this revoke

### Migration Template (per batch)

```sql
-- ============================================================================
-- Revoke anon/PUBLIC execute from [Batch Name]
-- ============================================================================
-- Feature: security-definer-revoke-public
-- Issue: PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION
-- Risk: Anon role can call functions that should require authentication
-- Fix: Explicit revoke from PUBLIC and anon, grant only to authenticated
-- ============================================================================

-- Function 1
REVOKE ALL ON FUNCTION function_name(arg_types) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION function_name(arg_types) TO authenticated;

-- Function 2 (overloaded example)
REVOKE ALL ON FUNCTION function_name(other_arg_types) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION function_name(other_arg_types) TO authenticated;

-- Trigger-bound functions: revoke only, no re-grant (not user-callable)
REVOKE ALL ON FUNCTION trigger_function_name() FROM PUBLIC, anon;

-- ===========================================================================
-- ROLLBACK (restore exact pre-migration ACL state from captured baseline)
-- ===========================================================================
-- For functions with PUBLIC grant (majority):
-- GRANT EXECUTE ON FUNCTION function_name(arg_types) TO PUBLIC;
--
-- For functions with direct anon grant (accept_band_invite, create_band, is_band_member):
-- GRANT EXECUTE ON FUNCTION function_name(arg_types) TO anon;
--
-- Refer to PRE_MIGRATION_ACL_STATE.md for exact restore commands per signature
```

### Verification Approach

**Direct-to-production deployment with per-batch production verification** — batches applied sequentially to production, with immediate post-deployment privilege checks and manual smoke tests after each batch before proceeding to the next.

**Critical verification requirements:**

1. **Both PUBLIC and anon must be checked explicitly** — most functions inherit anon via PUBLIC, not direct grants
2. **Pre-migration ACL capture is mandatory** — rollback must restore exact state, not use templates
3. **Privilege checks must query by exact signature** — overloads must be distinguished
4. **Use `has_function_privilege(role, oid, 'EXECUTE')` for all privilege verification** — never string-match the raw ACL array, as a PUBLIC grant makes every role's effective privilege `true` even with no explicit named entry

## Database Impact

**Migrations:** 8 new migration files (one per batch) — `20260822120000_revoke_anon_batch_1_triggers.sql` through `20260822120007_revoke_anon_batch_8_notifications_setlist_stats.sql`

**RLS Policies:** Not modified — affected (2 policies reference `check_band_member`, 1 references `check_financial_view_permission`), but only via function calls in USING clauses. Since anon has no valid auth.uid(), RLS already returns zero rows; revoking anon execute on the helper functions adds defense-in-depth but does not change RLS behavior.

**RPC Functions:** Not modified — 58 signatures affected, but only ACL changes (REVOKE/GRANT), no signature or body changes.

**Triggers:** Not applicable — trigger-bound functions are included in the revoke for hygiene, but trigger invocation is unaffected (triggers don't use EXECUTE grants).

**Edge Functions:** Not modified — edge functions use service_role keys, which are unaffected by revokes targeting anon/PUBLIC. Affected: `accept-invite` (calls `accept_band_invite` via service_role), `calendar-feed` (uses raw selects, no RPC calls).

## Flutter Architecture Changes

None — this is a database-only change. No Dart code modifications required.

## Files to Create

| File                                                                               | Justification                                                                                              |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `docs/features/security-definer-revoke-public/PRE_MIGRATION_ACL_STATE.md`          | Captured baseline of exact ACL state for all 58 signatures before any migrations run — source of truth for rollback plans (will be updated to add 2 missed functions) |
| `supabase/migrations/20260822120000_revoke_anon_batch_1_triggers.sql`              | Batch 1: Trigger-bound functions (16)                                                                      |
| `supabase/migrations/20260822120001_revoke_anon_batch_2_rls_helpers.sql`           | Batch 2: RLS/permission helper functions (10 signatures)                                                   |
| `supabase/migrations/20260822120002_revoke_anon_batch_3_calendar_invite.sql`       | Batch 3: Calendar and invite functions (7 signatures)                                                      |
| `supabase/migrations/20260822120003_revoke_anon_batch_4_notifications.sql`         | Batch 4: Notification and preference functions (6)                                                         |
| `supabase/migrations/20260822120004_revoke_anon_batch_5_setlists.sql`              | Batch 5: Setlist mutation functions (5 distinct names)                                                     |
| `supabase/migrations/20260822120005_revoke_anon_batch_6_song_metadata.sql`         | Batch 6: Song and setlist management functions (~9)                                                        |
| `supabase/migrations/20260822120006_revoke_anon_batch_7_band_mgmt.sql`             | Batch 7: Band and member management functions (~5)                                                         |
| `supabase/migrations/20260822120007_revoke_anon_batch_8_notifications_setlist_stats.sql` | Batch 8: Missed notification and setlist-stats functions (2) — Manager gate correction               |

## Files to Modify

| File                                                             | What changes                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `docs/agents/GUARDRAILS.md`                                      | Add mandatory revoke/grant pairing rule to §4 (Supabase Safety), and ACL discipline note about `has_function_privilege()`: "When adding SECURITY DEFINER functions, always include `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon` before the targeted GRANT. Never rely on PostgreSQL's default PUBLIC grant for production functions. When verifying function ACLs, use `has_function_privilege(role, oid, 'EXECUTE')` — never string-match the raw ACL array for a named grantee, as a PUBLIC grant makes every role's effective privilege true even with no explicit named entry (caused incorrect 'special case' classification for `is_band_member_with_role` during this feature's implementation)." |
| `docs/features/security-definer-revoke-public/PRE_MIGRATION_ACL_STATE.md` | Append 2 rows for `notify_band_members` and `recompute_setlist_stats` with their exact ACL state captured via live query                                                                                                                                                                                                                                                                                                                             |

## Files Off-Limits

| File                                  | Reason                                                                      |
| ------------------------------------- | --------------------------------------------------------------------------- |
| All files under `lib/`                | Flutter code unchanged — database-only change                               |
| All files under `supabase/functions/` | Edge functions unchanged — use service_role keys unaffected by anon revokes |
| All existing migration files (20260822120000 through 20260822120006) | Approved migrations — do not modify |
| `lib/main.dart`                       | Init order must not change (GUARDRAILS.md §1)                               |

## System Impact Map

| System                                 | Impact                                                                                                                                                                  |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | Affected — RLS helper `check_band_member` used in gig queries; anon revoke adds defense-in-depth                                                                        |
| Rehearsals                             | Affected — RLS helper `check_band_member` used; `check_rehearsal_response_access` used in response logic                                                                |
| Setlists / Catalog                     | Affected — 5+ setlist mutation functions lose anon execute; authenticated flows unchanged                                                                               |
| Members / RBAC                         | Affected — `is_band_admin`, `is_band_member` helpers lose anon execute; authenticated authorization unchanged                                                           |
| Auth / Session                         | Unaffected — authentication flows use built-in Supabase auth, not these RPCs                                                                                            |
| Routing                                | Unaffected — no routing logic changes                                                                                                                                   |
| Notifications                          | Affected — 6 notification/preference functions plus `notify_band_members` lose anon execute; logged-in notification flows unchanged                                     |
| Calendar / Invites                     | Affected — calendar token and invite functions lose anon execute; authenticated invite acceptance and calendar subscription unchanged (edge functions use service_role) |
| Platform (iOS / Android / Web / macOS) | Affected (all) — all platforms depend on these RPCs, but no platform-specific regression expected (grant change only, authenticated flows preserved)                    |
| Financial Entries                      | Affected — `check_financial_view_permission` RLS helper loses anon execute; authenticated RBAC unchanged                                                                |

## Regression Risk

**Level:** `MEDIUM`

**Rationale:**

- **+Risk (HIGH):** Zero automated test coverage on repository/controller layer (0/18 repositories, 0/15 controllers per 2026-08-21 audit) — manual verification is the only safety net
- **+Risk (MEDIUM):** Known error-swallowing pattern in repositories (`catch (e) { return []; }`) — if this breaks an authenticated call path, likely symptom is empty data quietly, not visible error
- **+Risk (MEDIUM):** 56 unique functions affected — large surface area increases risk of missing an edge case despite classification pass
- **-Risk (LOW):** Defense-in-depth change, not live-exploit fix — functions are internally fail-closed (prior audit confirmed), so impact of missing a legitimate anon-access case is lower than if functions were currently exploitable
- **-Risk (LOW):** Batched migrations with per-batch production verification — each batch verified immediately after applying to production with privilege checks and smoke tests before next batch proceeds; granular single-statement rollback possible per batch
- **-Risk (LOW):** RLS policies unchanged — only RLS helper function grants modified; RLS logic itself unaffected
- **-Risk (LOW):** Edge functions use service_role — unaffected by anon revokes

**Risk is not HIGH because:**

- No schema changes, no RPC signature changes, no Flutter code changes
- Authenticated flows explicitly preserved in every migration (re-grant to authenticated)
- CLASSIFICATION_NOTES.md verified all 56 functions against actual call sites and found no legitimate anon-access case
- Trigger-bound functions (16) are inert — zero functional risk

**Risk is not LOW because:**

- Large surface (56 functions, 23 Flutter files, 9 RLS policies cross-referenced in classification)
- No automated test coverage to catch regressions
- Repositories may silently fail rather than throw visible errors
- Production verification is manual, not automated

## Engineer Task Breakdown

### Task 1: Capture Pre-Migration ACL State (MANDATORY — before any migrations)

**Goal:** Document exact pre-migration privilege state per function signature for rollback plan
**Steps:**

1. Connect to Supabase production
2. Query `pg_proc` joined with `pg_namespace` for all 56 function names (58 total signatures), retrieving exact signature and ACL:
   ```sql
   SELECT
     p.proname AS function_name,
     pg_get_function_identity_arguments(p.oid) AS signature,
     p.proacl AS acl_array,
     has_function_privilege('PUBLIC', p.oid, 'EXECUTE') AS public_has_execute,
     has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_has_execute
   FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public'
     AND p.prosecdef = true
     AND p.proname IN (
       'accept_band_invite', 'add_special_item_to_setlist', 'auto_create_catalog_for_band',
       'bulk_add_songs_to_setlist', 'check_band_member', 'check_financial_view_permission',
       'check_gig_response_access', 'check_rehearsal_response_access', 'clear_song_metadata',
       'create_band', 'create_venue_for_gig_save', 'delete_setlist', 'delete_song_from_catalog',
       'delete_song_from_setlist', 'ensure_catalog_setlist', 'get_band_calendar_token',
       'get_bandmate_user_ids', 'get_my_calendar_token', 'get_or_create_calendar_preferences',
       'get_or_create_notification_preferences', 'get_unread_notification_count',
       'get_user_band_ids', 'handle_new_user', 'handle_new_user_profile',
       'increment_setlist_positions', 'is_band_admin', 'is_band_member',
       'is_band_member_with_role', 'mark_all_notifications_read', 'move_song_between_setlists',
       'notify_band_members', 'notify_blockout_created', 'notify_gig_created', 'notify_new_band_member',
       'notify_rehearsal_created', 'prevent_catalog_deletion', 'prevent_catalog_rename',
       'recompute_setlist_stats', 'regenerate_band_calendar_token', 'regenerate_calendar_token',
       'reorder_band_members', 'reorder_setlist_items', 'reorder_setlist_positions',
       'reorder_setlist_songs', 'reorder_setlists', 'restore_band_members',
       'sync_gig_location_from_venue', 'sync_gig_pay_from_financial_entry',
       'trigger_recompute_setlist_stats', 'trigger_send_push_notification',
       'update_calendar_preferences', 'update_band_calendar_preferences',
       'update_setlist_duration', 'update_song_metadata', 'update_song_notes_updated_at',
       'upsert_device_token'
     )
   ORDER BY p.proname, signature;
   ```
3. **If `PRE_MIGRATION_ACL_STATE.md` already exists:** Read the existing file in full, verify `notify_band_members` and `recompute_setlist_stats` are missing, append 2 rows to the Complete ACL State table with their exact captured state, update Summary to reflect 58 signatures total. Re-read the file after edit to confirm no corruption.
4. **If file does not exist:** Create `docs/features/security-definer-revoke-public/PRE_MIGRATION_ACL_STATE.md` with all 58 signatures documented:
   - Has PUBLIC grant? (yes/no)
   - Has direct anon grant? (yes/no)
   - Expected rollback: `GRANT ... TO PUBLIC` vs. `GRANT ... TO anon` vs. both
5. Use this as source of truth for every batch's rollback script

### Task 2: Create Migration Batch 1 (Trigger-bound functions)

**Goal:** Revoke anon/PUBLIC from 16 trigger-bound functions
**Steps:**

1. Create `supabase/migrations/20260822120000_revoke_anon_batch_1_triggers.sql`
2. For each of 16 trigger-bound functions, add:
   ```sql
   REVOKE ALL ON FUNCTION function_name() FROM PUBLIC, anon;
   ```
3. Do not re-grant (trigger functions not user-callable)
4. Include rollback block at bottom using exact ACL state from Task 1
5. Apply to production
6. Run Tier 2 verification immediately (see Verification Plan — post-deployment privilege checks and smoke tests)

### Task 3: Create Migration Batch 2 (RLS helpers)

**Goal:** Revoke anon/PUBLIC from 10 RLS/permission helper signatures
**Steps:**

1. Create `supabase/migrations/20260822120001_revoke_anon_batch_2_rls_helpers.sql`
2. For each signature (including both `is_band_admin` overloads):
   ```sql
   REVOKE ALL ON FUNCTION function_name(arg_types) FROM PUBLIC, anon;
   GRANT EXECUTE ON FUNCTION function_name(arg_types) TO authenticated;
   ```
3. Handle overloads explicitly with full arg list
4. Include rollback block using exact ACL state from Task 1
5. Apply to production, run Tier 2 verification immediately

### Task 4: Create Migration Batch 3 (Calendar/Invite)

**Goal:** Revoke anon/PUBLIC from 7 calendar and invite function signatures
**Steps:**

1. Create `supabase/migrations/20260822120002_revoke_anon_batch_3_calendar_invite.sql`
2. Revoke from all 7 signatures
3. **Special handling for `accept_band_invite`:** already has service_role-only grant; confirm no authenticated re-grant (keep service_role-only)
4. Include rollback block using exact ACL state from Task 1
5. Apply to production, run Tier 2 verification immediately
6. **Critical smoke test:** Invite acceptance end-to-end, calendar URL fetch

### Task 5: Create Migration Batch 4 (Notifications)

**Goal:** Revoke anon/PUBLIC from 6 notification/preference functions
**Steps:**

1. Create `supabase/migrations/20260822120003_revoke_anon_batch_4_notifications.sql`
2. Revoke and re-grant for all 6
3. Include rollback block using exact ACL state from Task 1
4. Apply to production, run Tier 2 verification immediately

### Task 6: Create Migration Batch 5 (Setlists)

**Goal:** Revoke anon/PUBLIC from 5 distinct setlist mutation function names
**Steps:**

1. Create `supabase/migrations/20260822120004_revoke_anon_batch_5_setlists.sql`
2. Revoke and re-grant for all 5 distinct names:
   - `add_special_item_to_setlist`
   - `ensure_catalog_setlist`
   - `increment_setlist_positions`
   - `reorder_setlist_items`
   - `reorder_setlist_songs`
3. Include rollback block using exact ACL state from Task 1
4. Apply to production, run Tier 2 verification immediately

### Task 7: Create Migration Batch 6 (Song/Setlist Management)

**Goal:** Revoke anon/PUBLIC from ~9 song and setlist management functions
**Steps:**

1. Create `supabase/migrations/20260822120005_revoke_anon_batch_6_song_metadata.sql`
2. Revoke and re-grant for all functions in this category
3. Include rollback block using exact ACL state from Task 1
4. Apply to production, run Tier 2 verification immediately

### Task 8: Create Migration Batch 7 (Band/Member Management)

**Goal:** Revoke anon/PUBLIC from remaining ~5 functions
**Steps:**

1. Create `supabase/migrations/20260822120006_revoke_anon_batch_7_band_mgmt.sql`
2. Revoke and re-grant for `create_band`, `restore_band_members`, `reorder_band_members`, `create_venue_for_gig_save`, and any remaining
3. **Special handling for `create_band`:** has direct anon grant (per §4a) — ensure explicit anon revoke and rollback restores `GRANT ... TO anon` not PUBLIC
4. Include rollback block using exact ACL state from Task 1
5. Apply to production, run Tier 2 verification immediately

### Task 8a: Create Migration Batch 8 (Missed notification/stats functions) — Manager Gate Correction

**Goal:** Revoke anon/PUBLIC from 2 missed functions (`notify_band_members`, `recompute_setlist_stats`)
**Steps:**

1. Create `supabase/migrations/20260822120007_revoke_anon_batch_8_notifications_setlist_stats.sql` with the following content:

```sql
-- ============================================================================
-- BATCH 8: Revoke anon/PUBLIC execute from previously-missed notification and
-- setlist-stats functions (Manager gate correction — coverage gap found in
-- post-implementation verification, not in original classification)
-- ============================================================================
-- Feature: security-definer-revoke-public
-- Issue: PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION
-- Risk: Anon role can call notify_band_members (no internal auth check — can
-- inject arbitrary notifications into any band) and recompute_setlist_stats
-- Fix: Explicit revoke from PUBLIC and anon, re-grant to authenticated
--
-- SAFETY: Both functions are also called internally by SECURITY DEFINER
-- trigger functions already covered in Batch 1 (notify_band_members from
-- notify_gig_created, notify_rehearsal_created, and notify_blockout_created;
-- recompute_setlist_stats from trigger_recompute_setlist_stats). Internal
-- calls run as function owner and are unaffected by this revoke.
-- ============================================================================

-- Function 1: notify_band_members
REVOKE ALL ON FUNCTION notify_band_members(p_band_id uuid, p_actor_user_id uuid, p_notification_type text, p_title text, p_body text, p_metadata jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION notify_band_members(p_band_id uuid, p_actor_user_id uuid, p_notification_type text, p_title text, p_body text, p_metadata jsonb) TO authenticated;

-- Function 2: recompute_setlist_stats
REVOKE ALL ON FUNCTION recompute_setlist_stats(p_setlist_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION recompute_setlist_stats(p_setlist_id uuid) TO authenticated;

-- ===========================================================================
-- ROLLBACK (restore exact pre-migration ACL state)
-- ===========================================================================
-- Both functions had PUBLIC grant in pre-migration state (confirmed via live
-- proacl query 2026-08-22). To rollback:
--
-- GRANT EXECUTE ON FUNCTION notify_band_members(p_band_id uuid, p_actor_user_id uuid, p_notification_type text, p_title text, p_body text, p_metadata jsonb) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION recompute_setlist_stats(p_setlist_id uuid) TO PUBLIC;
```

2. Include rollback block using exact ACL state from Task 1 (updated file)
3. Apply to production, run Tier 2 verification immediately

### Task 9: Update GUARDRAILS.md

**Goal:** Add mandatory revoke/grant pairing rule and ACL discipline note to prevent regression
**Steps:**

1. Open `docs/agents/GUARDRAILS.md`
2. Locate §4 (Supabase Safety) → "ACL discipline (function grants)" bullet
3. Update the existing ACL discipline bullet to include the `has_function_privilege()` guidance:
   ```markdown
   - **ACL discipline (function grants):** PostgreSQL grants EXECUTE to PUBLIC by default on `CREATE FUNCTION`. Always pair `REVOKE ALL FROM PUBLIC, anon` with explicit `GRANT EXECUTE ... TO authenticated` (or service_role for backend-only functions). Never leave anon-callable functions unless explicitly required for public endpoints. Migrations that modify function ACLs must document exact pre-migration state for rollback (see `feature/security-definer-revoke-public/PRE_MIGRATION_ACL_STATE.md` pattern). When verifying function ACLs, use `has_function_privilege(role, oid, 'EXECUTE')` — never string-match the raw ACL array for a named grantee, as a PUBLIC grant makes every role's effective privilege true even with no explicit named entry (this caused an incorrect "special case" classification for `is_band_member_with_role` during this feature's implementation).
   ```
4. Commit with all migrations

### Task 10: Post-Batch Verification (Production)

**Goal:** Confirm all 8 batches applied successfully to production
**Steps:**

1. After each batch is applied to production, Manager runs the privilege sweep for that batch's functions: confirm anon and PUBLIC EXECUTE removed, authenticated present (except service_role-only functions)
2. Engineer/Tony spot-check the affected app flow (e.g., after Batch 4, test notification preferences save/fetch)
3. After all 8 batches complete, run comprehensive privilege inventory for all 58 signatures (see Verification Plan POST-DEPLOY TEST 4)
4. Check production Supabase Advisors: confirm `anon_security_definer_function_executable` finding count drops to 0
5. Export post-migration ACL state to `docs/features/security-definer-revoke-public/POST_MIGRATION_ACL_STATE.md`

### Task 11: Production Deployment

**Goal:** Apply all 8 migrations to production
**Gate:** Manager approval after `QA_REPORT.md` is APPROVED (per `COMMIT_GATE.md` and `GUARDRAILS.md` §11) and per-batch production verification passes
**Steps:**

1. Confirm QA approval complete (see QA Regression Areas)
2. Merge feature branch to main
3. Run `supabase db push` against production project (applies all 8 migrations sequentially)
4. Monitor for errors during push
5. Run POST-DEPLOY TEST 4 (comprehensive privilege inventory): confirm changes applied
6. Check production Supabase Advisors: confirm 58→0 drop
7. If any migration fails mid-push, Supabase will halt and not apply remaining migrations — diagnose specific batch failure and execute rollback for applied batches if needed

### Task 12: Write ENGINEER_REPORT.md

**Goal:** Document implementation and verification results
**Steps:**

1. Create `docs/features/security-definer-revoke-public/ENGINEER_REPORT.md`
2. Include: task completion checklist (all 12 tasks + Task 8a), pre/post ACL diffs, advisor findings diff (58→0), manual smoke test results per batch, production verification query results
3. Flag any deviations from plan
4. Confirm `flutter analyze` passes (expect 0 Dart changes)
5. Generate `git diff` for review

## Verification Plan

### Tier 1 — Pre-Deployment (Static/Logic Verification)

Must pass before any production deployment. All tests runnable with zero live database changes.

**Static Review Tests:**

1. **SQL syntax validation:** Each migration file must parse without errors
2. **Signature matching:** Verify each REVOKE/GRANT statement targets a signature documented in `PRE_MIGRATION_ACL_STATE.md`
3. **Rollback completeness:** Verify every migration's rollback block references the exact pre-migration ACL state per function (PUBLIC vs. anon grant pattern)
4. **Overload handling:** Confirm `is_band_admin` (2 overloads) and `update_band_calendar_preferences` (2 overloads) each have 2 distinct REVOKE/GRANT pairs with full signatures
5. **Batch count reconciliation:** 8 batches × 56 unique function names = 58 total signatures (accounting for 2 overloaded functions with 2 signatures each)

**Manual Code Review (pre-deployment):**

- Read each migration file: confirm no typos in function names, confirm exact signature match to `PRE_MIGRATION_ACL_STATE.md`
- Confirm Batch 8 includes `notify_band_members` and `recompute_setlist_stats` with correct signatures

### Tier 2 — Post-Deployment (After Each Batch, Direct to Production)

Run immediately after each `supabase db push` to production.

```sql
-- POST-DEPLOY TEST 1: Verify PUBLIC and anon both removed (example for Batch 1)
-- CRITICAL: Check both PUBLIC and anon explicitly — most functions inherit via PUBLIC, not direct grants
SELECT
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS signature,
  has_function_privilege('PUBLIC', p.oid, 'EXECUTE') AS public_has_execute,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_has_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_has_execute
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('auto_create_catalog_for_band', 'handle_new_user',
                    'handle_new_user_profile', 'notify_blockout_created',
                    'notify_gig_created', 'notify_new_band_member',
                    'notify_rehearsal_created', 'prevent_catalog_deletion',
                    'prevent_catalog_rename', 'reorder_setlist_positions',
                    'sync_gig_location_from_venue', 'sync_gig_pay_from_financial_entry',
                    'trigger_recompute_setlist_stats', 'trigger_send_push_notification',
                    'update_setlist_duration', 'update_song_notes_updated_at')
ORDER BY p.proname, signature;
-- Expect: public_has_execute = false, anon_has_execute = false for all
-- authenticated_has_execute = false for trigger functions (not user-callable)
-- Repeat for each batch with appropriate function list
```

```sql
-- POST-DEPLOY TEST 2: Verify overloaded functions both revoked (Batch 2)
SELECT
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS signature,
  has_function_privilege('PUBLIC', p.oid, 'EXECUTE') AS public_has_execute,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_has_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_has_execute
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('is_band_admin', 'update_band_calendar_preferences')
ORDER BY p.proname, signature;
-- Expect: 2 rows for is_band_admin, 2 rows for update_band_calendar_preferences
-- All: public_has_execute = false, anon_has_execute = false, authenticated_has_execute = true
```

```sql
-- POST-DEPLOY TEST 3: Verify direct anon grant functions explicitly revoked (Batches 3 & 7)
SELECT
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS signature,
  p.proacl AS acl_array,
  has_function_privilege('PUBLIC', p.oid, 'EXECUTE') AS public_has_execute,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_has_execute
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('accept_band_invite', 'create_band', 'is_band_member')
ORDER BY p.proname, signature;
-- Expect: Both public_has_execute and anon_has_execute = false
-- proacl should NOT contain '=X/' (PUBLIC) or 'anon=X/' (direct anon grant)
```

```sql
-- POST-DEPLOY TEST 4: Comprehensive privilege inventory (run after all 8 batches)
-- Verify both PUBLIC and anon removed for all 58 signatures
SELECT
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS signature,
  has_function_privilege('PUBLIC', p.oid, 'EXECUTE') AS public_has_execute,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_has_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_has_execute
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.prosecdef = true
  AND p.proname IN (
    'accept_band_invite', 'add_special_item_to_setlist', 'auto_create_catalog_for_band',
    'bulk_add_songs_to_setlist', 'check_band_member', 'check_financial_view_permission',
    'check_gig_response_access', 'check_rehearsal_response_access', 'clear_song_metadata',
    'create_band', 'create_venue_for_gig_save', 'delete_setlist', 'delete_song_from_catalog',
    'delete_song_from_setlist', 'ensure_catalog_setlist', 'get_band_calendar_token',
    'get_bandmate_user_ids', 'get_my_calendar_token', 'get_or_create_calendar_preferences',
    'get_or_create_notification_preferences', 'get_unread_notification_count',
    'get_user_band_ids', 'handle_new_user', 'handle_new_user_profile',
    'increment_setlist_positions', 'is_band_admin', 'is_band_member',
    'is_band_member_with_role', 'mark_all_notifications_read', 'move_song_between_setlists',
    'notify_band_members', 'notify_blockout_created', 'notify_gig_created',
    'notify_new_band_member', 'notify_rehearsal_created', 'prevent_catalog_deletion',
    'prevent_catalog_rename', 'recompute_setlist_stats', 'regenerate_band_calendar_token',
    'regenerate_calendar_token', 'reorder_band_members', 'reorder_setlist_items',
    'reorder_setlist_positions', 'reorder_setlist_songs', 'reorder_setlists',
    'restore_band_members', 'sync_gig_location_from_venue', 'sync_gig_pay_from_financial_entry',
    'trigger_recompute_setlist_stats', 'trigger_send_push_notification',
    'update_calendar_preferences', 'update_band_calendar_preferences',
    'update_setlist_duration', 'update_song_metadata', 'update_song_notes_updated_at',
    'upsert_device_token'
  )
ORDER BY p.proname, signature;
-- Expect: public_has_execute = false AND anon_has_execute = false for all 58 signatures
-- Export full results to ENGINEER_REPORT.md
```

```sql
-- POST-DEPLOY TEST 5: Verify Batch 8 functions revoked
SELECT
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS signature,
  has_function_privilege('PUBLIC', p.oid, 'EXECUTE') AS public_has_execute,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_has_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_has_execute
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('notify_band_members', 'recompute_setlist_stats')
ORDER BY p.proname, signature;
-- Expect: public_has_execute = false, anon_has_execute = false, authenticated_has_execute = true for both
```

**Manual Smoke Tests (post-migration, authenticated flows):**

After each batch, spot-check the affected authenticated flow:

- **Batch 1 (triggers):** Create test gig → verify auto_create_catalog_for_band trigger fires
- **Batch 2 (RLS helpers):** Query financial_entries as authenticated member → verify RLS allows
- **Batch 3 (calendar/invite):** Accept invite end-to-end: send invite → click link → edge function → verify band membership created; fetch calendar subscription URL as authenticated admin → verify URL returned
- **Batch 4 (notifications):** Toggle notification preferences in Settings → verify save succeeds
- **Batch 5 (setlists):** Reorder songs in setlist → verify positions updated
- **Batch 6 (song metadata):** Edit song BPM inline → verify save succeeds
- **Batch 7 (band mgmt):** Create new band as authenticated user → verify band created and user is admin
- **Batch 8 (notify/stats):** Create test gig → verify `notify_band_members` is called internally via `notify_gig_created` trigger; edit setlist song → verify setlist duration updates (internal call to `recompute_setlist_stats` via trigger)

**Production Advisor Verification (after all batches):**

- Via Supabase Dashboard → Advisors → Security
- Expect: `anon_security_definer_function_executable` finding count: 0 (down from 58)

## QA Regression Areas

QA must specifically test (gate: QA approval required before production deployment per GUARDRAILS.md §11):

1. **Invite acceptance end-to-end:**
   - Send invite to test email
   - Click invite link (authenticated session)
   - Verify edge function succeeds
   - Verify band membership created with correct role

2. **Calendar subscription URL fetch:**
   - Authenticated admin navigates to Calendar settings
   - Generate calendar subscription URL
   - Verify URL returned
   - Paste URL into external calendar client (Apple Calendar, Google Calendar)
   - Verify .ics feed loads and displays gigs/rehearsals

3. **RLS policy enforcement (financial entries):**
   - Authenticated admin queries financial entries → verify full access
   - Authenticated member queries financial entries → verify full access
   - Authenticated contributor without can_view_financials queries → verify empty (RLS blocks)

4. **Notification preferences:**
   - Toggle notification preferences in Settings
   - Verify save succeeds
   - Verify fetch returns updated preferences

5. **Setlist mutations:**
   - Reorder songs in setlist → verify positions updated
   - Add special item to setlist → verify item appears
   - Move song between setlists → verify song moved

6. **Song metadata edits:**
   - Edit song BPM inline → verify save succeeds
   - Clear song BPM → verify cleared
   - Delete song from catalog → verify deleted

7. **Band creation:**
   - Create new band as authenticated user
   - Verify band created
   - Verify user is admin member

8. **Cross-platform verification:**
   - Test invite acceptance on iOS, Android, Web
   - Test setlist reorder on iOS, Android, Web, macOS
   - Verify no platform-specific regressions

9. **Advisor findings (post-deployment):**
   - Post-production push: verify Supabase Advisors shows 0 `anon_security_definer_function_executable` findings (down from 58)

10. **Silent failure monitoring:**
    - Any screen that shows empty data when it should show data is a regression candidate
    - Monitor for subtle breakage (no loud errors, just missing data)

11. **Batch 8 notification/stats functions:**
    - Create gig → verify notification created for band members (internal `notify_band_members` call via `notify_gig_created`)
    - Edit setlist song BPM → verify setlist duration recalculates (internal `recompute_setlist_stats` call via trigger)

## Rollout / Migration Strategy

### Phase 1: Pre-Deployment Verification

1. **Capture pre-migration ACL state (Task 1) — MANDATORY before any migrations**
   - Query production for exact ACL state of all 58 signatures
   - If `PRE_MIGRATION_ACL_STATE.md` exists, append `notify_band_members` and `recompute_setlist_stats` rows
   - If file does not exist, create with all 58 signatures
2. **Static verification (Tier 1):**
   - SQL syntax validation for all 8 migration files
   - Signature matching against `PRE_MIGRATION_ACL_STATE.md`
   - Rollback completeness review
   - Batch count reconciliation: 8 batches, 56 unique names, 58 signatures
3. **QA approval gate:**
   - QA runs full regression suite (see QA Regression Areas) against current production
   - QA produces `QA_REPORT.md` with APPROVED status
   - Per `COMMIT_GATE.md` and `GUARDRAILS.md` §11, no production push without QA PASS

### Phase 2: Production Deployment (Batched with Per-Batch Verification)

**Gate: Manager approval after QA approval complete**

1. Apply Batch 1 migration (`supabase db push` for `20260822120000_revoke_anon_batch_1_triggers.sql`)
2. Run Tier 2 verification for Batch 1 immediately: privilege checks + smoke test
3. If verification passes, proceed to Batch 2; if fails, diagnose and rollback Batch 1 before continuing
4. Repeat for Batches 2-8 sequentially: apply → verify → proceed
5. After all 8 batches applied, run comprehensive privilege inventory (POST-DEPLOY TEST 4)
6. Check production Supabase Advisors: confirm 58→0 drop

**If any migration fails mid-push:**

- Supabase will halt and not apply remaining migrations
- Diagnose specific batch failure
- Execute rollback for applied batches using commented rollback blocks
- Fix issue, re-test on staging if available, retry

### Phase 3: Post-Production Verification

1. QA spot-checks key flows across platforms (iOS, Android, Web, macOS)
2. Monitor error logs for 24 hours post-deployment
3. If regression detected: execute rollback plan (restore exact pre-migration ACL state per batch from captured baseline)

### Rollback Plan

**Critical requirement:** Rollback must restore exact pre-migration ACL state per signature, not use a blanket template.

**Per-batch rollback structure:**
Each migration includes commented rollback block at bottom. Rollback commands must be sourced from the captured ACL state in `PRE_MIGRATION_ACL_STATE.md` (Task 1), not assumptions.

**Example rollback (Batch 1):**

```sql
-- ===========================================================================
-- ROLLBACK (restore exact pre-migration ACL state from PRE_MIGRATION_ACL_STATE.md)
-- ===========================================================================
-- For functions that had PUBLIC grant (majority of functions):
GRANT EXECUTE ON FUNCTION auto_create_catalog_for_band() TO PUBLIC;
GRANT EXECUTE ON FUNCTION handle_new_user() TO PUBLIC;
-- ... (continue for all functions with PUBLIC in captured state)

-- For functions that had direct anon grant (accept_band_invite, create_band, is_band_member only):
-- GRANT EXECUTE ON FUNCTION create_band(TEXT, TEXT, TEXT) TO anon;  -- if create_band is in this batch

-- IMPORTANT: Do NOT use GRANT TO PUBLIC for functions that only had direct anon grants
-- IMPORTANT: Do NOT use GRANT TO anon for functions that only had PUBLIC grants
-- Refer to captured ACL state for exact restore commands per signature
```

**Full rollback (all batches):** Apply rollback blocks in reverse order (Batch 8 → Batch 1). Requires saved ACL state from Task 1.

**Rollback semantics:**

- **53 functions with PUBLIC grants:** Rollback uses `GRANT EXECUTE ... TO PUBLIC;`
- **3 functions with direct anon grants** (`accept_band_invite`, `create_band`, `is_band_member`): Rollback uses `GRANT EXECUTE ... TO anon;` (NOT PUBLIC)
- Any function with both grants (if discovered during Task 1): Rollback includes both GRANT statements

**Regression Risk from Batched Deployment:** Immediate single-statement rollback possible per batch. Each batch's rollback is a simple GRANT statement that restores prior state in <1 second. No schema changes, no data loss risk.

## Out of Scope

### Explicitly Out of Scope for This Feature

1. **Adding internal authorization checks to 5 setlist functions** (`add_special_item_to_setlist`, `ensure_catalog_setlist`, `increment_setlist_positions`, `reorder_setlist_items`, `reorder_setlist_songs`):
   - These functions have no `is_band_member` check and allow any authenticated user to tamper with any band's setlists
   - Revoking anon access is appropriate and will be done in this feature
   - Adding internal band-membership checks requires function body changes and separate verification → separate feature required
   - See CLASSIFICATION_NOTES.md §3f for full analysis

2. **Parameter design review for 4 helper functions** (`is_band_admin` 2-arg, `get_bandmate_user_ids`, `get_user_band_ids`, `check_rehearsal_response_access`):
   - Accept arbitrary user_id parameters without verifying they match `auth.uid()`
   - Information disclosure risk when anon-callable (fixed by this revoke)
   - Question remains: should these signatures exist at all, or should all helpers resolve from `auth.uid()` internally?
   - Requires signature change analysis → separate feature if pursued

3. **`get_user_band_role` search_path fix (C5 residual):**
   - Not included unless Tony explicitly approves for this feature
   - Separate concern from anon execute grants

4. **Automated test coverage for repository/controller layer:**
   - Current state: 0/18 repositories, 0/15 controllers have tests
   - Would significantly reduce regression risk for future grant changes
   - Large undertaking → separate feature

5. **Migrating edge functions from service_role to more granular roles:**
   - `accept-invite` and `calendar-feed` currently use `SUPABASE_SERVICE_ROLE_KEY` for all operations
   - More granular service accounts (per-function roles) would reduce blast radius
   - Out of scope for this feature, possibly future security hardening feature

## Additional Context

### Known Constraints from Project

- **Repositories commonly swallow errors** (`catch (e) { return []; }`) → silent failures expected; if this migration breaks a call path, likely symptom is empty data quietly, not visible error
- **Zero automated test coverage** on repository/controller layer → manual verification required
- Both raise the bar on verification requirements before and after each batch

### CLASSIFICATION_NOTES.md is Manager-Led Investigation

- All 56 functions were checked against live grants, RLS policies, and actual call sites in the app
- This is a strong starting point, but this is production security work touching 100+ active bands
- **Independently verify its conclusions against the code yourself before finalizing scope**, especially anywhere it claims a function does _not_ need anon access

### Functions with Explicit Direct Anon Grants

From CLASSIFICATION_NOTES.md §4a — these 3 require special rollback handling:

- `accept_band_invite`
- `create_band`
- `is_band_member`

For these three, `PUBLIC` was already revoked at some point (or never carried the default) — anon access survives because someone granted it directly. A migration that only runs `REVOKE EXECUTE ... FROM PUBLIC` will silently do nothing for these three; they need `REVOKE EXECUTE ... FROM anon` explicitly.

**Rollback implication:** These 3 must be rolled back with `GRANT EXECUTE ... TO anon` (not PUBLIC). Restoring PUBLIC would create a broader grant than existed pre-migration.

### Overloaded Functions

Require signature-specific targeting — cannot use bare function name:

- `is_band_admin` (1-arg: `UUID`; 2-arg: `UUID, UUID`)
- `update_band_calendar_preferences` (2 overloads — verify exact signatures during Task 1)

### Edge Function Auth Patterns

- `accept-invite` edge function: requires `Authorization` header, calls `auth.getUser()` (401 if missing/invalid), uses service role key for DB writes via `supabaseAdmin.rpc('accept_band_invite', ...)`
- `calendar-feed` edge function: runs on service role key, does raw table selects (no RPCs), token-authenticated via URL param

---

**Plan Complete — Manager Gate Corrections Applied**

- **Scope corrected:** 56 unique function names, 58 signatures, 8 batches (Batch 8 added for `notify_band_members` and `recompute_setlist_stats`)
- **Deployment strategy corrected:** All branch-testing references removed; direct-to-production with per-batch verification
- **QA gate added:** Explicit requirement for QA approval before production deployment (per `COMMIT_GATE.md` and `GUARDRAILS.md` §11)
- **ACL discipline note added:** `has_function_privilege()` guidance for GUARDRAILS.md update
- **notify_band_members caller list corrected:** 3 functions — `notify_gig_created`, `notify_rehearsal_created`, and `notify_blockout_created`

Branch: `feature/security-definer-revoke-public` (already created)
Next: Engineer implements Tasks 1-12 + Task 8a, produces ENGINEER_REPORT.md
