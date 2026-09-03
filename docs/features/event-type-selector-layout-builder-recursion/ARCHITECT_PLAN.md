# ARCHITECT PLAN

**Feature Slug:** `bug/event-type-selector-layout-builder-recursion`
**Feature Title:** Add Event drawer crashes — `!_debugDoingThisLayout` layout recursion from `EventTypeSelector`'s `LayoutBuilder` in non-flex header context

---

## Problem Summary

Opening the Add Event drawer triggers a `'!_debugDoingThisLayout': is not true` assertion, followed by a cascade of "RenderBox was not laid out" errors. The drawer is unusable.

---

## Root Cause

**Confidence: HIGH** (confirmed by reading `event_type_selector.dart` lines 46–83)

`EventTypeSelector` wraps its segmented-control `Container` in a `LayoutBuilder`. `LayoutBuilder.performLayout()` calls `invokeLayoutCallback(builder)`. During that callback, Forui widgets inside the `Stack` register `InheritedWidget` dependencies (via `FTheme.of(context)`). This dependency registration calls `markNeedsLayout()` on an ancestor. When `EventTypeSelector` lives inside a `Flexible`/`SingleChildScrollView` (as it did before PR #228), that `markNeedsLayout()` stops at the scroll view's relayout boundary and never touches an in-flight layout. After PR #228 moved `EventTypeSelector` into the sticky header — a direct non-flex `Column` child laid out with `parentUsesSize: true` — the `markNeedsLayout()` propagates up to the outer `Column`, which is still inside its own `performLayout()` call, violating `!_debugDoingThisLayout`.

The `LayoutBuilder` was only used to obtain `constraints.maxWidth` so it could compute `segmentWidth = constraints.maxWidth / N` for the sliding indicator. `FractionallySizedBox(widthFactor: 1/N)` achieves the identical width without any layout-phase callback, eliminating the recursion.

---

## Existing System Analysis

`lib/features/events/widgets/event_type_selector.dart` (127 lines):

- The `Container(height: 44, ...)` with `padding: EdgeInsets.all(3)` is the track.
- Inside it: `LayoutBuilder` → `Stack` → `AnimatedAlign` + indicator `Container(width: segmentWidth)` + `Row` of label buttons.
- `segmentWidth` is the **only** thing the `LayoutBuilder` provides. Everything else (`currentIndex`, `alignment`, `colors`) is already available at build time.
- The `Row` uses `Expanded` on each label, so the label layout is already proportional — only the sliding indicator needs the proportional width.
- `Stack(fit: StackFit.loose)` (current default). Switching to `StackFit.expand` ensures the stack fills the `Container`, giving `FractionallySizedBox` a non-infinite parent width to fraction against.

---

## Proposed Solution

Remove `LayoutBuilder`. Replace the indicator `Container` with `FractionallySizedBox(widthFactor: 1.0 / availableTypes.length)` wrapping the same `Container` (minus the `width` property). Add `fit: StackFit.expand` to the `Stack`.

Before:
```dart
child: LayoutBuilder(
  builder: (context, constraints) {
    final segmentWidth = constraints.maxWidth / availableTypes.length;
    return Stack(
      children: [
        AnimatedAlign(
          ...
          child: Container(
            width: segmentWidth,
            height: double.infinity,
            ...
          ),
        ),
        Row(...),
      ],
    );
  },
),
```

After:
```dart
child: Stack(
  fit: StackFit.expand,
  children: [
    AnimatedAlign(
      ...
      child: FractionallySizedBox(
        widthFactor: 1.0 / availableTypes.length,
        child: Container(
          decoration: BoxDecoration(...),
        ),
      ),
    ),
    Row(...),
  ],
),
```

`StackFit.expand` sets the `Stack`'s own size to match the parent `Container` (44 px tall, full horizontal padding-inset width). `FractionallySizedBox` then sizes to exactly `parentWidth / N` — the same value `LayoutBuilder` was computing, with no layout-phase callback.

---

## Database Impact

Not applicable.

---

## Flutter Architecture Changes

None — `EventTypeSelector` remains a `StatelessWidget`. No new providers, repositories, or controllers.

---

## Files to Create

None.

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/features/events/widgets/event_type_selector.dart` | Remove `LayoutBuilder` wrapper; add `StackFit.expand` to `Stack`; replace indicator `Container(width: segmentWidth)` with `FractionallySizedBox(widthFactor: 1.0 / availableTypes.length, child: Container(...))` |

---

## Files Off-Limits

All other files. This is a single-widget rendering fix. No callers need to change — `EventTypeSelector`'s public interface (`selectedType`, `availableTypes`, `isEditMode`, `isSaving`, `onTypeChanged`) is unchanged.

---

## Change Budget

- Net line delta: −4 lines (remove `LayoutBuilder` open/close + `segmentWidth` + `Container width:` line; add `FractionallySizedBox` open/close = net −4)
- New files: 0
- New public classes/methods: 0
- New dependencies: 0

---

## System Impact Map

| System | Status |
|--------|--------|
| Gigs | Unaffected |
| Rehearsals | Unaffected |
| Setlists | Unaffected |
| Members | Unaffected |
| Auth / Session | Unaffected |
| Routing | Unaffected |
| Notifications | Unaffected |
| Add Event drawer (all platforms) | Fixed |
| Init order | Unaffected |

---

## Regression Risk

**LOW** — single widget, no state, no DB, no platform-conditional code, no auth/routing touch. The visual output (indicator width and position) is mathematically identical pre/post. The only risk is a miscalculation of `FractionallySizedBox` parent bounds if `StackFit.expand` is omitted; the verification plan covers this.

---

## Engineer Task Breakdown

**Task 1 — Replace `LayoutBuilder` with `FractionallySizedBox` in `EventTypeSelector`**

File: `lib/features/events/widgets/event_type_selector.dart`

1. Delete the `LayoutBuilder` wrapper and the `segmentWidth` local variable (lines 46–83 approx).
2. On the `Stack`, add `fit: StackFit.expand`.
3. Replace `AnimatedAlign`'s child from:
   ```dart
   Container(
     width: segmentWidth,
     height: double.infinity,
     decoration: BoxDecoration(...),
   )
   ```
   to:
   ```dart
   FractionallySizedBox(
     widthFactor: 1.0 / availableTypes.length,
     child: Container(
       decoration: BoxDecoration(...),
     ),
   )
   ```
4. The `Row(children: availableTypes.map(...).toList())` is unchanged.

No other edits.

---

## Verification Plan

### Tier 1 — Pre-deploy (no drawer open required)

1. `flutter analyze lib/features/events/widgets/event_type_selector.dart` — zero errors/warnings.
2. Visual inspection of the widget in isolation (hot reload on macos target): confirm indicator width matches `1/N` of the track for N = 1, 2, 3 segment counts.

### Tier 2 — Post-deploy (manual, all affected platforms)

1. Open Add Event drawer (any platform). Confirm no assertion fires and the drawer renders.
2. Tap each event type (Rehearsal / Gig / Block Out). Confirm the rose pill slides to the correct segment and fills exactly one-third of the track.
3. Open Add Event drawer in edit mode (existing event). Confirm disabled state (faded pill, no tap response) renders correctly.
4. Confirm no visual regression on existing events list / other screens.

---

## QA Regression Areas

- Add Event drawer (all platforms: iOS, Android, macOS, Web)
- `EventTypeSelector` appearance: pill width, pill position per selection, disabled state alpha
- No other screens use `EventTypeSelector` directly (confirm with `grep -r EventTypeSelector lib/` — expected: one call site in the event drawer header)

---

## Rollout Strategy

Standard PR → review → merge to `main` → deploy web. No feature flag needed. No DB migration.

---

## Out of Scope

- Refactoring `EventTypeSelector` to a `StatefulWidget`.
- Changing the `EventTypeSelector` public API.
- Any other layout issues in the event drawer.
- Replacing other `LayoutBuilder` usages elsewhere in the codebase.
