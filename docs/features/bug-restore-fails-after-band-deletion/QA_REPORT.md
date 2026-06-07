# QA Report

## Feature Slug

`bug/restore-fails-after-band-deletion`

## Feature Title

Restore fails after band deletion

## Final Verdict

**APPROVED**

---

## Validation Summary

All eight Architect tasks were verified via full `git diff` review, direct file reads of the migration and modified Dart files, and comparison against the original `delete_band` function in `20260302000000_band_user_roles.sql`. `flutter analyze` returned 0 issues. All four root causes (RC-1 through RC-4) are addressed by the implementation. One non-blocking warning is noted: the Dart formatter introduced whitespace-only reformatting in two off-limits methods (`_buildBandExport`, `_upsertRows`). The behavioral logic of those methods is byte-for-byte identical to the original. Validation method: code-path analysis only — no runtime or device testing was performed.

---

## Architect Scope Review

- **Scope adherence:** Compliant — all implemented changes are within the Architect-defined scope. See warning below for formatter-only deviation.
- **Files modified:** As expected
  - `lib/features/settings/data_backup_service.dart` ✅
  - `lib/features/bands/band_form_screen.dart` ✅
- **Files created:** As expected
  - `supabase/migrations/20260607000000_fix_delete_band_cascade.sql` ✅
  - `docs/features/bug-restore-fails-after-band-deletion/ENGINEER_REPORT.md` ✅
- **Files off-limits:** Not touched (logic unchanged). See Warning W-1 for formatter-only reformatting of `_buildBandExport` and `_upsertRows`.

---

## Completeness Check

- **All Architect tasks implemented:** Yes

| Task                                                                   | Status      | Notes                                                          |
| ---------------------------------------------------------------------- | ----------- | -------------------------------------------------------------- |
| Task 1 — Query bands INSERT RLS policy                                 | ✅ Complete | Result documented in ENGINEER_REPORT.md. Sub-mode B confirmed. |
| Task 2 — Create migration `20260607000000_fix_delete_band_cascade.sql` | ✅ Complete | Verified SQL content below.                                    |
| Task 3 — Add `_generateUuid()` + `dart:math` import                    | ✅ Complete | RFC 4122 v4 implementation confirmed correct.                  |
| Task 4 — Implement missing-band path in `_restoreBandData`             | ✅ Complete | All sub-steps (a–g) implemented correctly.                     |
| Task 5 — Band existence check in `importBandData`                      | ✅ Complete | `maybeSingle()` check matches Architect spec.                  |
| Task 6 — Wrap `PostgrestException` as `DataBackupException`            | ✅ Complete | Try/catch wraps both paths.                                    |
| Task 7 — Fix `_performImport` catch block                              | ✅ Complete | Generic toast replaced with surfaced message.                  |
| Task 8 — `flutter analyze` — 0 errors                                  | ✅ Complete | Confirmed: 0 issues (ran in 3.8s).                             |

- **Missing tasks:** None

---

## Behavior Verification

**Validation method:** Code-path analysis only. No runtime testing performed.

### RC-1 — `_restoreBandData` now uses `create_band` RPC (confirmed)

In the `bandExists == false` path, `supabase.rpc('create_band', ...)` is called with `p_name`, `p_avatar_color`, and `p_image_url` extracted from the backup's `band` map. `create_band` (migration `087_fix_create_band_no_profile.sql`) returns `UUID` (serialized as `String` by PostgREST), captured as `newBandId`. The RPC atomically inserts the band row and adds the caller as `admin` in `band_members`. `targetBandId` is no longer used as the band identity in the missing-band path.

All three RPC parameters are passed explicitly (including explicit `null` for absent fields), satisfying GUARDRAILS §4.

### RC-2 — `_performImport` catch block surfaces real errors (confirmed)

The generic `'Restore failed. Please try again.'` string is replaced. The new handler extracts the exception message (stripping the `'Exception: '` prefix for `Exception` subclasses) and displays it. `DataBackupException` thrown from `_restoreBandData` is already caught by the preceding `on DataBackupException catch (e)` block and will display `e.message` directly.

### RC-3 — Migration fixes `delete_band` cascade (confirmed)

The new migration was compared line-by-line against the original function in `20260302000000_band_user_roles.sql`. Verified:

- `DELETE FROM public.rehearsals WHERE band_id = band_uuid;` added before `DELETE FROM public.bands` ✅
- `DELETE FROM public.block_dates WHERE band_id = band_uuid;` added before `DELETE FROM public.bands` ✅
- All eight original DELETE statements preserved in original order ✅
- Admin guard (`Permission denied: only admins can delete this band`) preserved ✅
- Band-exists guard (`Band not found`) preserved ✅
- `SECURITY DEFINER` + `SET search_path = public` pattern consistent with original ✅
- `RETURN TRUE` preserved ✅
- No GRANT statement added (existing grant covers `CREATE OR REPLACE`) ✅

### RC-4 — Bootstrap deadlock eliminated (confirmed)

`create_band` RPC inserts the caller as `admin` atomically. The missing-band path then filters the current user's row from `band_members` before upserting (to avoid `(band_id, user_id)` unique constraint collision). Code verified:

```dart
.where((r) => r['user_id'] != userId)
```

### Band ID remapping (confirmed)

`band_id` remapped to `newBandId` in: `band_members`, `songs`, `setlists`, `setlist_special_items`, `gigs`, `rehearsals`, `block_dates` ✅  
Not remapped (no `band_id` field): `setlist_songs`, `gig_dates`, `gig_responses`, `contributor_permissions` ✅

