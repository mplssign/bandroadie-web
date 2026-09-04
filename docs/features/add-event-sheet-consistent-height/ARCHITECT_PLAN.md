# ARCHITECT_PLAN — bug/add-event-sheet-consistent-height

## Feature Slug
`add-event-sheet-consistent-height`

## Feature Title
Add Event sheet height should stay constant across Rehearsal/Gig/Block out tabs

## Problem Summary
In the Add Event bottom sheet, switching the event type between Rehearsal, Gig, and Block out visibly changes the sheet's overall height. Block out (3 fields) renders as a short sheet, Rehearsal (3 section cards) as a medium sheet, and Gig (6 section cards) as a near-full-screen sheet. The user expects the sheet's outer height to remain identical across all three views — the body content should scroll internally, not resize the sheet chrome.

## Root Cause — HIGH confidence (confirmed in code)

`EventEditorDrawer.build()` at [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L2704-L2735) wraps the sheet body in a shrink-wrapping layout:

```dart
Container(
  constraints: BoxConstraints(
    maxHeight: MediaQuery.of(context).size.height,   // only a cap, no floor
  ),
  decoration: ...,
  child: Column(
    mainAxisSize: MainAxisSize.min,                  // hug children
    children: [
      Flexible(                                       // FlexFit.loose — child can be smaller than allocated
        child: SingleChildScrollView(                // shrink-wraps to child intrinsic when constraints are loose
          padding: const EdgeInsets.all(16),
          child: _buildScrollableBody(context),
        ),
      ),
      _buildStickyFooter(context),
    ],
  ),
),
```

Three properties combine to make the sheet resize with content:

1. The outer `Container` sets only `maxHeight` (a ceiling), never a floor or fixed height.
2. `Column(mainAxisSize: MainAxisSize.min)` tells the column to sum its children's chosen sizes rather than fill the parent.
3. `Flexible` (default `FlexFit.loose`) gives its child `[0, allocatedSpace]` — the child picks its own size. `SingleChildScrollView` along its scroll axis, when given loose constraints, shrink-wraps to its child's intrinsic height (up to the allocated maximum).

Result: the column's height = footer height + body's intrinsic height (up to screen height). `_buildScrollableBody` at [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L2878-L2985) returns a `Column` with a very different number of `_SectionCard` children per event type:

- `EventType.blockOut` — one `_buildBlockOutForm()` (start date, end date, reason) — small intrinsic height.
- `EventType.rehearsal` — three `_SectionCard`s (Schedule, Location, Notes) — medium intrinsic height.
- `EventType.gig` — six `_SectionCard`s (The Gig, Schedule, Location, Show Details, Money, Notes) — tall intrinsic height, clamps to `screenHeight - footer`.

`_handleTypeChanged` calls `setState` and swaps the body sub-tree, so the intrinsic height changes on each tap of the `EventTypeSelector`, and the sheet chrome resizes with it.

