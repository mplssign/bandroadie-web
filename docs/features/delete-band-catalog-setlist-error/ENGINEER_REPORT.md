# Engineer Report — bug/delete-band-catalog-setlist-error

## Goal

Fix the `delete_band` RPC so it can delete a band that has a catalog setlist, without removing the protection that prevents users from manually deleting catalog setlists.

## Implementation Summary

Created a single new SQL migration that:

1. **Updates `prevent_catalog_deletion()`** — Adds a check for the transaction-local session variable `app.deleting_band`. If set to `'true'`, the trigger allows the delete by returning `OLD` immediately. Otherwise, existing catalog protection logic runs unchanged.

2. **Updates `delete_band()`** — Adds `PERFORM set_config('app.deleting_band', 'true', true);` before the DELETE statements. The third parameter (`true`) makes the setting local to the current transaction, so it is automatically cleared on commit or rollback. All other logic (admin check, explicit deletes, return value) is preserved identically.

## Files Modified

None.

## Files Created

| File                                                                     | Purpose                                                                            |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| `supabase/migrations/20260306000000_fix_delete_band_catalog_trigger.sql` | Migration that replaces `prevent_catalog_deletion()` and `delete_band()` functions |

## Database Migrations Added

| Migration                                            | Description                                                                                                             |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `20260306000000_fix_delete_band_catalog_trigger.sql` | Adds transaction-local session variable bypass to catalog deletion trigger; adds `set_config` call to `delete_band` RPC |

## Verification Commands

```bash
flutter analyze   # Result: No issues found
```

## Manual Test Steps

### 1. Deploy migration

```bash
supabase db push
```

### 2. Test band deletion (the bug fix)

1. Open BandRoadie on macOS or Web
2. Navigate to a band where you are admin
3. Go to band settings → Delete Band
4. Confirm deletion
5. **Expected:** Band is deleted successfully, user returns to dashboard
6. **Previously:** Failed with "Cannot delete Catalog setlist"

### 3. Test catalog deletion protection (regression check)

1. Create or use an existing band
2. Attempt to delete the Catalog setlist via the `delete_setlist` RPC
3. **Expected:** Fails with "Cannot delete the Catalog setlist"
4. Verify the Catalog setlist still exists

### 4. Test direct SQL catalog deletion (regression check)

```sql
-- Should fail
DELETE FROM setlists WHERE id = '<catalog_setlist_id>';
-- Expected error: "Cannot delete Catalog setlist"
```

### 5. Test band creation still creates catalog

1. Create a new band
2. Verify a Catalog setlist is auto-created for the new band

## QA Focus Areas

- **Primary:** Band deletion now succeeds when the band has a catalog setlist
- **Regression:** Manual catalog deletion (via `delete_setlist` RPC or direct SQL) is still blocked
- **Security:** The `app.deleting_band` session variable is transaction-local and only set within `delete_band` (SECURITY DEFINER). It cannot be set by client code to bypass the trigger externally.
- **Transaction safety:** The `set_config(..., true)` call is transaction-local; it does not persist after the transaction ends
- **No Flutter changes:** The fix is entirely server-side; no client code was modified
- **No init-order changes:** N/A (database-only fix)
- **No config-path changes:** N/A (database-only fix)

## Assumptions

- The `delete_band` function body in `20260302000000_band_user_roles.sql` (lines 326–371) is the current deployed version
- The `prevent_catalog_deletion` trigger function in migration 068 (lines 155–164) is the current deployed version
- Migration timestamp `20260306000000` is after all deployed migrations
- No other functions set `app.deleting_band`
