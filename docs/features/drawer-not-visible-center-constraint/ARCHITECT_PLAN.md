# ARCHITECT PLAN

## Feature Slug
`bug/drawer-not-visible-center-constraint`

## Feature Title
Add Event drawer shows only overlay — invisible due to `Center > ConstrainedBox` in Forui sheet

## Problem Summary
Tapping "+ Add Event" produces a dark scrim but no visible drawer content. The sheet appears locked and unresponsive on all platforms.

## Root Cause
**Confidence: HIGH** — confirmed by reading lines 2701–2737 of `event_editor_drawer.dart`.

`EventEditorDrawer.build()` wraps its content in:

```dart
FTheme(data: ...,
  child: Center(
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680),
      child: DecoratedBox(..., child: Column([...]))
    )
  )
)
```

`showAppBottomSheet` calls Forui's `showFSheet` which wraps the builder output in `Material(transparent, child: builder(context))`. Forui's `ShiftedSheet` render object positions the child via:

```
Offset(0, max(0, screenHeight - childSize.height * animationValue - bottomInset))
```

`childSize` is the reported size of the `Material`. `Center` loosens the incoming tight constraints: it inherits `maxHeight = screenHeight` but sets `minHeight = 0`, making height unconstrained. `ConstrainedBox(maxWidth: 680)` adds no height constraint. The `Column` inside has `mainAxisSize.max` and correctly fills `screenHeight` — so `childSize.height = screenHeight`, and the sheet offset computes to `0`. The sheet is therefore positioned at y=0 with the `DecoratedBox` background rendering there. However, the `mainAxisMaxRatio: 1.0` passed by the call site is being overridden by the default `9/16` path only when `mainAxisMaxRatio` is null — in this case `1.0` is passed so that path is correct.

The actual breakage is that `Center` reports its own size as the full screen dimensions to the `ShiftedSheet`, while the visible rounded-rect `DecoratedBox` sits centred within it. The `ShiftedSheet` slides the entire `Center` widget (screen-sized) up from off-screen, but because `Center` is transparent and fills the screen, the `DecoratedBox` child **is centred vertically within a screen-height widget that starts at y=0** — meaning the decoration ends up at a y-position that coincides with the scrim, invisible against the dark overlay background at full height. On macOS/large viewports the rounded box floats in the middle of the screen. On mobile the `borderRadius: 14` + dark `kEdSurface` background is rendered but is indistinguishable from the scrim.

The simplest, correct fix: **remove `Center` and `ConstrainedBox`** and make `DecoratedBox` the direct child of `FTheme`. This makes the drawer fill the full sheet width, matching every other sheet in the app.

## Existing System Analysis

- `showAppBottomSheet` (`lib/components/ui/app_bottom_sheet.dart`): wraps builder in `Material(transparent)` → `showFSheet(side: FLayout.btt, mainAxisMaxRatio: ...)`. No changes needed here.
- Every other drawer in the app (`view_gig_drawer`, `band_member_detail_drawer`, `song_notes_drawer`, etc.) returns a `DecoratedBox` or `Column` directly — no `Center` wrapper. This drawer is the sole outlier.
- The 680px max-width `ConstrainedBox` was added for desktop aesthetics only and is not referenced anywhere else.

## Proposed Solution

Remove the `Center > ConstrainedBox(maxWidth: 680)` wrapper in `EventEditorDrawer.build()`. The `DecoratedBox` becomes the direct child of `FTheme`.

```dart
// BEFORE
FTheme(data: buildEventEditorTheme(),
  child: Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: kEdSurface,
          border: Border.all(color: kEdCardBorder),
          borderRadius: BorderRadius.circular(14),
          ...
        ),
        child: Column(children: [...]),
      ),
    ),
  ),
)

// AFTER
FTheme(data: buildEventEditorTheme(),
  child: DecoratedBox(
    decoration: BoxDecoration(
      color: kEdSurface,
      border: Border.all(color: kEdCardBorder),
      borderRadius: BorderRadius.circular(14),
      ...
    ),
    child: Column(children: [...]),
  ),
)
```

