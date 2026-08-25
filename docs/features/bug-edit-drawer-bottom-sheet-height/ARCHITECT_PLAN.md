# Feature Slug

bug/edit-drawer-bottom-sheet-height

# Problem Summary

The edit-mode bottom drawers for band members and songs do not expand tall enough to reveal all content. The corresponding view/detail drawers already use the larger sheet height ratios and behave correctly. This is a layout sizing bug confined to edit screens: the content is already scrollable, but the sheet ceiling is too low, so users cannot reach the lower controls or fields without the sheet extending farther.

The concrete failure modes are:

- `BandMemberEditDrawer.show()` calls `showAppBottomSheet()` without a `mainAxisMaxRatio`, so it falls back to the wrapper default of `9/16` (~56% of screen height).
- `SongDetailsBottomSheet` uses a raw `showModalBottomSheet` with a fixed `maxHeight: screenHeight * 0.85` for both view and edit modes, even though edit mode contains more fields and actions.

The expected behavior is that edit-mode sheets extend to the same near-full-height envelope already used by the sibling view/detail drawers, with content scrolling once the maximum height is reached. The view/detail drawers must remain unchanged.

# Root Cause

Primary root cause: the edit-mode drawers are using a lower maximum height than the sibling view/detail drawers and a lower-than-expected default inside the shared sheet wrapper.

Confidence: HIGH

Evidence from code inspection:

- `lib/features/contacts/widgets/band_member_edit_drawer.dart` does not pass `mainAxisMaxRatio` to `showAppBottomSheet()`. The shared wrapper defaults to `9/16` (`app_bottom_sheet.dart`), which is far smaller than the sibling view drawer's explicit `0.95` ratio.
- `lib/features/contacts/widgets/band_member_detail_drawer.dart` explicitly uses `mainAxisMaxRatio: 0.95` and wraps the body in `SingleChildScrollView`, which confirms the intended pattern: a taller sheet with scrolling.
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart` uses `maxHeight: screenHeight * 0.85` in both read-only and edit modes, even though edit mode contains more visible content; the body is also wrapped in `SingleChildScrollView` and therefore is designed to scroll once the sheet reaches its ceiling.

This is not a data issue, not a permission issue, and not a dependency issue. It is a fixed-height ceiling mismatch in the UI layer.

# Reference Docs Consulted

The notification reference docs were reviewed for completeness because the overall repo policy requires architecture review for all work and cross-checking of intended patterns. They are not implicated in this bug because the issue is UI drawer sizing only.

Files read:

- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md`
- `docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `docs/reference/notifications/notifications.md`

Conclusion: the notification system is unrelated to this bug; no notification trigger, token, or permission logic is involved.

# Existing System Analysis

Current behavior:

1. Band member edit drawer
   - `BandMemberEditDrawer.show()` opens via `showAppBottomSheet()`.
   - It does not specify `mainAxisMaxRatio`, so the default `9/16` is used.
   - The widget content is a scrollable body, but the maximum height cap is too low for the number of permission toggles and controls in edit mode.
   - The corresponding view drawer explicitly uses `mainAxisMaxRatio: 0.95`, which is the working precedent and the correct target.

2. Song details sheet
   - `SongDetailsBottomSheet` is not using the shared wrapper; it uses raw `showModalBottomSheet`.
   - In `build()`, `maxHeight` is set to `screenHeight * 0.85` for both view and edit modes.
   - Edit mode has additional inline editing and action controls, yet the cap stays fixed at 85% instead of allowing a fuller screen height.
   - The body is already wrapped in `SingleChildScrollView`, which is the correct pattern once the articulating height ceiling is raised.

3. Existing app precedent
   - `lib/features/calendar/widgets/add_block_out_drawer.dart` uses `mainAxisMaxRatio: 1.0` for create/edit-type drawers.
   - `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` uses `mainAxisMaxRatio: 1.0` for edit/create-type sheets.
   - `BandMemberDetailDrawer.show()` uses `mainAxisMaxRatio: 0.95` for the view/detail drawer. This strongly establishes the intended pattern: edit/create modes should be taller than the default and should use near-full-screen heights where content requires it.

Data flow: no persistent model updates or backend calls are involved in the bug. This is purely a presentation constraint in the UI layer. The sheet decides its maximum height before rendering, and the body scrolls within that cap.

# Proposed Solution

Implement the smallest fix that raises the edit-mode sheet ceilings without changing the corresponding view/detail behavior.

Proposed changes:

- In `BandMemberEditDrawer.show()`, pass `mainAxisMaxRatio: 0.95` to `showAppBottomSheet()`. This matches the sibling detail drawer's proven behavior and keeps the intent consistent: near-full-height editing, with content scrolling inside the sheet.
- In `SongDetailsBottomSheet`, set the max-height ceiling for edit mode specifically to the same value (`0.95`) rather than the uniform `0.85` used for both modes.

Why this is the correct fix:

- It is consistent with the established app precedent for taller edit/create drawers.
- It keeps view/detail behavior unchanged because the read-only path stays at its current compact ratio or identical settings.
- It fixes the actual root cause: the edit sheet is limited before the content can fully render.
- It respects the existing scroll pattern already implemented in each sheet.

What must not change:

- No changes to view/detail drawers beyond preserving their current behavior.
- No broader refactor from `showModalBottomSheet` to the shared wrapper in the song sheet; that is outside scope.
- No unrelated UI cleanup or sheet-chrome changes.

# Database Impact

Database: not applicable.

There is no schema, migration, RLS, trigger, or RPC change involved in this fix. The issue is restricted to widget sizing and max-height constraints in Flutter UI code. No database writes or reads need to be altered to fix the behavior.

# Flutter Architecture Changes

State:

- No state-management architecture change is needed.
- No provider or controller changes are required.

Widgets:

- `BandMemberEditDrawer.show()` will receive a `mainAxisMaxRatio` parameter.
- `SongDetailsBottomSheet` edit-mode `Container`/`ModalBottomSheet` constraints will use a higher max height for the edit variant only.

Repositories / persistence:

- No repository or data-layer change is required.

# Files to Create

none

# Files to Modify

| File                                                           | What changes                                                                                                                         |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/contacts/widgets/band_member_edit_drawer.dart`   | Add `mainAxisMaxRatio: 0.95` to the `showAppBottomSheet()` call in `BandMemberEditDrawer.show()`.                                    |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Raise the max-height limit for `isReadOnly == false` edit mode to match the taller drawer ratio and keep view/detail mode unchanged. |

