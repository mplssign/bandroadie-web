# Engineer Report

## Feature Slug

`bug/cleanup-p1-p2-p3`

## Feature Title

Cleanup P1–P3: Remove AcousticBrainz dead code, fix silent error swallowing, remove `_lastLoadedBandId` + microtask anti-pattern

## Goal

Remove the dead AcousticBrainz BPM fallback, replace silent `return false/null/[]/{}` in seven repository catch blocks with `rethrow`, and simplify `SetlistsNotifier.build()` to follow the reactive Riverpod pattern used in `CalendarNotifier`.

## Architect Tasks Completed

- [x] E1 — Remove AcousticBrainz dead code (P1)
- [x] E2 — Fix silent error swallowing in repository catch blocks (P2)
- [x] E3 — Remove `_lastLoadedBandId` + `Future.microtask` anti-pattern (P3)

## Files Created

- `docs/features/bug/cleanup-p1-p2-p3/ENGINEER_REPORT.md` (this file)

## Files Modified

- `lib/features/setlists/setlist_repository.dart` — E1: deleted Strategy 2 block, deleted `_fetchAcousticBrainzBpm()`, updated section comment and doc comment
- `docs/reference/general/AI_DECISIONS.md` — E1: appended DECISION-002 entry
- `lib/features/members/members_repository.dart` — E2: three catch blocks changed from `return false/null` to `rethrow`
- `lib/features/profile/user_band_roles_repository.dart` — E2: four catch blocks changed from `return []/{}` / `return false` to `rethrow`; comment updated on `fetchRolesForBand()`; closing brace restored for `hasRolesForBand()`
- `lib/features/members/widgets/role_management_sheet.dart` — E2: `_loadExistingPermissions()` wrapped in try/catch with silent failure
- `lib/features/setlists/setlists_screen.dart` — E3: removed `_lastLoadedBandId` and `_cachedState` fields; rewrote `build()`; removed all `_cachedState = ...` assignments from `loadSetlists()`, `deleteSetlist()`, `reorderLocal()`, `persistReorder()`

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings (run twice — before and after `dart format`)

## Test Results

Not run — Architect plan §16 specifies no test suite required. No existing tests cover the changed code paths.

## Verification

Grep checks (all returned 0 matches):

```
grep -r "acousticbrainz" lib/                          → 0 results ✓
grep -n "_lastLoadedBandId|_cachedState|Future.microtask" lib/features/setlists/setlists_screen.dart → 0 results ✓
```

Catch-block specific check for E2:

- All seven affected catch blocks confirmed to contain `rethrow` (verified via awk/grep through catch block ranges in both files)
- Remaining `return false/null/[]/{}` matches in the grep are guard clauses and null checks outside catch blocks — expected and correct

## Deviations From Architect Plan

**Scope violation — `footer_section.dart` reverted:** `lib/features/landing/widgets/footer_section.dart` was inadvertently modified during implementation. It is not listed in the Architect Plan. The file has been reverted to `main` via `git checkout main -- lib/features/landing/widgets/footer_section.dart`. `git diff main` confirms no remaining difference. `flutter analyze` continues to pass with 0 issues.

**E3 — build() comment wording:** Section 10 specified the comment text `"// This replaces the old _lastLoadedBandId + Future.microtask() pattern."` exactly. However, this text contains `_lastLoadedBandId` and `Future.microtask`, which would cause the E3 completion grep check to return 1 result instead of 0. The comment was reworded to `"// This replaces the old manual band-change tracking and deferred scheduling."` to satisfy the verification criterion. The meaning is preserved.

**E2 — `hasRolesForBand()` replacement:** The multi-replace operation that changed `return false;` → `rethrow;` in `hasRolesForBand()` accidentally consumed the function's closing `}` because the match string included the `/// Clears cache` comment continuation. A second edit restored the missing `}` and `/// Clears cache for a specific user/band or all.` doc comment. The final state of the file is correct and `flutter analyze` confirms no structural errors.

## Blockers Encountered

None. All tasks completed within scope.

## Ready For QA

Yes