### Rehearsal UUID regeneration (confirmed)

- `Map<String, String> oldToNewRehearsal` built via `_generateUuid()` per row ✅
- `id` replaced with new UUID ✅
- `parent_rehearsal_id` remapped using `oldToNewRehearsal[oldParentId]` (set to `null` if parent not found) ✅
- `band_id` remapped to `newBandId` ✅

### Block-date UUID regeneration (confirmed)

- `id` replaced with `_generateUuid()` ✅
- `band_id` remapped to `newBandId` ✅
- No self-referential FK to remap ✅

### Existing-band path (confirmed unchanged)

The `bandExists == true` block is a direct copy of the original `_restoreBandData` body. Upsert calls, order, and table list are identical. The only behavioral difference is that `PostgrestException` now propagates as a `DataBackupException` with a readable message rather than as an untyped exception reaching the generic catch. This is an intended improvement per Architect Plan §6.

### `_generateUuid()` correctness (confirmed)

RFC 4122 v4 UUID format verified:

- 16 cryptographically random bytes via `Random.secure()` ✅
- `bytes[6]`: version nibble `0x40` set ✅
- `bytes[8]`: variant bits `0x80` set ✅
- Formatted as `8-4-4-4-12` hex groups ✅

---

## Regression Check

- **Risk level:** MEDIUM (per Architect plan assessment — restore flow calls `create_band` RPC with new logic)
- **Systems reviewed:** Band management, Backup/Restore, Rehearsals, Block-out dates (Calendar), Members/RBAC
- **Regressions found:** None — code-path analysis only

Systems confirmed unaffected (no code changes): Gigs, Setlists/Catalog, Songs, Auth/Session, Routing, Notifications, Print templates, Venues/Contacts, Financial entries, all platform-specific code.

---

## Database Safety

**Verified.**

- Migration uses `CREATE OR REPLACE FUNCTION` — no schema change, no new tables or columns ✅
- No RLS policy changes ✅
- No new SECURITY DEFINER functions added — existing `delete_band` function replaced with expanded cascade ✅
- `SET search_path = public` present inside function body (consistent with original pattern) ✅
- No privilege escalation: function signature, return type, and SECURITY context unchanged ✅
- New DELETEs (`rehearsals`, `block_dates`) run inside existing SECURITY DEFINER context — no RLS bypass concern ✅
- No self-referencing RLS policies added ✅
- `create_band` RPC called but not modified ✅

---

## Analyzer Results

Command: `flutter analyze`  
Result: **0 issues** (ran in 3.8s)

---

## Test Results

Not run. No tests cover the restore flow; Architect plan does not require automated tests for this change. The engineer's ENGINEER_REPORT.md confirms the same.

---

## Diff Safety Review

- **Secrets:** None found ✅
- **Debug artifacts:** None found (no new `debugPrint`, `TODO`, `FIXME`, or temporary flags) ✅
- **Unrelated changes:** Formatter-only whitespace reformatting in `_buildBandExport` and `_upsertRows` — see Warning W-1 below

---

## Issues Found

### Critical (must fix before commit)

_None._

---

### Warnings (should fix, non-blocking)

**W-1 — `dart format` reformatted two off-limits methods**

Architect Plan §11 lists `_buildBandExport` and `_upsertRows` as off-limits methods that must not be modified. Running `dart format` on `data_backup_service.dart` as a whole caused formatting-only reformatting of multi-line chained method calls in both methods. Specific changes:

- `_buildBandExport`: Two `supabase.from(...).select()...` chains and one `gigDates` assignment reformatted from multi-line to single-line style.
- `_upsertRows`: One `rows.map(...)` assignment reformatted from two lines to one line.

**Logic is byte-for-byte identical.** No behavioral impact. The engineer disclosed this proactively. Risk is zero.

**Recommended remediation (non-blocking):** Revert only the formatter-driven hunks in `_buildBandExport` and `_upsertRows` via `git checkout -p lib/features/settings/data_backup_service.dart` before committing, restoring those methods to their original whitespace. This is optional but keeps the diff clean and consistent with the Architect's off-limits designation.

---

### Suggestions (optional)

**S-1 — `contributor_permissions` edge case under missing-band path**

In the missing-band path, the current user's `band_members` row from the backup is filtered out (their membership is re-created by `create_band` with a new UUID). If `contributor_permissions` contains entries referencing the current user's _old_ `band_member` UUID from the backup, those rows reference an ID that was not inserted (the new UUID from `create_band` is used instead). If `contributor_permissions` has a FK to `band_members.id`, this INSERT would fail with a `PostgrestException` — which would now surface as a readable error rather than the generic toast. In practice, admins (the only users who can restore) are unlikely to hold contributor permissions, making this a rare edge case. Worth documenting for future investigation, but not a blocker.

**S-2 — Tier 1/Tier 2 SQL verification not executable in QA session**

The Architect Plan §15 defines SQL verification queries to run pre- and post-deployment against the production database. These cannot be executed in a QA code-review session. The Engineer confirmed pre-deploy observations against the source SQL (the `delete_band` function body was read directly and compared). Post-deploy Tier 2 queries must be run by the engineer or release owner after `supabase db push` succeeds.

---

## QA Sign-off

Reviewed by: QA Agent  
Date: 2026-06-07  
Branch: `bug/restore-fails-after-band-deletion`  
Validation method: Code-path analysis — full `git diff` review, direct file reads, `flutter analyze`