# Files Off-Limits

| File                                                                            | Reason                                                                                                                  |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                                                 | Initialization order must not change.                                                                                   |
| `lib/components/ui/app_bottom_sheet.dart`                                       | This is the shared wrapper; changing its default globally would impact every other sheet and is beyond the bug's scope. |
| `lib/features/contacts/widgets/band_member_detail_drawer.dart`                  | View/detail drawer must remain unchanged.                                                                               |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` read-only branch | The view mode is intentionally not changed.                                                                             |
| `pubspec.yaml`                                                                  | No dependency or package changes are required.                                                                          |

# System Impact Map

| System                                 | Impact                                                        |
| -------------------------------------- | ------------------------------------------------------------- |
| Gigs                                   | unaffected                                                    |
| Rehearsals                             | unaffected                                                    |
| Setlists / Catalog                     | affected (song detail edit sheet only)                        |
| Members / RBAC                         | affected (band member edit drawer only)                       |
| Auth / Session                         | unaffected                                                    |
| Routing                                | unaffected                                                    |
| Notifications                          | unaffected                                                    |
| Platform (iOS / Android / Web / macOS) | affected only in UI layout behavior; no platform logic change |

# Regression Risk

Regression risk: LOW

Reasoning:

- The change is limited to explicit edit-mode max-height values.
- The view/detail drawer behavior is deliberately preserved.
- No persistence, auth, routing, or database logic is modified.
- The edit sheets already use scroll containers, so the fix is to increase the available height rather than change the underlying content or state logic.

# Engineer Task Breakdown

1. Update `BandMemberEditDrawer.show()` to pass `mainAxisMaxRatio: 0.95` to the shared bottom sheet wrapper.
2. Update the song details sheet edit-mode height logic so it uses a taller ceiling than the fixed 0.85 formula while leaving the read-only path alone.
3. Verify the generated UI still respects scroll behavior and no view/detail drawer changes were introduced.
4. Run the project’s verification commands required by the repo and QA checklist.
5. Confirm there are no unrelated file changes.

# Verification Plan

## Tier 1 — Pre-deployment (must pass before any release or database push)

Because this bug is a Flutter-only UI fix with no database migration, the pre-deployment checks are code and layout validation rather than SQL validation.

- `-- PRE-DEPLOY TEST 1:` Run `flutter analyze` from the repo root and confirm it exits cleanly with no analyzer errors.
- `-- PRE-DEPLOY TEST 2:` Run `flutter test` for the full test suite and confirm all tests pass.
- `-- PRE-DEPLOY TEST 3:` Open the Band Member edit drawer with enough sub-permission toggles to be tall; confirm the sheet expands to the larger height and the lower controls remain reachable via scroll.
- `-- PRE-DEPLOY TEST 4:` Open the Song edit sheet with a song that has notes/lyrics/all fields populated; confirm the sheet expands to the taller edit-mode limit and content remains reachable via scroll.

## Tier 2 — Post-deployment (run after release / deployment passes)

- `-- POST-DEPLOY TEST 1:` Re-open the Band Member edit drawer and confirm it still extends taller than before without altering the sibling detail drawer.
- `-- POST-DEPLOY TEST 2:` Re-open the Song details sheet in edit mode and confirm the edit-mode sheet is taller than the view mode while both remain scrollable.
- `-- POST-DEPLOY TEST 3:` Re-open both corresponding view/detail drawers and confirm their appearance and scroll behavior remain unchanged.
- `-- POST-DEPLOY TEST 4:` Verify no unexpected regressions appear in adjacent sheet flows that already use the same pattern (e.g., add/edit event and block-out drawers), while ensuring the fix remains scoped to the named files only.

# QA Regression Areas

QA must specifically validate:

- Band Member edit drawer height in edit mode with many contributor toggles.
- Song details edit sheet height in edit mode with all available fields filled.
- View/detail drawers remain visually and behaviorally unchanged.
- Vertical scrolling still works smoothly once each sheet reaches its ceiling.
- The fix is limited to edit mode; read-only drawers must not become taller or visually different.

# Rollout / Migration Strategy

No migration is required.

This is a UI-only fix with no schema changes, no RLS policy changes, and no data migration. The rollout is a standard application release with no special database rollout or rollback step.

# Out of Scope

- Any other bottom sheet or drawer in the app not named in the fix.
- The `forui` 0.25.0 → 0.26.0 upgrade work.
- Cleanup or refactoring between raw `showModalBottomSheet` usage and the shared `showAppBottomSheet` wrapper outside this bug.
- Changing the view/detail sheet behavior or screen geometry for read-only mode.
- Any work that broadens the fix beyond the two named files.

# Final Output

The plan fixes the root cause by aligning edit drawers with the app’s taller-sheet precedent while preserving read-only behavior. The issue is isolated to fixed max-height constraints in the UI layer, not to data or persistence. The implementation is intentionally limited to the two affected files and follows the existing scrollable-sheet pattern already proven elsewhere in the app.
