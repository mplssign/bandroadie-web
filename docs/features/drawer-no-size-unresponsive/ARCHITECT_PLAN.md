# ARCHITECT PLAN

**Feature Slug:** `bug/drawer-no-size-unresponsive`
**Feature Title:** Add Event drawer unresponsive — "Cannot hit test a render box with no size"

---

## Problem Summary

After PR #228 (event-drawer redesign), tapping "+ Add Event" from the dashboard or calendar renders the drawer unresponsive. Flutter logs: `Cannot hit test a render box with no size`. Affects all platforms.

---

## Root Cause

**Confidence: HIGH — confirmed in code at line 2721.**

`lib/features/events/widgets/event_editor_drawer.dart` — the `build()` method of the drawer widget wraps its content in:

```dart
Column(
  mainAxisSize: MainAxisSize.min,   // ← bug
  children: [
    _buildStickyHeader(context),
    Container(height: 1, color: kEdCardBorder),
    Flexible(                        // ← gets 0 height under min column
      child: SingleChildScrollView(...),
    ),
    _buildStickyFooter(context),
  ],
),
```

`MainAxisSize.min` tells the `Column` to shrink-wrap its children. `Flexible` inside a `min` column receives zero "remaining space" — its height collapses to 0. A render box with size 0 cannot be hit-tested, making the entire sheet unresponsive.

The fix: `mainAxisSize: MainAxisSize.max` (the default). With `max`, the column expands to fill the finite height provided by the bottom sheet, and `Flexible` correctly claims the remaining height between the sticky header and footer.

---

## Existing System Analysis

- The drawer is rendered in a `DraggableScrollableSheet` (or equivalent modal bottom sheet) that already provides a finite vertical constraint — so `MainAxisSize.max` is safe and correct.
- A second `mainAxisSize: MainAxisSize.min` exists at ~line 3272, inside an AM/PM `Row` (not a `Column`) with no `Flexible` children. It is unrelated and must not be touched.
- No other `Flexible` children appear in this `Column` subtree.

---

## Proposed Solution

Change a single argument on line 2721:

```dart
// before
mainAxisSize: MainAxisSize.min,

// after
mainAxisSize: MainAxisSize.max,
```

No other changes.

---

## Database Impact

Not applicable.

---

## Flutter Architecture Changes

None. No new widgets, providers, repositories, or navigation paths.

---

## Files to Create

None.

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/features/events/widgets/event_editor_drawer.dart` | Line 2721: `MainAxisSize.min` → `MainAxisSize.max` |

---

## Files Off-Limits

All other files. This is a single-argument fix; no refactoring is in scope.

---

## Change Budget

- Net line delta: 1 line changed (0 added, 0 removed)
- New files: 0
- New public classes/methods: 0
- New dependencies: 0

---

## System Impact Map

| System | Status |
|--------|--------|
| Events / Add Event drawer | **Affected** (fixed) |
| Gigs | Unaffected |
| Rehearsals | Unaffected |
| Setlists | Unaffected |
| Members | Unaffected |
| Auth / Session | Unaffected |
| Routing | Unaffected |
| Notifications | Unaffected |
| Init order | Unaffected |
| Database / RLS | Unaffected |
| Platforms (iOS, Android, macOS, web) | All fixed equally |

---

## Regression Risk

**LOW.** Single-argument change in a leaf widget. No shared state, no database, no auth, no routing touched. The column was already receiving a finite constraint from the bottom sheet — `max` is the correct semantic, not a new constraint.

---

## Engineer Task Breakdown

1. In `lib/features/events/widgets/event_editor_drawer.dart`, find the `Column` whose immediate `Flexible` child wraps the `SingleChildScrollView` (around line 2721). Change `mainAxisSize: MainAxisSize.min` to `mainAxisSize: MainAxisSize.max`. Touch nothing else in the file.

---

## Verification Plan

### Tier 1 — Pre-deploy (no live Supabase required)

1. `flutter analyze lib/features/events/widgets/event_editor_drawer.dart` — zero new warnings or errors.
2. Hot-reload on macOS simulator: tap "+ Add Event" → drawer opens and scroll area is interactive.
3. Confirm the sticky header and footer remain visible and don't scroll away.

### Tier 2 — Post-deploy

1. On each platform (iOS, Android, macOS, web): tap "+ Add Event" from dashboard and from calendar. Drawer opens, all fields are tappable, form can be submitted. No "Cannot hit test" exception in logs.
2. Confirm the AM/PM `Row` toggle in the time picker still renders correctly (the untouched `mainAxisSize.min` in the `Row` near line 3272).

---

## QA Regression Areas

- Add Event drawer: open, interact with all fields, submit, cancel.
- Edit Event drawer (same widget, different mode): open, edit, save.
- AM/PM toggle in soundcheck time picker — verify it still renders (unrelated `mainAxisSize.min` must remain).

---

## Rollout Strategy

Standard PR against `bug/drawer-no-size-unresponsive` → `main`. No feature flag needed. Fix is self-contained and immediately safe to ship.

---

## Out of Scope

- Any visual redesign of the drawer.
- Changing the `_SectionCard` or AM/PM row layout.
- Adding tests (no existing test infrastructure for this widget; coverage is out of scope per project conventions for a one-line fix).
