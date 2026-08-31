# Feature Slug

bug/setlist-picker-drawer-height

# Problem Summary

The "Add To Setlist" bottom sheet — shown when the user selects one or more songs (in the Catalog or a setlist) and taps "Add To Setlist" to pick a destination setlist or create a new one — is capped at 70% of screen height. This leaves noticeable unused vertical space between the sheet's top edge and the status bar/system inset, and it forces the internal setlist list to scroll sooner than necessary even when there is ample room to display more rows.

Expected behavior: the sheet's `maxHeight` constraint is raised to 85% of screen height. The sheet must still respect the existing safe-area handling (`useSafeArea: true` passed to `showAppBottomSheet`) and the existing keyboard-inset handling (`AnimatedPadding` driven by `MediaQuery.of(context).viewInsets.bottom`) with no other layout changes.

Actual behavior: `maxHeight` is `MediaQuery.of(context).size.height * 0.7`, so the sheet stops at ~70% of the screen even when content and safe-area headroom would allow more.

# Root Cause

Primary root cause: a single hardcoded `BoxConstraints.maxHeight` factor of `0.7` inside `_SetlistPickerSheetState.build()` in [lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart](lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart#L253) caps the sheet's overall height below the intended envelope.

Confidence: HIGH

Evidence from code inspection:

- [lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart](lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart#L253) contains:

  ```dart
  constraints: BoxConstraints(
    maxHeight: MediaQuery.of(context).size.height * 0.7,
  ),
  ```

  This constraint is applied directly to the outer `Container` of the sheet body. Because the outer Column uses `mainAxisSize: MainAxisSize.min` and the content is wrapped in `Flexible`, the effective sheet height is governed by this max cap once content exceeds the cap. No larger height constraint exists upstream in this widget.

- A repository-wide grep for `0.7` inside this file returns exactly one match (line 253). A grep for `useSafeArea` returns only the `useSafeArea: true` argument in `showSetlistPickerBottomSheet`. There is no other height-governing factor in this file.

- The wrapper [showAppBottomSheet](lib/components/ui/app_bottom_sheet.dart#L17) uses Forui's `showFSheet` with a `mainAxisMaxRatio` parameter. `showSetlistPickerBottomSheet` does not pass `mainAxisMaxRatio`, so the outer Forui envelope uses the shared default. The observed ~70% ceiling reported in the Feature Input matches the inner container constraint, confirming the inner `maxHeight` is the operative cap in this widget.

- The two invocation sites — [setlist_detail_screen.dart:377](lib/features/setlists/setlist_detail_screen.dart#L377) (`_handleMoveOrCopySong`) and [setlist_detail_screen.dart:1400](lib/features/setlists/setlist_detail_screen.dart#L1400) (`_handleAddToSetlist`) — only await the returned `SetlistPickerResult`. Neither reasons about sheet height or depends on the `0.7` factor in any way.

This is not a data issue, not a permissions issue, and not a state-management issue. It is a single hardcoded UI constant.

# Reference Docs Consulted

The `docs/reference/` tree does not contain a dedicated bottom-sheet or drawer-sizing domain reference. Files reviewed to confirm this and to check for any policy that would forbid raising the ceiling:

- `docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md` — landing page marketing guidance; not relevant.
- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` — mentions this exact sheet in the context of a prior keyboard-inset fix (`AnimatedPadding` with `viewInsets.bottom`) but prescribes no height policy.
- `docs/reference/audits/ICON_AUDIT_AND_LUCIDE_MIGRATION.md` — icon-only inventory; not relevant.
- `docs/reference/general/AI_DECISIONS.md` and `docs/reference/general/RUNTIME_CONFIG.md` — no decisions covering bottom-sheet height ratios.

Adjacent design precedent (reviewed to confirm a taller ceiling is consistent with existing patterns):

- [docs/features/bug-edit-drawer-bottom-sheet-height/ARCHITECT_PLAN.md](docs/features/bug-edit-drawer-bottom-sheet-height/ARCHITECT_PLAN.md) established that edit-mode drawers with dense content should extend to a near-full-height envelope (`mainAxisMaxRatio: 0.95` via the shared wrapper for `showAppBottomSheet` sheets, or an explicit `screenHeight * 0.95` cap for sheets that manage their own constraints). The setlist picker manages its own `BoxConstraints.maxHeight` directly, so the analogous fix is to raise the direct constant. The Feature Input specifies `0.85` as the target, which is more conservative than that precedent and is retained.

Conclusion: no reference doc mandates a specific height policy that would block the change. No AI decision needs to be recorded for this fix.

# Existing System Analysis

Current data flow, event creation → sheet display → user selection:

1. User multi-selects songs in the Catalog or a setlist and taps "Add To Setlist".
2. `_handleAddToSetlist` ([setlist_detail_screen.dart:1400](lib/features/setlists/setlist_detail_screen.dart#L1400)) or `_handleMoveOrCopySong` ([setlist_detail_screen.dart:377](lib/features/setlists/setlist_detail_screen.dart#L377)) calls `showSetlistPickerBottomSheet(context, selectedSongCount: …, sourceSetlistId: …, sourceSetlistName: …)`.
3. `showSetlistPickerBottomSheet` ([setlist_picker_bottom_sheet.dart:83](lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart#L83)) delegates to `showAppBottomSheet` with `isScrollControlled: true`, `useSafeArea: true`, a transparent background, and a black54 barrier. It does not pass `mainAxisMaxRatio`.
4. The sheet's `build()` method wraps the body in:
   - `AnimatedBuilder` for entrance animation (`Transform.translate` + `Opacity`).
   - `AnimatedPadding` with `padding: EdgeInsets.only(bottom: keyboardHeight)` where `keyboardHeight = MediaQuery.of(context).viewInsets.bottom` — this is the keyboard-inset handler and is unaffected by the max-height cap.
   - A `Container` with `margin: const EdgeInsets.all(16)`, `constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7)`, and rounded surface decoration.
   - Inside the Container: `Column(mainAxisSize: MainAxisSize.min)` with a header and a `Flexible` that hosts either `_buildCreateNewForm()` or `_buildSetlistList(...)`.
5. `_buildSetlistList` renders a "Create New Setlist" tile, a divider, and then either an empty-state block or a `Flexible → ListView.builder(shrinkWrap: true)` of setlist tiles. Bottom padding is `MediaQuery.of(context).padding.bottom + 8` — safe-area based, independent of the max-height factor.
6. `_buildCreateNewForm` renders a text field, Cancel/Create buttons, and the same `MediaQuery.of(context).padding.bottom + 8` bottom padding.

Layout invariants that must survive the fix:

- `useSafeArea: true` on `showAppBottomSheet` reserves top and bottom system insets outside the sheet body, so raising the internal `maxHeight` to 0.85 does not push the sheet into the status bar or home indicator.
- The `Container` has a hardcoded `margin: EdgeInsets.all(16)` giving an additional 16px inset on all sides of the sheet body. This means a 0.85 factor yields a visible body that still clears the status bar area with margin plus safe-area headroom.
- The `AnimatedPadding` sits _outside_ the constrained `Container`, so the keyboard inset continues to slide the entire sheet upward independently of the max-height constant.
- `MainAxisSize.min` on the Column means the sheet only reaches the `maxHeight` cap when content actually needs it (many setlists). With few setlists, sheet height is unchanged.

None of the surrounding logic (state, animation, callbacks, close button, Move/Copy toggle, create form, empty state, list virtualization) is a function of the `0.7` factor.

# Proposed Solution

Change the single hardcoded factor `0.7` to `0.85` on the one line where the sheet's outer `Container` sets its `BoxConstraints.maxHeight`. No other lines in any file change.

Exact before/after:

```dart
// Before
constraints: BoxConstraints(
  maxHeight: MediaQuery.of(context).size.height * 0.7,
),
```

```dart
// After
constraints: BoxConstraints(
  maxHeight: MediaQuery.of(context).size.height * 0.85,
),
```

Why this is the correct fix:

- It targets the exact operative constraint identified in Phase 6 with HIGH confidence.
- It respects the guardrail "prefer the smallest change that fully solves the problem" — one file, one number.
- Safe-area handling (`useSafeArea: true`) is unchanged and continues to reserve top/bottom system insets outside the sheet.
- Keyboard handling (`AnimatedPadding` with `viewInsets.bottom`) is unchanged; the padding sits outside the constrained container.
- The `EdgeInsets.all(16)` outer margin on the Container provides an additional 16px inset from the safe-area boundary. At 85% of screen height, the sheet body still clears the header/status-bar region on every supported platform (iOS notch/dynamic island, Android status bar, macOS/web title areas).
- No dependent layout math elsewhere assumes 0.7. The `Flexible → ListView.builder(shrinkWrap: true)` sizes to the available parent constraint. Bottom padding uses `MediaQuery.of(context).padding.bottom + 8`, which is independent of the maxHeight factor.
- Both call sites (`_handleAddToSetlist`, `_handleMoveOrCopySong`) only await the sheet's return value; they do not depend on its height.

What must not change:

- No changes to `showSetlistPickerBottomSheet` signature, its `showAppBottomSheet` call, or the `useSafeArea`/`isScrollControlled`/`barrierColor` arguments.
- No changes to `showAppBottomSheet` or its Forui `mainAxisMaxRatio` default. Do not add or change `mainAxisMaxRatio` for this sheet.
- No changes to the `AnimatedPadding`, `AnimatedBuilder`, `Container.margin`, `Container.decoration`, or the `Column` structure inside the sheet.
- No changes to `_buildSetlistList`, `_buildCreateNewForm`, `_buildHeader`, `_buildMoveCopyToggle`, `_buildToggleOption`, or `_SetlistOptionTile`.
- No changes to the two call sites in `setlist_detail_screen.dart`.
- No changes to any sibling bottom sheet — including [add_to_setlist_overlay.dart](lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart), which is a separate full-screen overlay explicitly out of scope per the Feature Input.

# Database Impact

Database: not applicable.

No schema, migration, RLS policy, RPC, trigger, or edge function is involved. This is a client-only UI constant change.

- Migrations: not required.
- Edge function deploy: not required.
- RLS policies: unaffected.
- RPC signatures: unaffected.
- Triggers: unaffected.

# Flutter Architecture Changes

None.

- State management: no provider, notifier, or controller change.
- Repositories: unchanged.
- Widgets: a single numeric literal changes inside one existing widget (`_SetlistPickerSheetState.build()`); the widget tree structure is identical.
- Routing: unaffected.
- Init order: unaffected.

# Files to Create

none.

# Files to Modify

| File                                                                                                                             | What changes                                                                                                                                                                                                                                                                |
| -------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart](lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart) | In `showSetlistPickerBottomSheet()`, add `mainAxisMaxRatio: 0.85` to the existing `showAppBottomSheet<SetlistPickerResult>(...)` call so the Forui outer envelope uses the intended cap.                                                                                    |
| [lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart](lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart) | Reconcile the inner `Container.constraints.maxHeight` per the revised diagnosis decision: remove the hardcoded local height ratio constraint (or otherwise ensure there is not a second independent height ratio knob in this widget). Keep styling/layout behavior intact. |

# Files Off-Limits

| File                                                                                                                                                 | Reason                                                                                                                  |
| ---------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| [lib/main.dart](lib/main.dart)                                                                                                                       | Initialization order must not change.                                                                                   |
| [lib/components/ui/app_bottom_sheet.dart](lib/components/ui/app_bottom_sheet.dart)                                                                   | Shared wrapper — changing its default `mainAxisMaxRatio` would impact every other sheet in the app and is out of scope. |
| [lib/features/setlists/setlist_detail_screen.dart](lib/features/setlists/setlist_detail_screen.dart)                                                 | Caller only; the two `showSetlistPickerBottomSheet` invocations must not be altered.                                    |
| [lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart](lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart) | Separate full-screen category-selection overlay; explicitly out of scope per the Feature Input.                         |
| [lib/features/setlists/widgets/song_details_bottom_sheet.dart](lib/features/setlists/widgets/song_details_bottom_sheet.dart)                         | Different sheet; its height was addressed in a separate bug and must not be touched here.                               |
| [lib/features/contacts/widgets/band_member_edit_drawer.dart](lib/features/contacts/widgets/band_member_edit_drawer.dart)                             | Different drawer; its height was addressed in a separate bug and must not be touched here.                              |
| `pubspec.yaml`, `pubspec.lock`                                                                                                                       | No dependency changes required.                                                                                         |
| Any file under `supabase/`, `sql/`, or `database/`                                                                                                   | No backend change is involved.                                                                                          |

Migration policy: not required.
Edge function deploy: not required.
New dependencies: not allowed.
New files: none.

# System Impact Map

| System                                 | Impact                                                                                                                         |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Gigs                                   | unaffected                                                                                                                     |
| Rehearsals                             | unaffected                                                                                                                     |
| Setlists / Catalog                     | affected (only the "Add To Setlist" picker sheet's max visible height)                                                         |
| Members / RBAC                         | unaffected                                                                                                                     |
| Auth / Session                         | unaffected                                                                                                                     |
| Routing                                | unaffected                                                                                                                     |
| Notifications                          | unaffected                                                                                                                     |
| Platform (iOS / Android / Web / macOS) | affected only in that the sheet renders taller on all four platforms; no platform branching or platform-specific logic changes |

# Regression Risk

Regression risk: LOW

Rationale:

- Exactly one file is modified.
- Exactly one numeric literal is changed on one line.
- No auth, session, routing, init order, or database mutation is touched.
- Notifications are unaffected.
- No other notification/UI code path shares this constant.
- Safe-area and keyboard-inset handling remain in place with no code change.
- Both call sites are pure `await` consumers that do not depend on the sheet's height.
- The `Container` retains its `margin: EdgeInsets.all(16)` and `useSafeArea: true`, providing headroom against the top system inset at 0.85.

# Engineer Task Breakdown

1. Open [lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart](lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart).
2. Locate the `showAppBottomSheet<SetlistPickerResult>(...)` call inside `showSetlistPickerBottomSheet()`.
3. Add `mainAxisMaxRatio: 0.85` to that call so the outer Forui sheet envelope is explicitly capped at 85%.
4. In `_SetlistPickerSheetState.build()`, remove or otherwise reconcile the inner `Container.constraints.maxHeight` hardcoded ratio per the revised diagnosis decision so there is a single authoritative height ratio in this widget.
5. Do not add, remove, or reorder imports.
6. Do not modify any other file.
7. Run `flutter analyze` and confirm zero new errors, warnings, or infos attributable to this change.
8. Run `flutter test` and confirm the full suite passes.
9. Produce `git diff` and confirm the file-level edits match this mechanism: `mainAxisMaxRatio: 0.85` is present in the `showAppBottomSheet` call, and no second unexplained independent height ratio remains in the file.

# Verification Plan

## Tier 1 — Pre-deployment (must pass before any release)

Because this is a client-only Flutter UI constant change with no database mutation, the Tier 1 gates are code-level and layout-level. There are no SQL Tier 1 tests for this bug.

- `-- PRE-DEPLOY TEST 1:` `flutter analyze` from the repo root exits cleanly with no new analyzer diagnostics introduced by this change.
- `-- PRE-DEPLOY TEST 2:` `flutter test` runs the full existing test suite to completion with no new failures.
- `-- PRE-DEPLOY TEST 3:` Manual sheet layout check — Catalog with ≥10 setlists in the band:
  1. Open the Catalog.
  2. Select two or more songs.
  3. Tap "Add To Setlist".
  4. Confirm the "Add To Setlist" sheet's top edge sits at approximately 85% of screen height and is visibly taller than the prior Forui default envelope (~56.25%) while still clearing the status bar / notch area on the current platform.
  5. Confirm the setlist list scrolls only after content exceeds the new taller cap.
- `-- PRE-DEPLOY TEST 4:` Manual keyboard interaction check — Catalog:
  1. Open the Catalog, select songs, tap "Add To Setlist".
  2. Tap "Create New Setlist" and focus the text field.
  3. Confirm the sheet slides above the software keyboard via the existing `AnimatedPadding` (`viewInsets.bottom`) with no visual jump and no keyboard overlap of the input field or action buttons.
- `-- PRE-DEPLOY TEST 5:` Manual sheet layout check from within a non-Catalog setlist (Move/Copy path):
  1. Open a setlist that is not the Catalog.
  2. Select one or more songs.
  3. Tap the action that triggers `_handleMoveOrCopySong` (invokes `showSetlistPickerBottomSheet` with `sourceSetlistId` set).
  4. Confirm the Move/Copy toggle in the header is present, the sheet extends to the new taller cap, and content scrolls only after exceeding it.
- `-- PRE-DEPLOY TEST 6:` Static code check + `git diff` review:
  1. Confirm `showSetlistPickerBottomSheet()` passes `mainAxisMaxRatio: 0.85` to `showAppBottomSheet`.
  2. Confirm no second unexplained independent height ratio remains in `setlist_picker_bottom_sheet.dart`.
  3. Confirm no unrelated formatting, import, or whitespace-only churn is present.

## Tier 2 — Post-deployment (run after release / deployment passes)

- `-- POST-DEPLOY TEST 1:` Re-open the "Add To Setlist" sheet from the Catalog and confirm the taller max height is present in the shipped build across web, iOS, Android, and macOS.
- `-- POST-DEPLOY TEST 2:` Re-open the "Add To Setlist" sheet from within a non-Catalog setlist (Move/Copy path) and confirm parity with Test 1.
- `-- POST-DEPLOY TEST 3:` Verify the sheet body still clears the top system inset on each platform: iOS notch/dynamic island, Android status bar, macOS/web title area. No overlap with the status bar, notch, or navigation bar.
- `-- POST-DEPLOY TEST 4:` Verify sibling sheets that were not intended to change are unaffected in the shipped build:
  - Song details bottom sheet (view and edit modes) — height unchanged from prior release.
  - Band member edit drawer — height unchanged from prior release.
  - Tuning picker bottom sheet — height unchanged from prior release.
  - `add_to_setlist_overlay` full-screen overlay — unchanged.

# QA Regression Areas

QA must specifically validate:

- Primary: "Add To Setlist" sheet reaches ~85% of screen height when invoked from the Catalog with enough setlists to fill it, and scrolls only after that cap is reached.
- Primary: "Add To Setlist" sheet reaches ~85% of screen height when invoked from a non-Catalog setlist (Move/Copy path) with the Move/Copy toggle visible.
- Safe-area: sheet body clears the top status bar / notch / dynamic island on iOS, the status bar on Android, and the title area on macOS/web. Bottom safe-area padding (`MediaQuery.of(context).padding.bottom + 8`) still renders correctly.
- Keyboard: opening "Create New Setlist" and focusing the input still slides the sheet above the software keyboard via `AnimatedPadding` with no overlap.
- Small-content behavior: opening the sheet with zero or few setlists renders as before (sheet is shorter than the cap because `MainAxisSize.min` still applies) — the fix must not force the sheet to be tall when content is small.
- Empty state: with zero non-Catalog setlists, the empty-state block ("No setlists yet") renders correctly under the new cap.
- Adjacent, out-of-scope sheets remain unchanged:
  - `song_details_bottom_sheet.dart` view/edit heights unchanged.
  - `band_member_edit_drawer.dart` height unchanged.
  - `tuning_picker_bottom_sheet.dart` height unchanged.
  - `add_to_setlist/add_to_setlist_overlay.dart` unchanged.
- Both call sites in `setlist_detail_screen.dart` still receive `SetlistPickerResult` correctly for existing-setlist selection, create-new, and cancel paths.
- Cross-platform smoke: verify on web, iOS, Android, and macOS since the widget is shared with no platform branching.

# Rollout / Migration Strategy

Not applicable. This is a client-only Flutter constant change. It ships with the next standard app release. No database migration, no edge function deploy, no phased rollout, and no feature flag are required. Rollback, if ever required, is the inverse one-character revert (`0.85` → `0.7`) on the same line.

# Out of Scope

- Any change to `showAppBottomSheet`, Forui's `showFSheet`, or the shared `mainAxisMaxRatio` default.
- Any change to [add_to_setlist_overlay.dart](lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart) (the category-selection full-screen overlay), which the Feature Input explicitly excludes.
- Any change to other bottom sheets or drawers — including `song_details_bottom_sheet.dart`, `band_member_edit_drawer.dart`, `band_member_detail_drawer.dart`, and `tuning_picker_bottom_sheet.dart`.
- Any change to the sheet's animation curves, durations, colors, header layout, Move/Copy toggle, empty state, or list virtualization.
- Any refactor to migrate this sheet to a different sizing model (e.g., `mainAxisMaxRatio` on the wrapper instead of an inner `BoxConstraints`). This can be considered in a separate feature if desired but is not part of this fix.
- Adding tests for this widget. Existing tests must continue to pass; adding new widget tests is out of scope for a single-constant fix.
- Any formatting, import cleanup, comment edits, or unrelated refactoring in the modified file.

---

## Revised Diagnosis (2026-08-31)

This section is appended to preserve the original record and supersedes the earlier Root Cause and Proposed Solution sections above.

### What Was Retested

- Re-read `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` in full.
- Re-read `lib/components/ui/app_bottom_sheet.dart` in full.
- Verified Forui `showFSheet` behavior from installed package source:
  - `/Users/tonyholmes/.pub-cache/hosted/pub.dev/forui-0.26.0/lib/src/widgets/sheet/modal_sheet.dart`
  - `/Users/tonyholmes/.pub-cache/hosted/pub.dev/forui-0.26.0/lib/src/widgets/sheet/shifted_sheet.dart`
- Reviewed prior same-class precedent:
  - `docs/features/bug-edit-drawer-bottom-sheet-height/ARCHITECT_PLAN.md`
- Re-checked sibling usage precedent:
  - `lib/features/calendar/widgets/add_block_out_drawer.dart`
  - `lib/features/events/widgets/add_edit_event_bottom_sheet.dart`

### Confirmed Correct Root Cause

The previously implemented change (`Container` `maxHeight` `0.7` -> `0.85`) was applied to a nested inner constraint that was not the effective limiter at runtime.

`showSetlistPickerBottomSheet()` calls `showAppBottomSheet(...)` without `mainAxisMaxRatio`.
`showAppBottomSheet` forwards `mainAxisMaxRatio: mainAxisMaxRatio ?? (9 / 16)` to Forui `showFSheet`.
Forui then enforces the sheet's outer envelope in `ShiftedSheet.constrainChild(...)` with:

- vertical sheets (`FLayout.btt`): `maxHeight = constraints.maxHeight * mainAxisMaxRatio`

So the active outer cap was `9/16` (~56.25%), which is tighter than both `0.7` and `0.85`. That means the inner `Container.constraints.maxHeight` could not increase visible sheet height, so the first fix attempt had no visual effect.

Confidence: HIGH (direct source verification in local code + Forui package source).

### Constraint Chain Verification (No Hidden Override)

- In `setlist_picker_bottom_sheet.dart`, the only explicit local height cap is the single `Container.constraints.maxHeight` line.
- No other local `maxHeight`/`FractionallySizedBox`/`DraggableScrollableSheet` cap exists in this widget.
- Therefore, the governing cap for visible sheet height is the outer Forui route envelope unless explicitly overridden with `mainAxisMaxRatio` in the `showAppBottomSheet(...)` call.

### Revised Fix (Authoritative)

Update `showSetlistPickerBottomSheet()` to pass:

- `mainAxisMaxRatio: 0.85`

inside the existing `showAppBottomSheet<SetlistPickerResult>(...)` call.

### Decision On Inner `Container.constraints.maxHeight`

Decision: reconcile to a single source of truth by removing the hardcoded inner `maxHeight` ratio constraint from this sheet.

Rationale:

- After adding `mainAxisMaxRatio: 0.85`, keeping a second hardcoded `0.85` locally is redundant and creates dual knobs for the same behavior.
- A single authoritative ratio at the sheet wrapper call site is clearer, matches established project precedent for `showAppBottomSheet`-based drawers, and avoids future drift.
- The inner container can still keep styling (`margin`, `decoration`) without owning global height policy.

Implementation note: keep the `constraints:` block only if needed for non-height constraints; otherwise remove it entirely to avoid two competing magic numbers.

### Revised Implementation Boundaries

Files to modify (revised):

- `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`
  - Add `mainAxisMaxRatio: 0.85` to the `showAppBottomSheet` invocation.
  - Remove/reconcile inner hardcoded `maxHeight` ratio so only one height constant governs the sheet.

Files explicitly off-limits (unchanged):

- `lib/components/ui/app_bottom_sheet.dart` (do not change global default)
- `lib/features/setlists/setlist_detail_screen.dart`
- `lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart`
- all backend/database files

### Revised Verification Focus

1. Confirm from code diff that `showSetlistPickerBottomSheet()` now passes `mainAxisMaxRatio: 0.85`.
2. Confirm no second independent height ratio remains in this widget without explicit justification.
3. Manual runtime check: sheet visibly taller than prior 56.25% cap in both call paths (Catalog add, non-Catalog move/copy), while safe-area and keyboard behavior remain intact.
