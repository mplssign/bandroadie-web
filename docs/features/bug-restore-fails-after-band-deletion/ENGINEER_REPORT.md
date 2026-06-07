# Engineer Report

## Feature Slug

`bug/restore-fails-after-band-deletion`

## Feature Title

Restore fails after band deletion

## Goal

Fix the restore flow so that a BandRoadie backup can be restored even when the original source band has been deleted. Recreate the band via `create_band` RPC, remap all child-row `band_id` values to the new band, generate fresh UUIDs for orphaned `rehearsals` and `block_dates` rows to bypass RLS-blocked UPDATE paths, and surface real error messages instead of the generic "Restore failed. Please try again." toast.

---

## Architect Tasks Completed

- [x] Task 1 — Query `bands` table RLS INSERT policy from production (confirmed RC-4)
- [x] Task 2 — Create migration `20260607000000_fix_delete_band_cascade.sql`
- [x] Task 3 — Add `_generateUuid()` helper + `dart:math` import to `data_backup_service.dart`
- [x] Task 4 — Implement missing-band path in `_restoreBandData`
- [x] Task 5 — Update `importBandData` to check band existence before calling `_restoreBandData`
- [x] Task 6 — Wrap `PostgrestException` as `DataBackupException` inside `_restoreBandData`
- [x] Task 7 — Fix `_performImport` catch block in `band_form_screen.dart`
- [x] Task 8 — `flutter analyze` — 0 errors

---

## Task 1 — Bands RLS INSERT Policy Query Result

Query run against production (`nekwjxvgbveheooyorjo`):

```sql
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'bands' AND schemaname = 'public';
```

Full result:

| policyname                   | cmd    | qual                                                                                                                                          | with_check                |
| ---------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| Band members can view bands  | SELECT | is_band_member(id)                                                                                                                            | NULL                      |
| Only admins can delete bands | DELETE | EXISTS (SELECT 1 FROM band_members bm WHERE bm.band_id = bands.id AND bm.user_id = auth.uid() AND bm.role = 'admin' AND bm.status = 'active') | NULL                      |
| bands: delete creator        | DELETE | (created_by = auth.uid())                                                                                                                     | NULL                      |
| bands: insert own            | INSERT | NULL                                                                                                                                          | (created_by = auth.uid()) |
| bands: select my bands       | SELECT | EXISTS (SELECT 1 FROM band_members bm WHERE bm.band_id = bands.id AND bm.user_id = auth.uid() AND bm.status IN ('active','invited'))          | NULL                      |
| bands_delete_admins          | DELETE | is_band_admin(id)                                                                                                                             | NULL                      |
| bands_insert_authenticated   | INSERT | NULL                                                                                                                                          | (created_by = auth.uid()) |
| bands_select_members         | SELECT | EXISTS (SELECT 1 FROM band_members bm WHERE bm.band_id = bands.id AND bm.user_id = auth.uid() AND bm.status = 'active')                       | NULL                      |
| bands_update_admins          | UPDATE | is_band_admin(id)                                                                                                                             | is_band_admin(id)         |

**RC-4 finding:** Both INSERT policies (`bands: insert own` and `bands_insert_authenticated`) only check `WITH CHECK (created_by = auth.uid())`. This confirms **Sub-mode B** is the operative failure path, not Sub-mode A. The `bands` INSERT itself would succeed when the current user's `created_by` matches. However:

- The subsequent `band_members` upsert faces a bootstrapping problem for OTHER users' rows (no admin row for current user yet at time of insert).
- More critically, RC-3 (orphaned `rehearsals`/`block_dates`) is the primary failure path: the ON CONFLICT UPDATE for those rows is RLS-blocked because `rehearsals.band_id` references the deleted band.
- RC-1 (bypassing `create_band` RPC) remains the correct fix regardless — the RPC atomically inserts the band + current user's admin row, eliminating the bootstrap race entirely.

---

## Files Created

- `supabase/migrations/20260607000000_fix_delete_band_cascade.sql`
- `docs/features/bug-restore-fails-after-band-deletion/ENGINEER_REPORT.md` (this file)

## Files Modified

- `lib/features/settings/data_backup_service.dart`
- `lib/features/bands/band_form_screen.dart`

---

## Analyzer Results

Command: `flutter analyze`
Result: **0 errors, 0 warnings** (after adding `package:supabase_flutter/supabase_flutter.dart show PostgrestException` import — see Deviations).

---

## Test Results

Not run (no tests explicitly cover the restore flow; Architect plan does not require automated tests for this change).

---

## Verification

Manual steps performed:

- Confirmed production `bands` RLS INSERT policies via `supabase db query --linked`.
- Read full `delete_band` function body from `20260302000000_band_user_roles.sql` to confirm exact existing DELETE order before creating replacement migration.
- Verified new migration preserves all existing DELETE statements and admin/band-exists guards.
- Confirmed `dart format` produced no unexpected changes to `band_form_screen.dart` (no diff on that file from formatter).
- Ran `flutter analyze` twice (before and after `dart format`) — 0 issues both times.
- Ran `git diff` — only `lib/features/bands/band_form_screen.dart` and `lib/features/settings/data_backup_service.dart` modified; `supabase/migrations/20260607000000_fix_delete_band_cascade.sql` untracked (new file).

---

## Deviations From Architect Plan

1. **`PostgrestException` import:** The plan stated "Import `package:supabase_flutter/supabase_flutter.dart` is already present." It is not directly present in `data_backup_service.dart` — only `../../app/services/supabase_client.dart` is imported, which imports supabase_flutter but does not re-export `PostgrestException`. Added `import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;` to satisfy the on-catch type requirement. This is minimal and adds no new package dependency (`supabase_flutter` is already in `pubspec.yaml`).

2. **`dart format` reformatted `_buildBandExport`:** The formatter reformatted some multi-line chained calls in `_buildBandExport` (a method that is off-limits per §11). These are whitespace/formatting-only changes with zero behavioural impact. The method logic is byte-for-byte identical. Accepted as the formatter is authoritative per Phase 6.

---

## Blockers Encountered

None.

---

## Ready For QA

Yes.

QA regression areas from §16 of the Architect Plan that must be exercised before merge:

1. Restore after band deletion (new-band path) — primary fix.
2. Restore when source band still exists (existing-band path) — regression check.
3. Error surfacing with corrupted backup file.
4. `delete_band` cascade regression (verify no orphaned `rehearsals`/`block_dates` after deletion).
5. Multi-band safety check.
