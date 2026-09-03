# ARCHITECT_PLAN.md

## Feature Slug

`bug/drawer-layout-recursion-constrainedbox`

## Feature Title

Add Event drawer crashes with `'!_debugDoingThisLayout'` layout recursion

## Problem Summary

Opening the Add Event drawer fires `'!_debugDoingThisLayout': is not true` followed by a chain of `RenderBox was not laid out` errors. The failing widget is inside `FAutocomplete` (used for gig name and city autocomplete in `GigFormFields`). The drawer is unusable.

## Root Cause

**Confidence: HIGH — confirmed by diffing PR #228 against commit 992a5ce.**

Two regressions introduced in the same PR:

### Regression 1 — `DecoratedBox` replaces `Container(constraints:…)` in `build()`

Current `build()` (line 2701) returns:
```dart
FTheme(
  data: buildEventEditorTheme(),
  child: DecoratedBox(
    decoration: BoxDecoration(...),
    child: Column(...),
  ),
)
```

`DecoratedBox` creates `RenderDecoratedBox`, which is a pure passthrough — it applies no constraints. Forui's `FAutocomplete` resolves its overlay anchor by measuring its host render object during layout. Without a settled `RenderConstrainedBox` ancestor, that measurement calls `markNeedsLayout()` on an object already in `layout()`, producing `'!_debugDoingThisLayout'`.

The original code (992a5ce line ~2713) used:
```dart
Container(
  constraints: BoxConstraints(
    maxHeight: MediaQuery.of(context).size.height,
  ),
  decoration: BoxDecoration(...),
  child: Column(...),
)
```
`Container(constraints:…)` inserts a `RenderConstrainedBox`, which provides the settled layout anchor. This is the direct cause of the crash.

### Regression 2 — `_createGigFormFields()` called five times per build

`_buildScrollableBody` dispatches to five section builders (`_buildGigSection`, `_buildScheduleSection`, `_buildLocationSection`, `_buildShowPrepSection`, `_buildMoneySection`), each of which calls `_createGigFormFields()` internally. Each call executes `ref.watch(currentUserPermissionsProvider)` once and `ref.watch(contactsProvider)` twice — 15 redundant provider subscriptions per build instead of 3. The original code created `gigFormFields` once in `build()`. This regression does not crash the app on its own but is a direct consequence of the same refactor and must be fixed here.

## Existing System Analysis

- `EventEditorDrawer` is a `ConsumerStatefulWidget` living in `lib/features/events/widgets/event_editor_drawer.dart` (3645 lines).
- `GigFormFields`, `RehearsalFormFields`, `EventFormFields` are plain Dart objects (data holders + builder methods). Only `_createGigFormFields()` calls `ref.watch()`.
- `_createRehearsalFormFields()` and `_createEventFormFields(context)` do not call `ref.watch()`.
- `_buildScrollableBody` branches on `_eventType`: block-out (no form fields), gig (needs `gigFormFields` + `eventFormFields`), rehearsal (needs `rehearsalFormFields` + `eventFormFields`).
- Section builders that serve both gig and rehearsal paths (`_buildScheduleSection`, `_buildLocationSection`) branch on `isGig` internally.
- `_buildNotesSection` uses `_createEventFormFields(context).buildNotesSection()` and is called from both gig and rehearsal paths.

## Proposed Solution

Two changes, both in `event_editor_drawer.dart`.

### Change 1 — Restore `Container(constraints:…)` in `build()`

In `build()` (line 2701), replace the `DecoratedBox` with a `Container` that carries `constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height)`. The `decoration:` argument moves from `DecoratedBox` to `Container`. The `Column` child is unchanged. This is a 2-line net addition.

### Change 2 — Create form fields once in `_buildScrollableBody`

At the top of `_buildScrollableBody` (after the `_isEditingExpense` guard), create the three form field objects once:

```dart
final gigFormFields = _eventType == EventType.gig ? _createGigFormFields() : null;
final rehearsalFormFields = _eventType == EventType.rehearsal ? _createRehearsalFormFields() : null;
final eventFormFields = _eventType != EventType.blockOut ? _createEventFormFields(context) : null;
```

Pass the pre-created objects into each section builder via parameters. Section builders remove their internal `_createGigFormFields()` / `_createRehearsalFormFields()` / `_createEventFormFields()` calls and use the passed-in objects directly. Signatures that serve both gig and rehearsal paths use nullable types (`GigFormFields?`).

No new public classes or methods are introduced.

## Database Impact

n/a

## Flutter Architecture Changes

No new providers, repositories, controllers, or widgets. The fix is entirely within a single `ConsumerStatefulWidget`.

## Files to Create

None.

## Files to Modify

| File | What changes |
|---|---|
| `lib/features/events/widgets/event_editor_drawer.dart` | Change 1: `build()` — replace `DecoratedBox` with `Container(constraints:…)`. Change 2: `_buildScrollableBody` + five section builder method signatures. |

## Files Off-Limits

