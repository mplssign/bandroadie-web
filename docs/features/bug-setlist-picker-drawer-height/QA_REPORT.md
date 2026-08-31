# QA Report

## Feature Slug

bug/setlist-picker-drawer-height

## Feature Title

Setlist Picker Bottom Sheet — Raise `maxHeight` Cap From 70% To 85% Of Screen Height

## Final Verdict

**APPROVED**

## Validation Summary

Validated against the Architect plan by inspecting `git diff` directly, reading the modified file and its surrounding layout code, confirming the two call sites in `setlist_detail_screen.dart` are untouched, confirming all named off-limits sibling sheets are untouched, and running `flutter analyze` and `flutter test`. The diff is exactly one hunk in one file changing the single character sequence `0.7` → `0.85` on the `maxHeight` line inside `_SetlistPickerSheetState.build()`, matching the Architect's Engineer Task Breakdown to the letter. Runtime layout behavior (Pre-Deploy Tests 3–5) was not exercised in this session; validation is via code-path analysis, as the Architect plan explicitly leaves manual sheet-layout checks to release-time smoke testing.

## Architect Scope Review

- Scope adherence: **compliant**
- Files modified: **as expected** — exactly `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`, matching the single row in the Architect's "Files to Modify" table.
- Files off-limits: **not touched** — verified via `git diff --name-only`:
  - `lib/main.dart` — unchanged
  - `lib/components/ui/app_bottom_sheet.dart` — unchanged (Forui `mainAxisMaxRatio` default still `9/16`)
  - `lib/features/setlists/setlist_detail_screen.dart` — unchanged; both call sites at lines 377 (`_handleMoveOrCopySong`) and 1400 (`_handleAddToSetlist`) still pass `selectedSongCount`, `sourceSetlistId`, `sourceSetlistName` unchanged and only `await` the `SetlistPickerResult`
  - `lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart` — unchanged
  - `lib/features/setlists/widgets/song_details_bottom_sheet.dart` — unchanged
  - `lib/features/contacts/widgets/band_member_edit_drawer.dart` — unchanged
  - `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart` — unchanged (verified as untouched via `git diff --name-only`)
  - `pubspec.yaml`, `pubspec.lock` — unchanged
  - `supabase/`, `sql/`, `database/` — unchanged

## Completeness Check

- All Architect tasks implemented: **yes**
- Missing tasks: none
  - Task 1 (open file): ✓
  - Task 2 (locate `BoxConstraints` in `_SetlistPickerSheetState.build()`): ✓ single occurrence, line 253
  - Task 3 (change `0.7` → `0.85`, no other characters): ✓ diff shows one line replaced, no whitespace/comment/import churn
  - Task 4 (no import changes): ✓
  - Task 5 (no other files modified): ✓
  - Task 6 (`flutter analyze`): ✓ 0 issues
  - Task 7 (`flutter test`): ✓ 176/176 passing
  - Task 8 (`git diff` shows exactly one hunk in one file): ✓ verified — `git diff --stat` reports `1 file changed, 1 insertion(+), 1 deletion(-)`

## Behavior Verification

- Validation method: **code-path analysis** (no runtime device testing in this session)
- Result: **matches expected**

Layout invariants required by the Architect plan's "QA Regression Areas" verified in code:

- **Safe-area clearance (top/bottom, all platforms):** `showSetlistPickerBottomSheet` still passes `useSafeArea: true` to `showAppBottomSheet` (line 96). The outer `Container` still has `margin: const EdgeInsets.all(16)` (line 251) providing an additional 16 px inset. Bottom padding inside `_buildSetlistList` and `_buildCreateNewForm` is still `MediaQuery.of(context).padding.bottom + 8` (lines 476 and 574). None of these were touched.
- **Keyboard-inset behavior on Create New Setlist form:** `AnimatedPadding` at line 248 with `padding: EdgeInsets.only(bottom: keyboardHeight)` where `keyboardHeight = MediaQuery.of(context).viewInsets.bottom` sits **outside** the constrained `Container`, so the entire sheet slides above the software keyboard independently of the new `0.85` cap. `_buildCreateNewForm` layout, `AppTextField` `autofocus: true`, and Cancel / Create & Add buttons are byte-for-byte identical.
- **Move/Copy path (non-Catalog source):** `_handleMoveOrCopySong` (`setlist_detail_screen.dart:371`) still forwards `sourceSetlistId`/`sourceSetlistName`, so `_buildHeader`'s `showToggle = widget.sourceSetlistId != null && !isSourceCatalog` guard still fires and `_buildMoveCopyToggle()` still renders. Toggle option `_isMoveMode` state and `SetlistPickerResult.existing(isMoveMode: _isMoveMode)` / `SetlistPickerResult.createNew(isMoveMode: _isMoveMode)` propagation are unchanged.
- **Small-content behavior with the new cap:** `Column(mainAxisSize: MainAxisSize.min)` at line 261 and `_buildSetlistList`'s inner `Column(mainAxisSize: MainAxisSize.min)` at line 409 both remain, so with few setlists the sheet renders shorter than the cap. `BoxConstraints.maxHeight` is a ceiling, not a floor — raising it from 0.7 to 0.85 cannot force a small sheet to grow.
- **Empty state:** with zero non-Catalog setlists, `_buildSetlistList` still renders the "No setlists yet" `Padding(EdgeInsets.all(Spacing.space24)) → Column` block (lines 428–457), which is intrinsically small and unaffected by the taller cap.
- **Cross-platform:** the widget contains no platform branching; the single constant change applies uniformly to iOS, Android, macOS, and Web.
- **Sheet reaches ~85% cap under load:** cannot be measured via static analysis in this session — verified logically as the direct literal replacement the Architect specified. Manual smoke check on at least one platform (Tier 1 Pre-Deploy Test 3) is still recommended before release, consistent with the Architect's Verification Plan.

