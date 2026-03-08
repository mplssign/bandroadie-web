# QA Report — bug/delete-band-catalog-setlist-error

## Feature Slug

`delete-band-catalog-setlist-error`

## Feature Title

Fix: delete_band RPC fails with "Cannot delete Catalog setlist"

---

## Validation Summary

The Engineer implementation correctly follows the Architect plan. A single new SQL migration adds a transaction-local session variable bypass to the `prevent_catalog_deletion` trigger, and sets that variable in `delete_band` before executing DELETE statements. No Flutter code was changed. No existing files were modified. The fix is minimal, scoped, and safe.

---

## Bug Reproduction Result

**Root cause confirmed:** The `prevent_catalog_deletion` trigger unconditionally blocks deletion of catalog setlists, including during band removal via `delete_band` RPC.

**Fix logic verified (code review):**

- `delete_band` now calls `set_config('app.deleting_band', 'true', true)` before DELETEs
- `prevent_catalog_deletion` checks `current_setting('app.deleting_band', true)` and returns OLD if `'true'`
- Manual catalog deletion (via `delete_setlist` or direct SQL) remains blocked because `app.deleting_band` is never set outside `delete_band`

---

## Implementation Review

| Aspect                                                         | Status                                              |
| -------------------------------------------------------------- | --------------------------------------------------- |
| Follows Architect plan                                         | PASS                                                |
| Minimal change surface                                         | PASS — one new migration, two function replacements |
| No Flutter changes                                             | PASS                                                |
| No init-order changes                                          | PASS                                                |
| No config-path changes                                         | PASS                                                |
| No unrelated refactors                                         | PASS                                                |
| Architecture preserved                                         | PASS                                                |
| `delete_band` body identical to original (except `set_config`) | PASS                                                |
| `prevent_catalog_deletion` preserves existing protection logic | PASS                                                |
| GRANT EXECUTE included                                         | PASS                                                |
| Migration timestamp valid (after 20260305100000)               | PASS                                                |

---

## Files Verified

### Files Created

| File                                                                     | Purpose                                                             | Verified |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------- | -------- |
| `supabase/migrations/20260306000000_fix_delete_band_catalog_trigger.sql` | Migration: updates `prevent_catalog_deletion()` and `delete_band()` | PASS     |
| `docs/features/delete-band-catalog-setlist-error/ARCHITECT_PLAN.md`      | Architect plan                                                      | PASS     |
| `docs/features/delete-band-catalog-setlist-error/ENGINEER_REPORT.md`     | Engineer report                                                     | PASS     |

### Files Modified

None. (Correct per plan.)

### Reference Files Checked

| File                                                                                    | Purpose                                                        |
| --------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `supabase/migrations/20260302000000_band_user_roles.sql` (lines 326–375)                | Original `delete_band` — verified body match                   |
| `lib/supabase/migrations/068_ensure_catalog_setlist_rpc_standalone.sql` (lines 155–164) | Original `prevent_catalog_deletion` — verified logic preserved |

---

## Migration Review

| Check                                                          | Result |
| -------------------------------------------------------------- | ------ |
| No existing migrations modified                                | PASS   |
| Only new migration added                                       | PASS   |
| No schema changes (no tables, columns, indexes)                | PASS   |
| No RLS policy changes                                          | PASS   |
| No foreign key changes                                         | PASS   |
| No cascade changes                                             | PASS   |
| No privilege escalation                                        | PASS   |
| Functions replaced with same signatures                        | PASS   |
| SECURITY DEFINER preserved on both functions                   | PASS   |
| Transaction-local session variable (not persistent)            | PASS   |
| `app.deleting_band` cannot be set by client code via PostgREST | PASS   |

---

## Regression Check

| System                              | Impact                                              | Risk |
| ----------------------------------- | --------------------------------------------------- | ---- |
| Setlists (catalog protection)       | Trigger modified — bypass gated by session variable | LOW  |
| Band deletion                       | `set_config` added before existing DELETE chain     | LOW  |
| `delete_setlist` RPC                | Not modified, does not set bypass variable          | NONE |
| Gigs / gig_responses                | No changes                                          | NONE |
| Rehearsals                          | No changes                                          | NONE |
| Songs                               | No changes                                          | NONE |
| Notifications                       | Not involved                                        | NONE |
| Role permissions                    | Admin check preserved identically                   | NONE |
| Routing                             | No Flutter changes                                  | NONE |
| Auth/session                        | No changes                                          | NONE |
| Band creation / catalog auto-create | Not touched                                         | NONE |
| Catalog rename protection           | Not touched                                         | NONE |

### Regression Risk Level: LOW

---

## Analyzer Results

```
flutter analyze: No issues found (0 errors, 0 warnings)
```

---

## Diff Review

| Check                   | Result |
| ----------------------- | ------ |
| No secrets or API keys  | PASS   |
| No environment keys     | PASS   |
| No config changes       | PASS   |
| No unrelated refactors  | PASS   |
| Only expected new files | PASS   |

---

## Critical Issues

None.

## Warnings

None.

## Suggestions

- Post-deployment: test band deletion end-to-end on at least one platform
- Post-deployment: verify manual catalog deletion via `delete_setlist` still fails
- Post-deployment: verify direct SQL `DELETE FROM setlists WHERE is_catalog = true` still fails

---

## Final Verdict

**APPROVED**