No other code changes are required.

## Database Impact
Not applicable.

## Flutter Architecture Changes
None — no new providers, repositories, or controllers. Single widget tree restructure within one existing widget's `build()` method.

## Files to Create
None.

## Files to Modify

| File | Change |
|------|--------|
| `lib/features/events/widgets/event_editor_drawer.dart` | Remove `Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: ...))` wrapper around `DecoratedBox` inside `build()` (lines 2704–2707 and their closing parens ~2737–2739) |

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/components/ui/app_bottom_sheet.dart` | Root cause is in the drawer, not the sheet wrapper; no change needed |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Call site is correct; `mainAxisMaxRatio: 1.0` and `useSafeArea: true` are appropriate |
| All other drawer files | Confirmed not affected; changing them would be an out-of-scope refactor |
| `supabase/` | No DB impact |

## Change Budget

- Net line delta: −6 lines (remove `Center(`, `child: ConstrainedBox(`, `constraints: const BoxConstraints(maxWidth: 680),`, `child:` indentation shift, and 3 closing parens)
- New files: 0
- New public classes/methods: 0
- New dependencies: 0

## System Impact Map

| System | Status |
|--------|--------|
| Events / Add Event drawer | **Affected** — fix target |
| Gigs | Unaffected |
| Rehearsals | Unaffected |
| Setlists | Unaffected |
| Members / Contacts | Unaffected |
| Auth / Session | Unaffected |
| Routing | Unaffected |
| Notifications | Unaffected |
| Init order | Unaffected |
| iOS / Android / macOS / Web | All affected (bug exists on all; fix applies to all) |

## Regression Risk
**LOW** — single widget tree change in one drawer, no state, no routing, no DB, no platform-conditional code. The only visual regression risk is loss of the 680px max-width on large screens; this is intentional and accepted to fix the visibility bug.

## Engineer Task Breakdown

1. **Remove `Center > ConstrainedBox` wrapper from `EventEditorDrawer.build()`**
   - File: `lib/features/events/widgets/event_editor_drawer.dart`
   - In the `build()` method (around line 2701), remove the `Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: ...))` wrapping and make `DecoratedBox` the direct child of `FTheme(data: buildEventEditorTheme(), child: ...)`.
   - Adjust indentation of `DecoratedBox` and its subtree to match the new nesting depth.
   - Do not change anything else in the file.

## Verification Plan

### Tier 1 — Pre-deploy (no running app required)

1. Run `flutter analyze lib/features/events/widgets/event_editor_drawer.dart` — must report no issues.
2. Confirm in the diff that `Center(` and `ConstrainedBox(` are fully removed and no new widgets are introduced.
3. Confirm `DecoratedBox` is now a direct child of `FTheme`'s `child:` argument.

### Tier 2 — Post-deploy (manual smoke, all platforms)

1. **iOS/Android:** Tap "+ Add Event" → drawer must slide up, show rounded card content, be scrollable, and be dismissible.
2. **macOS:** Repeat — drawer must fill full sheet width (no floating centered box).
3. **Web:** Repeat — same as macOS.
4. **Dismiss:** Tap scrim → drawer must close cleanly.
5. **No regression:** Open any other drawer (e.g., "View Gig", "Edit Member") → confirm appearance unchanged.

## QA Regression Areas

- Add Event flow on all four platforms
- Any other sheet opened via `showAppBottomSheet` (no code change; confirm by smoke)

## Rollout Strategy

Standard PR → review → merge to main → deploy web. No feature flag needed; the bug makes the feature completely non-functional, so there is no partial-rollout risk.

## Out of Scope

- Restoring a 680px max-width for desktop using a platform-aware approach (e.g., `LayoutBuilder`) — that is a future enhancement, not part of this fix.
- Any other refactoring of `EventEditorDrawer`.