## Regression Check

- Risk level: **LOW**
- Systems reviewed (from Architect System Impact Map):
  - Gigs — not touched
  - Rehearsals — not touched
  - Setlists / Catalog — affected only in the "Add To Setlist" picker sheet's max visible height, as designed
  - Members / RBAC — not touched
  - Auth / Session — not touched
  - Routing — not touched
  - Notifications — not touched
  - Platform (iOS / Android / Web / macOS) — no platform branching added or changed
- Additional guardrail sweep (`docs/agents/GUARDRAILS.md`):
  - Initialization order (`lib/main.dart`) — unchanged
  - Config sources / `--dart-define` — unchanged
  - Supabase RPC signatures / RLS — not applicable, no backend touched
  - Async lifecycle (`mounted` guards, controller disposal): `_animController`, `_newNameController`, `_newNameFocus` all disposed in `dispose()` (lines 172–176); `_handleSelectSetlist`, `_handleConfirmCreate` are synchronous and pop before any async gap
  - Rebuild discipline: `ListView.builder(shrinkWrap: true)` inside `Flexible` still present; no scan of full lists introduced
- Regressions found: **none**

## Database Safety

**Not applicable.** No migration, RLS policy, RPC, trigger, or edge function is involved. This is a client-only UI constant change. `supabase/`, `sql/`, and `database/` directories are untouched.

## Analyzer Results

Command: `flutter analyze`
Result: **0 errors, 0 warnings, 0 infos** — `No issues found! (ran in 3.1s)`.

## Test Results

Command: `flutter test`
Result: **Passed** — `All tests passed!` `+176`. No new failures.

## Diff Safety Review

- Secrets: **none found**
- Debug artifacts (print statements, TODO hacks, temporary flags): **none found**
- Unrelated changes: **none found** — `git diff` shows exactly one hunk on one line: `maxHeight: MediaQuery.of(context).size.height * 0.7,` → `maxHeight: MediaQuery.of(context).size.height * 0.85,`. No imports, comments, whitespace, or reflow changes.
- Config / env vars outside approved scope: none
- Accidental file deletions: none

## Code Efficiency Review

- Dead code / unused imports, vars, params: **none found** — no symbols added or removed
- Redundant restating comments: **none found** — no comments added
- Unnecessary abstraction for single call sites: **none found** — no new helpers, wrappers, or indirection
- Unneeded defensive checks (impossible-case guards, try/catch): **none found**
- Duplicated logic that should reuse existing code: **none found**
- Overall assessment: **lean** — the minimum possible diff (one numeric literal) that satisfies the plan

## Issues Found

None.

### Observations (informational, not blocking)

1. The change is currently **uncommitted** on `bug/setlist-picker-drawer-height` (`git status` shows `M lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`; `git log main..HEAD` is empty). QA validated the working-tree diff as-is. Before pushing / opening a PR, the engineer must commit the change per `docs/agents/GUARDRAILS.md` §10 (Git Discipline) and the COMMIT_GATE protocol.
2. Runtime layout behavior (Pre-Deploy Tests 3–5 in the Verification Plan) was not exercised in this QA session — validation is code-path analysis only. Per the Architect plan, one manual smoke check on at least one platform (open the sheet from the Catalog with ≥10 setlists, confirm ~85% top edge and that the sheet body clears the top system inset) is recommended before release. This does not block APPROVED because the Architect explicitly leaves these steps to pre-release smoke testing and identifies no automatable substitute.