All files except `event_editor_drawer.dart`. `GigFormFields`, `RehearsalFormFields`, `EventFormFields`, `GigFormFields`-related widgets, Forui widgets, `app_bottom_sheet.dart`, and all other features are off-limits — the fix does not require touching any of them.

## Change Budget

- Expected net line delta: +2 lines (Change 1) + ~0 net (Change 2 adds 3 lines, removes ~5 inline calls, adjusts ~5 signatures — roughly neutral). Total: **+2 to +5 net lines**.
- Expected new files: 0
- Expected new public classes/methods: 0
- Expected new dependencies: 0

## System Impact Map

| System | Status |
|---|---|
| Gigs | affected — crash fixed |
| Rehearsals | unaffected |
| Setlists | unaffected |
| Members | unaffected |
| Auth | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platforms (iOS/Android/macOS/Web) | all affected equally — pure Flutter layout fix |

## Regression Risk

**LOW.** The change restores a previously working layout pattern (`Container(constraints:…)`). No auth, session, routing, DB, or init-order code is touched.

## Engineer Task Breakdown

**Task 1 — Replace `DecoratedBox` with `Container(constraints:…)` in `build()`**

In `build()`, change the immediate child of `FTheme` from:
```dart
DecoratedBox(
  decoration: BoxDecoration(
    color: kEdSurface,
    border: Border.all(color: kEdCardBorder),
    borderRadius: BorderRadius.circular(14),
    boxShadow: const [...],
  ),
  child: Column(children: [...]),
)
```
to:
```dart
Container(
  constraints: BoxConstraints(
    maxHeight: MediaQuery.of(context).size.height,
  ),
  decoration: BoxDecoration(
    color: kEdSurface,
    border: Border.all(color: kEdCardBorder),
    borderRadius: BorderRadius.circular(14),
    boxShadow: const [...],
  ),
  child: Column(children: [...]),
)
```
No other change in this task.

**Task 2 — Create form fields once in `_buildScrollableBody`**

At the top of `_buildScrollableBody` (immediately after the `if (_isEditingExpense)` guard), add:
```dart
final gigFormFields = _eventType == EventType.gig ? _createGigFormFields() : null;
final rehearsalFormFields = _eventType == EventType.rehearsal ? _createRehearsalFormFields() : null;
final eventFormFields = _eventType != EventType.blockOut ? _createEventFormFields(context) : null;
```

Update the five gig-path `_SectionCard(child: _buildXxxSection(context))` call sites to pass the pre-created objects.

Update the five section builder method signatures to accept the pre-created form fields as parameters. Inside each builder, replace every `_createGigFormFields()` call with the passed-in `gigFormFields` (assert non-null within gig-only paths), and similarly for `rehearsalFormFields` and `eventFormFields`.

`_buildScheduleSection` and `_buildLocationSection` — called from both gig and rehearsal paths — use `GigFormFields?` / `RehearsalFormFields?` and branch on `isGig` as they already do.

The rehearsal-path call sites in `_buildScrollableBody` pass `rehearsalFormFields!` and `eventFormFields!`.

## Verification Plan

### Tier 1 — Pre-deploy (no running app required)

1. `flutter analyze lib/features/events/widgets/event_editor_drawer.dart` — zero issues.
2. Code review: confirm `build()` contains `Container(constraints: BoxConstraints(maxHeight: ...))` and no `DecoratedBox` remains as the `FTheme` child.
3. Code review: confirm `_createGigFormFields()` appears exactly once in `_buildScrollableBody` and zero times in the five section builder methods.
4. Code review: confirm `_createRehearsalFormFields()` and `_createEventFormFields(context)` each appear at most once in `_buildScrollableBody` and zero times in the section builders.

### Tier 2 — Post-deploy (device/simulator)

1. Open the Add Event drawer on any platform → confirm no `'!_debugDoingThisLayout'` or `RenderBox was not laid out` exceptions in debug console.
2. Gig autocomplete (name and city) — type into both fields, verify suggestions appear and selection works.
3. Set all gig sections (schedule, location, contacts, money) — verify each section renders and is interactive.
4. Rehearsal event type — open Add Rehearsal drawer, verify schedule/location sections render without errors.
5. Block-out event type — open Add Block Out drawer, verify it renders without errors.
6. Edit an existing gig — verify all sections load with correct pre-populated data.

## QA Regression Areas

- `EventEditorDrawer` gig event type: all sections, autocomplete fields (name, city, contacts)
- `EventEditorDrawer` rehearsal event type: schedule, location sections
- `EventEditorDrawer` block-out event type: full render
- View-only mode for all three event types

## Rollout Strategy

Standard: merge PR → verify on staging device → ship in next release. No feature flag, no migration, no server-side change.

## Out of Scope

- Any other `EventEditorDrawer` refactor or feature work
- Changes to `GigFormFields`, `RehearsalFormFields`, `EventFormFields`
- Changes to `app_bottom_sheet.dart` or Forui sheet sizing
- Any other file in the codebase
