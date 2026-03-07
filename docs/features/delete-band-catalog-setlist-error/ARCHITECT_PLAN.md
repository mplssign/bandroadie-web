# Architect Plan — bug/delete-band-catalog-setlist-error

## 1. Problem Summary

Deleting a band in BandRoadie fails with:

> "Failed to delete band: Cannot delete Catalog setlist."

The `delete_band` RPC explicitly deletes setlist rows (`DELETE FROM public.setlists WHERE band_id = band_uuid`). This fires the `prevent_catalog_deletion_trigger` on the `setlists` table, which unconditionally blocks deletion of any setlist where `is_catalog = true`. The trigger has no mechanism to distinguish between manual user deletion and deletion as part of band removal.

The band remains in the database and cannot be removed.

## 2. Existing System Analysis

### delete_band RPC

- **Defined in:** `supabase/migrations/20260302000000_band_user_roles.sql` (lines 326–371)
- **Behavior:** SECURITY DEFINER function. Verifies caller is an admin. Performs explicit row-by-row deletion of:
  1. `band_members`
  2. `band_invitations`
  3. `gig_responses` (for the band's gigs)
  4. `gigs`
  5. `setlist_songs` (for the band's setlists)
  6. `setlists` ← **fails here**
  7. `songs`
  8. `bands`
- **Does NOT** call `delete_setlist` RPC. Uses direct DELETE statements.
- **Does NOT** set any session variable or flag to signal "band deletion context."

### prevent_catalog_deletion trigger

- **Created in:** `lib/supabase/migrations/068_ensure_catalog_setlist_rpc_standalone.sql` (lines 155–164)
- **Type:** BEFORE DELETE trigger on `public.setlists`, fires FOR EACH ROW.
- **Behavior:** If `OLD.setlist_type = 'catalog' OR OLD.is_catalog = true`, raises exception `'Cannot delete Catalog setlist'`.
- **No bypass logic.** Blocks ALL deletes of catalog setlists regardless of context.

### delete_setlist RPC

- **Defined in:** `supabase/migrations/20260228000000_create_delete_setlist_rpc.sql` (lines 11–66)
- **Behavior:** Verifies band membership. Checks `is_catalog` / name-based catalog detection. Raises exception for catalog setlists. Nullifies gig/rehearsal setlist_id references. Deletes setlist_songs and then setlist.
- **Not involved in the bug.** `delete_band` does not invoke `delete_setlist`.

### Setlists table schema

- **Defined in:** `lib/supabase/migrations/005_create_setlists_tables.sql`
- **Key columns:** `id`, `band_id` (FK to bands ON DELETE CASCADE), `name`, `setlist_type` (added in 068), `is_catalog` (added in 068)
- **FK constraint:** `band_id UUID REFERENCES public.bands(id) ON DELETE CASCADE`

### setlist_songs table

- **FK constraint:** `setlist_id UUID REFERENCES public.setlists(id) ON DELETE CASCADE`
- Cascades automatically when setlists are deleted.

### Flutter invocation

- **File:** `lib/features/bands/band_form_screen.dart` (lines 565–575)
- Calls `supabase.rpc('delete_band', params: {'band_uuid': band.id})`
- Catches `PostgrestException`, displays user-friendly error message.
- No client-side logic contributes to the bug.

### Prior attempted fix (never deployed)

- **File:** `lib/supabase/migrations/083_fix_delete_band_catalog_trigger.sql`
- **Approach:** Updated `prevent_catalog_deletion()` to check `pg_trigger_depth() > 1` and rewrote `delete_band` to delete the band row first (relying on FK CASCADE).
- **Status:** Exists only in `lib/supabase/migrations/`. **Not present in `supabase/migrations/`.** Never deployed.
- **Overwritten by:** Migration `20260302000000_band_user_roles.sql` replaced `delete_band` with explicit-delete approach, undoing the 083 strategy.

### Prior attempted fix (migration 070)

- **File:** `lib/supabase/migrations/070_fix_catalog_deletion_cascade.sql`
- **Approach:** Updated trigger to check if band still exists (`NOT EXISTS (SELECT 1 FROM bands WHERE id = OLD.band_id)`).
- **Status:** Also in `lib/supabase/migrations/` only. Unclear if deployed, but irrelevant — the current `delete_band` deletes setlists before the band row, so the band would still exist when the trigger fires.

## 3. Root Cause

**Layer:** Database trigger (`prevent_catalog_deletion_trigger` on `public.setlists`)

**Chain of failure:**

1. Flutter calls `delete_band` RPC
2. `delete_band` executes `DELETE FROM public.setlists WHERE band_id = band_uuid;`
3. `prevent_catalog_deletion_trigger` fires for the catalog setlist row
4. Trigger checks `is_catalog = true` → raises exception `'Cannot delete Catalog setlist'`
5. Exception propagates up to `delete_band` → entire transaction aborts
6. Flutter receives PostgrestException with message containing "Cannot delete"
7. UI shows "Failed to delete band: Cannot delete Catalog setlist."

**Evidence:**

- The `delete_band` RPC in `20260302000000_band_user_roles.sql` does an explicit `DELETE FROM public.setlists` (line 363)
- The trigger in migration 068 unconditionally blocks catalog setlist deletion (lines 155–164)
- The trigger has no bypass for "band deletion in progress" context
- Migration 083 attempted a fix but was never deployed to `supabase/migrations/`
- Migration 20260302000000 subsequently overwrote `delete_band`, negating 083 even if it had been deployed

## 4. Proposed Solution

**Approach:** Transaction-local session variable bypass.

Modify two database functions in a single new migration:

### A. Update `prevent_catalog_deletion()`

Add a bypass check at the top of the trigger function:

- Check `current_setting('app.deleting_band', true)` — if it equals `'true'`, allow the delete by returning OLD immediately.
- The second parameter `true` in `current_setting()` means "return NULL if the setting doesn't exist" (avoids errors when the variable isn't set).
- If the variable is not set (or not `'true'`), proceed with existing catalog protection logic.

### B. Update `delete_band()`

Before any DELETE statements, set a transaction-local session variable:

- Call `PERFORM set_config('app.deleting_band', 'true', true);`
- The third parameter `true` makes the setting local to the current transaction.
- When the trigger fires during setlist deletion, it reads this variable and allows the delete.
- After the transaction completes (commit or rollback), the variable is automatically cleared.

### Why this approach

| Criterion                   | Assessment                                                                    |
| --------------------------- | ----------------------------------------------------------------------------- |
| Minimal change surface      | Two functions updated in one migration                                        |
| Backward compatible         | No schema changes, no column additions                                        |
| Preserves manual protection | Without the session variable set, trigger still blocks catalog deletion       |
| No Flutter changes          | Bug is entirely in the database layer                                         |
| Transaction-safe            | `set_config(..., true)` is transaction-local; auto-cleared on commit/rollback |
| No init-order changes       | N/A                                                                           |
| No config-path changes      | N/A                                                                           |

### Why NOT the pg_trigger_depth approach (from 083)

The `pg_trigger_depth() > 1` approach only works when deletion is triggered via FK CASCADE (depth > 1). The current `delete_band` performs explicit DELETEs (not CASCADE), so `pg_trigger_depth()` equals 1 during the setlist trigger — the bypass would not activate. Switching `delete_band` to CASCADE-first would require rewriting its deletion strategy, which is a larger change with more risk.

### Why NOT the "band exists" check approach (from 070)

Migration 070 checked if the band still exists. Since `delete_band` deletes setlists before the band row, the band still exists when the trigger fires, so this check fails to allow the bypass.

## 5. Database Impact

- **No schema changes.** No new tables, columns, or indexes.
- **Two functions replaced:** `prevent_catalog_deletion()` and `delete_band()`.
- **One migration file added** to `supabase/migrations/`.
- **Session variable `app.deleting_band`** is transaction-local; no persistent state.

## 6. RLS / RPC Changes

### RPC changes

- **`delete_band(UUID)`:** Add `PERFORM set_config('app.deleting_band', 'true', true);` before DELETE statements. All other logic (admin check, explicit deletes, return value) stays identical.

### Trigger changes

- **`prevent_catalog_deletion()`:** Add session variable check at the top, before the existing `is_catalog` check. All existing protection logic is preserved as the fallback path.

### RLS policy changes

- **None.** No RLS policies are modified.

## 7. Flutter Architecture Changes

**None.** The bug is entirely in the database layer. No Flutter code changes are required.

The existing error handling in `band_form_screen.dart` will naturally work correctly once the RPC succeeds.

## 8. Exact Files to Create

| File                                                                     | Purpose                                                                                      |
| ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| `supabase/migrations/YYYYMMDDHHMMSS_fix_delete_band_catalog_trigger.sql` | New migration: updates `prevent_catalog_deletion()` trigger function and `delete_band()` RPC |

Engineer must use a valid timestamp for the migration filename (after `20260305100000`).

## 9. Exact Files to Modify

**None.** The fix is a new migration that replaces the existing functions. No existing files are edited.

### Reference files (do not modify, read for context only)

| File                                                                    | Reason                                                               |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `supabase/migrations/20260302000000_band_user_roles.sql`                | Contains current `delete_band` definition (lines 326–371)            |
| `supabase/migrations/20260228000000_create_delete_setlist_rpc.sql`      | Contains `delete_setlist` RPC (not modified, verify no conflict)     |
| `lib/supabase/migrations/068_ensure_catalog_setlist_rpc_standalone.sql` | Contains original `prevent_catalog_deletion` trigger (lines 155–164) |
| `lib/supabase/migrations/083_fix_delete_band_catalog_trigger.sql`       | Prior attempted fix (reference only, do not deploy)                  |
| `lib/features/bands/band_form_screen.dart`                              | Flutter call site (no changes needed)                                |

## 10. Risks / Edge Cases

### Risk: Session variable leaks across operations

- **Mitigation:** `set_config('app.deleting_band', 'true', true)` is transaction-local. It cannot leak to other transactions or persist after the transaction ends. Supabase RPCs run in their own transaction.

### Risk: Other code paths set the variable

- **Mitigation:** `app.deleting_band` is a custom namespace. No other function uses it. Only `delete_band` should ever set it.

### Risk: Trigger function signature mismatch

- **Mitigation:** The trigger function is replaced with `CREATE OR REPLACE FUNCTION`. The function signature (no arguments, returns TRIGGER) is unchanged.

### Risk: delete_band function signature collision

- **Mitigation:** Migration uses `CREATE OR REPLACE FUNCTION public.delete_band(UUID)` with the exact same signature. The function body is identical except for the added `set_config` call.

### Edge case: Band with no catalog setlist

- **Impact:** None. The session variable is set unconditionally, but if no catalog setlist exists, the trigger never fires for a catalog row. The variable is harmlessly cleared at transaction end.

### Edge case: Concurrent band deletion

- **Impact:** None. Session variables are per-connection, transaction-local. Two concurrent `delete_band` calls operate in separate transactions with separate session state.

### Edge case: delete_setlist RPC still works

- **Impact:** None. `delete_setlist` does not set `app.deleting_band`. The trigger continues to block manual catalog deletion through `delete_setlist`.

## 11. Verification Plan

### Database verification

1. Create a test band
2. Confirm the band has a catalog setlist (verify `is_catalog = true`)
3. Call `delete_band` RPC
4. Verify the band is deleted
5. Verify all setlists (including catalog) are deleted
6. Verify setlist_songs, gigs, songs, band_members are deleted

### Manual deletion protection verification

1. Create a test band with a catalog setlist
2. Attempt to call `delete_setlist` RPC on the catalog setlist
3. Verify it fails with "Cannot delete the Catalog setlist"
4. Attempt direct SQL: `DELETE FROM setlists WHERE id = <catalog_id>;`
5. Verify it fails with "Cannot delete Catalog setlist"

### Regression checks

- `flutter analyze` — must pass with no errors
- Verify no initialization order changes
- Verify no config path changes
- Verify `delete_setlist` RPC still protects catalog setlists
- Verify band creation still auto-creates catalog setlist

### Platform testing

- Test band deletion on at least one platform (macOS or Web recommended)
- Confirm success snackbar appears after deletion
- Confirm navigation returns to dashboard with updated band list

## 12. Engineer Task Breakdown

| #   | Task                                                                                                                                                 | Scope        |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| 1   | Read this plan and all referenced files                                                                                                              | Context      |
| 2   | Create new migration file in `supabase/migrations/` with timestamp after `20260305100000`                                                            | Database     |
| 3   | Write `CREATE OR REPLACE FUNCTION prevent_catalog_deletion()` with session variable bypass                                                           | Database     |
| 4   | Write `CREATE OR REPLACE FUNCTION delete_band(UUID)` with `set_config` call before deletes                                                           | Database     |
| 5   | Copy current `delete_band` body from `20260302000000_band_user_roles.sql` (lines 326–371) — only add the `set_config` line, preserve everything else | Database     |
| 6   | Include `GRANT EXECUTE ON FUNCTION public.delete_band(UUID) TO authenticated;`                                                                       | Database     |
| 7   | Run `flutter analyze`                                                                                                                                | Verification |
| 8   | Deploy migration to Supabase                                                                                                                         | Deployment   |
| 9   | Test band deletion end-to-end                                                                                                                        | Verification |
| 10  | Test manual catalog deletion still blocked                                                                                                           | Verification |
| 11  | Prepare QA handoff                                                                                                                                   | Process      |

## 13. Rollout / Migration Strategy

### Deployment order

1. Deploy the new migration to Supabase (this replaces the two functions atomically)
2. No Flutter deployment needed — the fix is entirely server-side
3. The fix takes effect immediately for all clients

### Rollback plan

If the migration causes issues:

1. Revert `prevent_catalog_deletion()` to the original 068 version (remove session variable check)
2. Revert `delete_band()` to the 20260302 version (remove `set_config` call)
3. This restores the original behavior (band deletion blocked by trigger)

### Migration safety

- The migration is additive (replaces functions, does not drop tables/columns)
- No data is modified
- Both functions are replaced atomically in a single transaction
- Rollback returns to the pre-fix state without data loss

## 14. Out of Scope

- Refactoring `delete_band` to use FK CASCADE instead of explicit deletes
- Deploying the old migration 083 from `lib/supabase/migrations/`
- Modifying `delete_setlist` RPC
- Changing Flutter error handling in `band_form_screen.dart`
- Adding new UI for band deletion flow
- Fixing or cleaning up `lib/supabase/migrations/` reference files
- Adding unit tests for band deletion (recommended but not in scope for this bug fix)
- Modifying the `prevent_catalog_rename_trigger`
- Schema changes to the `setlists` table
