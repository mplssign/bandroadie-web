# QA Report

## Feature Slug
`one-calendar-manual-blackout`

## Feature Title
Fix: Manual blackout dates not propagating with One Calendar enabled

## Final Verdict
**APPROVED**

## Validation Summary
All validation was performed via code-path analysis against `git diff main`, direct file reads, and `flutter analyze`. The implementation consists of a single diff in `event_editor_drawer.dart` — two new imports and a 28-line propagation block inserted at the Architect-specified location. All 10 QA regression areas pass. No off-limits files were modified. The analyzer reports 0 issues.

---

## Architect Scope Review
- Scope adherence: **compliant**
- Files modified: **as expected** — only `lib/features/events/widgets/event_editor_drawer.dart`
- Files off-limits: **not touched** — confirmed via `git diff main -- [all off-limits paths]` producing empty output

---

## Completeness Check
- All Architect tasks implemented: **yes**
- Missing tasks: none

**Task 1** — Two imports added at correct positions in the import block (lines 15 and 19 of the modified file), maintaining alphabetical grouping.

**Task 2** — Propagation block inserted verbatim (with cosmetic `dart format` reflow noted in Engineer Report) after the `if (_isEditMode) { … } else { … }` block and before the `// Refresh calendar` comment. Confirmed at lines 1090–1116.

**Task 3** — `flutter analyze` run and confirmed 0 errors.

---

## Behavior Verification
- Validation method: **code-path analysis**
- Result: **matches expected**

### QA Regression Area Results

**1. Manual blockout creation — primary path (One Calendar ON)**
- Checked: Propagation block (lines 1090–1116) fires after the primary `createBlockOut()` for `widget.bandId`. Iterates `otherBandIds` and calls `repository.createBlockOut()` for each with identical parameters (`startDate`, `untilDate`, `reason`, `userId`).
- Found: Implementation correct. Primary write is unchanged; propagation is additive.
- **PASS** (code-path analysis)

**2. One Calendar off — no propagation**
- Checked: `getBandIdsToApplyBlockOut()` implementation in `one_calendar_preferences_repository.dart` (lines 95–138). When `prefs.oneCalendarEnabled == false`, returns `[]` immediately (lines 106–111). When `bandIds = []`, `otherBandIds = []`, the for-loop body never executes — zero additional writes.
- Found: Off-path is a confirmed no-op. No writes, no side effects.
- **PASS** (code-path analysis)

**3. Selected bands mode — excluded band not propagated**
- Checked: `getBandIdsToApplyBlockOut()` lines 122–130 — computes intersection of `selectedBandIds` and `userBandIds`. A band not in `selectedBandIds` is absent from the returned list and therefore absent from `otherBandIds`.
- Found: Selected-bands exclusion logic is in the repository (unchanged), called correctly by the propagation block.
- **PASS** (code-path analysis)

**4. Multi-day range propagation**
- Checked: The propagation block passes `untilDate: _blockOutUntilDate` to each `repository.createBlockOut()` call — the same field as the primary call. `BlockOutRepository.createBlockOut()` is unchanged; it handles the date range identically regardless of caller.
- Found: All days in a range propagate correctly.
- **PASS** (code-path analysis)

**5. Gig propagation regression**
- Checked: `git diff main` output shows zero changes outside `event_editor_drawer.dart`. `AutoConflictBlockingService`, `events_repository.dart`, and `BlockOutRepository` are all unmodified.
- Found: Gig path is completely unaffected.
- **PASS** (confirmed via diff)

**6. Primary save not broken by propagation failure**
- Checked: The propagation block (lines 1092–1116) is wrapped in an outer try-catch (lines 1092/1114) that catches without re-throwing. Individual per-band failures are also caught by the inner try-catch (lines 1100/1108–1112). Neither catch block re-throws. Execution continues to the calendar refresh (line 1118) and the success snackbar (line 1127) regardless of propagation outcome. The function's outer try-catch (line 1057/1132) only triggers if something BEFORE or AFTER the propagation block throws.
- Found: Propagation failure is fully isolated. Primary save and success UI path are preserved.
- **PASS** (code-path analysis)