`isScrollControlled: true` in `AddEditEventBottomSheet.show` at [lib/features/events/widgets/add_edit_event_bottom_sheet.dart](lib/features/events/widgets/add_edit_event_bottom_sheet.dart#L60-L74) gives the sheet loose vertical constraints from the modal, so nothing outside `EventEditorDrawer.build()` imposes a fixed sheet height either. The fix must be inside `EventEditorDrawer.build()`.

## Existing System Analysis

- `EventEditorDrawer` is the single source of truth for the Add/Edit Event UI. It is instantiated only from `AddEditEventBottomSheet.show` ([add_edit_event_bottom_sheet.dart:67](lib/features/events/widgets/add_edit_event_bottom_sheet.dart#L67)), which is called from 16 sites across `calendar_screen.dart`, `calendar_tab_content.dart`, `home_screen.dart`, and `home_tab_content.dart`. All 16 callers use the same wrapper; none re-implement the sheet chrome.
- The wrapper already sets `isScrollControlled: true`, `useSafeArea: true`, and `backgroundColor: Colors.transparent` on `showModalBottomSheet` — those are the correct params for a full-height custom-chrome sheet. No change is needed there.
- `EventTypeSelector` ([event_type_selector.dart](lib/features/events/widgets/event_type_selector.dart)) is the segmented control. Its own layout is stable (44px tall row) — it is not the cause. It is hidden in edit mode (`if (!_isEditMode && !_isEditingExpense)` at [event_editor_drawer.dart:2846](lib/features/events/widgets/event_editor_drawer.dart#L2846)); this bug is user-visible only in create mode, but the fix applies uniformly and will produce a consistent-height edit sheet too — a benign, desirable side effect.
- Existing widget test at [test/features/events/widgets/event_dropdown_test.dart:197-278](test/features/events/widgets/event_dropdown_test.dart#L197-L278) asserts `EventEditorDrawer` inside a `showModalBottomSheet` on rehearsal type produces no layout errors (`BoxConstraints forces an infinite width`, `RenderBox was not laid out`). The fix must continue to pass this test.
- Prior PR #245 (`feat(ui): scrollable sheet headers and required-field gate on Add Event`, current `main` HEAD `1da31c2`) introduced the scrollable-body pattern with the sticky header inside the scroll view. That refactor is not being reversed — this fix only stabilizes the outer container height around it.

## Proposed Solution

Lock the outer container to a stable height equal to the available modal height, and force the scroll view to fill that height regardless of body intrinsic size.

Three coordinated changes inside a single `build()` method:

1. Replace `constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height)` with `height: MediaQuery.of(context).size.height` on the outer `Container`.
   - Rationale: gives the Container a definite preferred height. When `useSafeArea: true` on the modal wraps our subtree in `SafeArea(bottom: false)`, the parent will clamp our container to the actual safe-area height; when the test harness omits `useSafeArea`, the container fills the test viewport. Either way, the sheet's outer size is defined by the viewport, not by the body content.

2. Replace `Flexible` with `Expanded` around the `SingleChildScrollView`.
   - Rationale: `Expanded` gives `FlexFit.tight`, forcing the scroll view to take exactly its allocated space instead of shrink-wrapping its child's intrinsic height.

3. Remove `mainAxisSize: MainAxisSize.min` from the `Column` (fall back to the `MainAxisSize.max` default).
   - Rationale: with a fixed-height parent and an `Expanded` child, `MainAxisSize.min` is inconsistent with the intent; `MainAxisSize.max` makes the layout intent explicit and matches how `Expanded` behaves.

That is the entire fix. Body content that exceeds available height scrolls internally (unchanged for Gig). Body content that is shorter than available height leaves stable empty space below the last field (visible only for Block out and, to a lesser degree, Rehearsal) — this is the exact "identical sheet height" behavior the bug report requests.

Rejected alternatives:

- **Fixed percentage (e.g. `size.height * 0.9`).** Arbitrary, doesn't compose well with `useSafeArea: true` (would compound insets), and still requires the same three-line layout swap.
- **`AnimatedSize` wrapping the body.** Animates between three different heights but does not deliver "identical height across all three views" — it just softens the resize. Explicitly not what the bug asks for.
- **`DraggableScrollableSheet`.** Larger refactor. The sheet already opts out of the default draggable behavior with a custom chrome; introducing a draggable sheet would change UX beyond scope.
- **Duplicating the outer chrome per event type.** Introduces per-type sizing logic and drifts from the "single source of truth" pattern documented at [event_editor_drawer.dart:52-66](lib/features/events/widgets/event_editor_drawer.dart#L52-L66).

## Database Impact
n/a

## Flutter Architecture Changes
None. No new providers, controllers, repositories, models, routes, or dependencies. Riverpod graph unchanged. Init order unchanged. Platform-conditional code unchanged (this widget renders identically on iOS, Android, macOS, and web).

## Files to Create
None.

## Files to Modify

| File | Change |
| --- | --- |
| [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) | In `_EventEditorDrawerState.build()` (currently lines 2703-2735): (1) swap the outer `Container.constraints: BoxConstraints(maxHeight: …)` for `Container.height: …` using the same `MediaQuery.of(context).size.height` value; (2) change `Flexible` around `SingleChildScrollView` to `Expanded`; (3) remove `mainAxisSize: MainAxisSize.min` from the `Column`. Nothing else in this file changes. |

## Files Off-Limits

| File | Why off-limits |
| --- | --- |
| [lib/features/events/widgets/add_edit_event_bottom_sheet.dart](lib/features/events/widgets/add_edit_event_bottom_sheet.dart) | `showModalBottomSheet` params (`isScrollControlled: true`, `useSafeArea: true`, `backgroundColor: Colors.transparent`) are already correct for a full-height custom-chrome sheet. Changing them would alter behavior for all 16 call sites unnecessarily. |
| [lib/features/events/widgets/event_type_selector.dart](lib/features/events/widgets/event_type_selector.dart) | The segmented control's own layout is stable (fixed 44px). It is not the cause of the resize; touching it invites regressions to the selector's animation and layout. |
| [lib/features/events/widgets/event_form_fields.dart](lib/features/events/widgets/event_form_fields.dart), [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart), [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart), [lib/features/events/widgets/gig_expense_subview.dart](lib/features/events/widgets/gig_expense_subview.dart), [lib/features/events/widgets/event_editor_helpers.dart](lib/features/events/widgets/event_editor_helpers.dart), [lib/features/events/widgets/event_editor_actions.dart](lib/features/events/widgets/event_editor_actions.dart), [lib/features/events/widgets/button_group_grid.dart](lib/features/events/widgets/button_group_grid.dart) | The form-body widgets are what legitimately have different intrinsic heights per event type. The fix is at the sheet-chrome level (outer container), not by trimming form content. |
| [lib/features/events/models/event_form_data.dart](lib/features/events/models/event_form_data.dart), [lib/features/events/events_repository.dart](lib/features/events/events_repository.dart), any repository/controller/model in `lib/features/events/`, `lib/features/rehearsals/`, `lib/features/gigs/`, `lib/features/calendar/` | Pure data/state layers. This bug is layout-only. |
| Any caller of `AddEditEventBottomSheet.show` ([calendar_screen.dart](lib/features/calendar/calendar_screen.dart), [calendar_tab_content.dart](lib/features/calendar/calendar_tab_content.dart), [home_screen.dart](lib/features/home/home_screen.dart), [home_tab_content.dart](lib/features/home/home_tab_content.dart)) | Callers pass `initialType` and other data; they don't own sheet chrome sizing. |
| `supabase/migrations/**`, `supabase/functions/**`, `lib/app/theme/design_tokens.dart`, `lib/app/theme/event_editor_theme.dart`, `pubspec.yaml`, `pubspec.lock` | No DB, RLS, RPC, edge-function, theme-token, or dependency change is required. |

## Change Budget

| Metric | Expected |
| --- | --- |
| Files created | 0 |
| Files modified | 1 |
| Net line delta in [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) | -1 (remove `mainAxisSize: MainAxisSize.min` and one line of `BoxConstraints(...)`; add one `height:` line; rename `Flexible` → `Expanded`) |
| New public classes / methods | 0 |
| New dependencies | 0 |
| New migrations / edge functions | 0 |

## System Impact Map

| System | Impact |
| --- | --- |
| Gigs | Unaffected — gig creation/edit flow (data, validation, save, delete) unchanged. Only the sheet's outer height changes. |
| Rehearsals | Unaffected — same as gigs. |
| Setlists | Unaffected. |
| Members | Unaffected. |
| Auth | Unaffected. |
| Routing | Unaffected — same `showModalBottomSheet` call sites, same widget instantiation. |
| Notifications | Unaffected. |
| Platforms (iOS / Android / macOS / Web) | Layout fix applies uniformly. No platform-conditional code changed. `useSafeArea: true` on the modal continues to handle notch/Dynamic Island top inset. |
| Init order | Unaffected — no changes to `main.dart` or startup sequence. |

## Regression Risk

**LOW.**

The change is scoped to one method (`_EventEditorDrawerState.build`) in one file. It does not touch:
- Auth, session, or PKCE flow.
- Supabase queries, RLS, or RPC.
- Riverpod providers, controllers, repositories, or models.
- Routing, deep links, or navigation.
- Init order or platform-conditional code.
- Any form field, validation, save, delete, or permission logic.

The only user-visible behavior change is the outer sheet height: it becomes constant instead of varying with event type. The scrollable body absorbs content-height differences internally, which is the pre-existing pattern for the Gig case and the intended behavior for all three cases.

Existing widget test at [test/features/events/widgets/event_dropdown_test.dart:197-278](test/features/events/widgets/event_dropdown_test.dart#L197-L278) exercises the drawer inside `showModalBottomSheet(isScrollControlled: true)` on rehearsal type and asserts zero layout errors — the fix must continue to pass this test unchanged.

## Engineer Task Breakdown

1. In [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) inside `_EventEditorDrawerState.build()` (lines 2703-2735 as of `main@1da31c2`), replace `constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height)` with `height: MediaQuery.of(context).size.height` on the outer `Container`, replace `Flexible` with `Expanded` around the `SingleChildScrollView`, and remove `mainAxisSize: MainAxisSize.min` from the `Column`. Make no other changes to this file.
2. Run `flutter analyze` and confirm zero new warnings or errors.
3. Run `flutter test test/features/events/widgets/event_dropdown_test.dart` and confirm all tests pass, including `EventEditorDrawer inside bottom sheet emits no layout errors on Android (rehearsal)`.

## Verification Plan

### Tier 1 — pre-deploy (automated + local)

1. **Static analysis.** `flutter analyze` reports zero new warnings or errors introduced by the change.
2. **Existing widget test.** `flutter test test/features/events/widgets/event_dropdown_test.dart` passes, including the `EventEditorDrawer inside bottom sheet emits no layout errors on Android (rehearsal)` test group. No new test file is needed — this test already exercises the exact code path being modified and would catch any `BoxConstraints forces an infinite width` or `RenderBox was not laid out` regression from the layout change.

### Tier 2 — manual visual (post-implement, pre-merge)

Run on at least one mobile target (iOS simulator or physical device) and one desktop target (macOS):

1. From the Calendar screen (or Home screen), tap **Add Event**. Note the sheet's overall visible height.
2. Tap the **Rehearsal** segment. Confirm the sheet's outer height does not change.
3. Tap the **Gig** segment. Confirm the sheet's outer height does not change; body scrolls internally when content exceeds the visible area.
4. Tap the **Block out** segment. Confirm the sheet's outer height does not change; empty space below the last field is acceptable.
5. Tap **Rehearsal** again to confirm the height is unchanged in reverse direction.
6. Repeat with the keyboard summoned (tap into Notes on Rehearsal, then switch types). Confirm the sheet still respects keyboard inset and does not visibly resize on type change.
7. Confirm the sticky header (title + `EventTypeSelector`) remains visible at the top and the sticky footer (Save/Cancel) remains visible at the bottom for all three event types.
8. Confirm the sheet still respects the top safe area on iOS notch / Dynamic Island (`useSafeArea: true` is preserved).
9. Open **Edit Event** from an existing gig or rehearsal (not create mode). Confirm the edit sheet also renders at the same stable height. This is a benign side effect; no visual regression should be observed.

## QA Regression Areas

- Add Event sheet on iOS, Android, macOS, and web — sheet opens, all three types render at identical outer height, body content is fully reachable (via scroll when needed).
- Edit Event sheet — opens for existing rehearsals and gigs; outer height is stable across sessions; edit-mode behavior (`EventTypeSelector` hidden, delete button visible, permission gating on save) is unchanged.
- View-only mode for contributors — sheet renders read-only overlay unchanged.
- Expense subview — tapping "Add Expense" from Gig's Money section swaps the body to the expense editor without resizing the sheet chrome; back button returns to the gig form.
- Keyboard behavior — tapping into a text field lifts the sheet position via modal viewInsets handling; sheet does not visibly resize.
- The 16 call sites listed under "Existing System Analysis" — all continue to open the sheet with the correct `initialType` and prefill.

## Rollout Strategy

Standard PR against `main` off `bug/add-event-sheet-consistent-height`. No feature flag, no migration, no data backfill, no API surface change. Rollback is a single-file revert.

## Out of Scope

- Redesigning the sheet's outer chrome (rounded corners, drop shadow, `kEdSurface` background, 14px radius) — preserved as-is.
- Changing the `showModalBottomSheet` params in `AddEditEventBottomSheet.show`.
- Changing the `EventTypeSelector` layout, animation, or available types.
- Changing what forms render for each event type, their field order, or their validation.
- Adding golden tests, screenshot tests, or new widget tests beyond the existing coverage.
- Any refactor of `_buildScrollableBody`, `_buildStickyHeader`, `_buildStickyFooter`, `_buildBlockOutForm`, `_buildScheduleSection`, `_buildLocationSection`, `_buildShowPrepSection`, `_buildMoneySection`, or `_buildNotesSection`.
- Any change to the sheet's edit-mode behavior beyond the incidental (and desirable) side effect of edit-mode height also becoming stable.
- Any change to keyboard handling, save/cancel wiring, permission gating, dirty-tracking, or the required-field gate introduced in PR #245.
