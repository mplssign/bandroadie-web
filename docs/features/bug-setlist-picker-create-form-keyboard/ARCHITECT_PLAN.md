# Feature Slug

`bug/setlist-picker-create-form-keyboard`

# Problem Summary

From the Catalog screen in Select mode, when the user selects songs and then chooses "Create New Setlist" from the setlist picker, the sheet header is visible but the body is effectively hidden behind the keyboard. The visible header says "Create New Setlist" / "Adding N songs" with the close button, but the text field and action buttons are not rendered in the reachable area. The keyboard opens, the user can type into the invisible focused field, but cannot see or confirm the form. This blocks creation of a new setlist directly from Catalog selection.

Expected behavior: the create-new form should be visible and usable above the keyboard, with the field and the Cancel / Create & Add buttons fully visible and reachable.

Actual behavior: only the sheet header remains visible, while the body collapses into the bottom of the sheet behind the keyboard, leaving the underlying Catalog screen visible underneath.

Affected platforms: iOS is confirmed by report; the code path is shared Flutter layout logic and is likely shared with Android and web-mobile behavior as well.

# Root Cause

Primary root cause: the sheet body applies keyboard padding twice.

Confidence: HIGH

Confirmed in code:

- `showFSheet()` in the installed Forui library defaults to `resizeToAvoidBottomInset: true` and passes `bottomViewInset: MediaQuery.viewInsetsOf(context).bottom` into `ShiftedSheet` when constructing the sheet route. This means the sheet already moves itself above the keyboard.
- In `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`, `_SetlistPickerSheetState.build()` does its own `final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;` and wraps the sheet content in `AnimatedPadding(padding: EdgeInsets.only(bottom: keyboardHeight), ...)`.
- The widget then renders the form within a `Column` whose content is padded again by the sheet's own keyboard-aware positioning. The result is a shell that is vertically reduced to almost nothing, making the form effectively invisible while the header remains visible.

This is not a `mainAxisMaxRatio` bug. The sheet already sets `mainAxisMaxRatio: 0.85` through `showSetlistPickerBottomSheet()`, and that value is not the operative cause of the hidden body. The actual failure is the duplicate keyboard inset handling. The prior height-ratio fixes in this repo are related but not the same bug class.

Direct evidence from the codebase:

- `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`
  - `showSetlistPickerBottomSheet()` passes `mainAxisMaxRatio: 0.85`
  - `_SetlistPickerSheetState.build()` reads `MediaQuery.of(context).viewInsets.bottom`
  - `_buildCreateNewForm()` is rendered under a body that receives `AnimatedPadding(bottom: keyboardHeight)`
- Forui library source (`~/.pub-cache/hosted/pub.dev/forui-0.26.0/...`)
  - `showFSheet` defaults `resizeToAvoidBottomInset = true`
  - `ShiftedSheet` sets `bottomViewInset: MediaQuery.viewInsetsOf(context).bottom`
  - `constrainChild()` constrains the sheet height based on `mainAxisMaxRatio` and `bottomViewInset` without the app needing to apply an additional `AnimatedPadding` for the same keyboard adjustment

This confirms the underlying mechanism: the sheet is being repositioned once by the framework and again by the local widget.

# Reference Docs Consulted

Not applicable to the notifications domain. This bug is a Flutter UI layout issue; no notification path or preference logic is implicated.

Files reviewed for sizing precedent and prior bug-class context:

- `docs/features/bug-setlist-picker-drawer-height/ARCHITECT_PLAN.md`
- `docs/features/bug-edit-drawer-bottom-sheet-height/ARCHITECT_PLAN.md`
- `docs/features/detail-sheet-sizing-venue-back/ARCHITECT_PLAN.md`
- `lib/components/ui/app_bottom_sheet.dart`
- `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`
- installed Forui source: `~/.pub-cache/hosted/pub.dev/forui-0.26.0/lib/src/widgets/sheet/...`

# Existing System Analysis

Current flow:

1. User selects songs in Catalog and taps the sticky "Move to setlist" action.
2. `showSetlistPickerBottomSheet()` opens via `showAppBottomSheet()` with `isScrollControlled: true`, `useSafeArea: true`, and `mainAxisMaxRatio: 0.85`.
3. The Forui sheet already handles bottom inset avoidance by default (`resizeToAvoidBottomInset: true`), moving the entire sheet above the keyboard.
4. `_SetlistPickerSheetState._handleCreateNew()` sets `_isCreatingNew = true` and requests focus in a post-frame callback.
5. The keyboard appears; the sheet re-renders.
6. The widget also wraps the body in `AnimatedPadding(padding: EdgeInsets.only(bottom: keyboardHeight), ...)`, adding a second bottom offset. This makes the body effectively collapse and leaves only the header visible.
7. The underlying Catalog screen remains visible behind the sheet, which matches the report that the sheet's hit-testable area has collapsed rather than failed to open.

Important distinction:

- The sheet is not failing to render because the content is absent from the widget tree.
- The form is still present in the tree but effectively pushed out of the visible area by a duplicated keyboard offset.
- The close button remains reachable because header rendering is above the collapsed form area, while the body is displaced outside the visible sheet bounds.

# Proposed Solution

Apply the smallest fix at the actual failure point: remove the manual keyboard-based `AnimatedPadding` in `_SetlistPickerSheetState.build()` and rely on the Forui sheet's built-in keyboard avoidance behavior.

Minimal fix strategy:

- Keep `showSetlistPickerBottomSheet()` using `mainAxisMaxRatio: 0.85` and `useSafeArea: true`.
- Keep the form and action buttons in the sheet body as-is.
- Remove the widget-level `AnimatedPadding` that adds `MediaQuery.of(context).viewInsets.bottom`.
- Let Forui's `showFSheet` / `ShiftedSheet` handle the keyboard inset, which already does so via `resizeToAvoidBottomInset` and `bottomViewInset`.
- Preserve the existing logic for focus request, validation, Cancel, and Create & Add behavior.