**7. Edit mode — known limitation documented**
- Checked: The propagation block is placed AFTER the `if (_isEditMode) { … } else { … }` block, per Architect Task 2. This means propagation also fires in edit mode. In edit mode it will attempt new writes to other bands:
  - If date range unchanged: unique constraint `(user_id, band_id, date)` fires → inner try-catch catches silently → no change in other bands.
  - If date range changed: new rows are created in other bands for the new dates; old rows remain.
- Found: This is the Architect-approved placement and a documented Out of Scope limitation. The propagated copy in Band B is NOT synced to the edited version (old rows persist). No regression introduced; behavior is an accepted known gap.
- **PASS** — known limitation per Architect plan; confirmed as documented Out of Scope

**8. Delete — scoped to current band only**
- Checked: `_deleteBlockOut()` (lines 1140–1209) — unchanged in diff. Calls `repository.deleteBlockOutSpan()` with only `widget.bandId`. No propagation block added to delete path.
- Found: Delete remains band-scoped. Cross-band delete is explicitly Out of Scope per Architect plan.
- **PASS** (code-path analysis)

**9. RBAC — contributor guard intact**
- Checked: `_saveBlockOut()` lines 1027–1041 — checks `perms?.isContributor == true` and returns early (before reaching the outer `try` block at line 1057). The propagation block at line 1092 is inside the outer `try`. Contributors exit before the outer `try` is reached.
- Found: RBAC guard is completely unaffected; contributors are still blocked before any write or propagation attempt.
- **PASS** (code-path analysis)

**10. `flutter analyze` — 0 errors**
- Checked: Ran `flutter analyze` directly.
- Found: "No issues found! (ran in 4.0s)"
- **PASS**

---

## Regression Check
- Risk level: **LOW**
- Systems reviewed: Calendar/Block Dates (write path), Gigs, RBAC/Permissions, Auth/Session, Routing, Initialization order, Disposal/Lifecycle
- Regressions found: **none**

The change is confined to a single method in one file. The propagation block is non-blocking by construction. All surrounding code is unmodified. No new providers, state objects, or database objects were introduced.

---

## Database Safety
**Not applicable** — no migrations, no RLS changes, no schema modifications. Pre-existing RLS on `block_dates` already permits cross-band INSERT (confirmed by gig propagation path). No new database objects introduced.

---

## Analyzer Results
Command: `flutter analyze`
Result: **0 errors, 0 warnings** — "No issues found! (ran in 4.0s)"

---

## Test Results
**Not run** — no automated tests cover `_saveBlockOut()`. Architect plan did not require `flutter test`. Engineer Report confirms this was not run.

---

## Diff Safety Review
- Secrets: **none found**
- Debug artifacts: **none** — two `debugPrint` calls in the propagation block match the existing logging pattern throughout the file (30+ existing `debugPrint` calls). `debugPrint` is Flutter's standard guarded logging mechanism, appropriate for error reporting in catch blocks.
- Unrelated changes: **none** — diff is exactly 2 imports + 28-line propagation block, totalling 31 added lines. No formatting churn outside the inserted block.

---

## Issues Found
None

### Known Limitations (from Architect plan — Out of Scope, not issues)
1. **Edit mode propagation behavior** — When a blockout is edited in Band A, the propagation block fires and may create additional rows in other bands with the new date range. Old rows in other bands are not cleaned up. This is the accepted behavior given the Architect-specified insertion point and the documented Out of Scope status of cross-band edit sync.
2. **Delete does not propagate** — Deleting a blockout in Band A leaves the propagated copy in Band B intact. Accepted per Architect Out of Scope.
3. **No retroactive backfill** — Existing manual blockouts created before this fix are not propagated. Accepted per Architect Out of Scope.