Why this is the correct fix:

- It addresses the actual root cause rather than masking symptoms.
- It is localized to the problematic sheet widget only.
- It preserves the existing height cap and safe-area setup already deemed correct by prior bug-fix work.
- It avoids touching unrelated call sites like the Catalog screen or shared bottom-sheet wrapper.

What must not change:

- Do not alter `setlist_detail_screen.dart` or any Catalog selection flow.
- Do not change `showAppBottomSheet()` unless the investigation proves that the wrapper itself is wrong (it is not here).
- Do not change `mainAxisMaxRatio` beyond the already-correct `0.85` value.
- Do not add a new controller, provider, or repository for this UI-only bug.

# Database Impact

`Database: not applicable`

No schema, migration, RLS policy, RPC, trigger, edge-function, or auth change is required. This is a client-side layout bug in a Flutter sheet widget.

- Migrations: not required
- Edge function deploy: not required
- RLS policies: unaffected
- RPC signatures: unaffected
- Triggers: unaffected

# Flutter Architecture Changes

No architecture change is needed.

- State management: unchanged
- Repositories: unchanged
- Routing: unaffected
- Init order: unaffected
- Widget structure: only the sheet's keyboard padding behavior is adjusted

# Files to Create

none

# Files to Modify

| File                                                             | What changes                                                                                                                                                                                                                                                                           |
| ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` | Remove the extra keyboard-driven `AnimatedPadding` in `_SetlistPickerSheetState.build()`, allowing Forui's default keyboard avoidance to handle inset adjustments without double-applying the inset. Preserve the existing `mainAxisMaxRatio: 0.85`, safe-area, and create-form logic. |

# Files Off-Limits

| File                                               | Reason                                                                                             |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart` | Caller flow and selection logic are not the root cause and should remain unchanged.                |
| `lib/components/ui/app_bottom_sheet.dart`          | The shared wrapper is behaving as designed; the bug is in the local sheet widget, not the wrapper. |
| `lib/main.dart`                                    | Initialization order must not change.                                                              |
| `pubspec.yaml`                                     | No dependency change is required.                                                                  |
| `supabase/` and `sql/`                             | No backend change is involved.                                                                     |

# System Impact Map

| System                                 | Impact                                                            |
| -------------------------------------- | ----------------------------------------------------------------- |
| Gigs                                   | unaffected                                                        |
| Rehearsals                             | unaffected                                                        |
| Setlists / Catalog                     | affected (only the Catalog selection “Create New Setlist” prompt) |
| Members / RBAC                         | unaffected                                                        |
| Auth / Session                         | unaffected                                                        |
| Routing                                | unaffected                                                        |
| Notifications                          | unaffected                                                        |
| Platform (iOS / Android / Web / macOS) | affected in layout behavior only; no platform branching change    |

# Regression Risk

Regression risk: MEDIUM

Reasoning:

- This is a keyboard-layout fix in a shared bottom-sheet path used by several setlist flows.
- The bug is in a single widget, but the fix changes how the sheet reacts to keyboard insets, which can affect all bottom-sheet interactions in the same screen family.
- The fix is still narrow and does not change persistence, auth, routing, or global sheet architecture.

# Engineer Task Breakdown

1. Open `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`.
2. Confirm the extra `AnimatedPadding(bottom: keyboardHeight)` is the only local keyboard inset adjustment in the sheet.
3. Remove the extra keyboard padding from the outer sheet body while keeping the form and action button layout intact.
4. Preserve `mainAxisMaxRatio: 0.85` and `useSafeArea: true` on the sheet invocation.
5. Check that the form remains visible above the keyboard, the cancel button remains reachable, and the create flow still validates and saves correctly.
6. Run the repo’s required validation commands and confirm no unrelated files are touched.

# Verification Plan

## Tier 1 — Pre-deployment (must pass before any release)

- `-- PRE-DEPLOY TEST 1:` Run `flutter analyze` and confirm zero analyzer issues.
- `-- PRE-DEPLOY TEST 2:` Run `flutter test` and confirm the existing test suite passes without regressions.
- `-- PRE-DEPLOY TEST 3:` Manual reproduction from the Catalog Select flow:
  1. Open Catalog
  2. Select multiple songs
  3. Tap "Move to setlist"
  4. Tap "Create New Setlist"
  5. Confirm the name field and action buttons are fully visible above the keyboard
- `-- PRE-DEPLOY TEST 4:` Manual keyboard regression check:
  1. Repeat the flow with the keyboard open
  2. Confirm the sheet no longer collapses or leaves the body hidden
  3. Confirm the field stays visible and the user can finish creating the setlist
- `-- PRE-DEPLOY TEST 5:` Regression check for the existing setlist picker list state:
  1. Open the sheet without keyboard
  2. Confirm the list view still renders and selection behavior remains unchanged

## Tier 2 — Post-deployment (run after release)

- `-- POST-DEPLOY TEST 1:` Validate on iOS that the Catalog Create New Setlist flow works in a real device build.
- `-- POST-DEPLOY TEST 2:` Validate on Android and web-mobile that the same create-form is visible and usable above the keyboard.
- `-- POST-DEPLOY TEST 3:` Confirm that the reopen/close behavior remains stable across repeated sheet openings.
- `-- POST-DEPLOY TEST 4:` Confirm the existing setlist list and “Create New Setlist” entry still work for non-Catalog setlist selection flows.

# Engineer Notes

This bug is not a database bug and does not require any migration or backend change. The fix belongs in the UI sheet widget itself and should avoid any broader refactor or change to the shared bottom-sheet wrapper.
