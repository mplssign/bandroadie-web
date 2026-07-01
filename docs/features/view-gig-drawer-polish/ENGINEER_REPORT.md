# Engineer Report

## Feature Slug
`view-gig-drawer-polish`

## Feature Title
ViewGigDrawer Font Size Polish

## Goal
Increase the visual prominence of the gig name and date line in `ViewGigDrawer` by stepping each up the named text style scale.

## Architect Tasks Completed
- [x] Gig name: moved two steps larger on the combined AppTextStyles/TextTheme scale
- [x] Day and date line: moved one step larger on the AppTextStyles scale

## Files Created
- none

## Files Modified
- `lib/features/gigs/widgets/view_gig_drawer.dart`

## Style Changes

### Gig name (venue/event name) — line 144

| | Style | Font size | Weight |
|---|---|---|---|
| Before | `AppTextStyles.pageTitle` | 21px | w700 |
| After | `Theme.of(context).textTheme.headlineMedium` | 26px | w700 |

`pageTitle` (21px) is the top of the `AppTextStyles` named scale. The two steps above it using the `TextTheme` sub-scale are `headlineSmall` (22px, w600) → `headlineMedium` (26px, w700). `headlineMedium` preserves the existing w700 weight and is applied via `Theme.of(context).textTheme.headlineMedium?.copyWith(color: ...)` to stay consistent with `GoogleFonts.dmSansTextTheme`.

### Day and date line — line 186

| | Style | Font size | Weight |
|---|---|---|---|
| Before | `AppTextStyles.headline` | 17px | w600 |
| After | `AppTextStyles.title3` | 20px | w600 |

One step up on the AppTextStyles scale: `headline` (17px) → `title3` (20px).

## Analyzer Results
Command: `flutter analyze lib/features/gigs/widgets/view_gig_drawer.dart`
Result: **0 errors, 0 warnings** (ran in 2.5s)

## Test Results
Not run — no test file covers this widget and no tests were specified.

## Verification
Manual steps performed:
- Confirmed current styles by reading `view_gig_drawer.dart` in full
- Confirmed the full `AppTextStyles` scale by reading `design_tokens.dart`
- Confirmed `TextTheme` scale (headlineSmall 22px/w600, headlineMedium 26px/w700, headlineLarge 32px/w700) by reading `app_theme.dart`
- Verified `flutter analyze` reports 0 issues after changes

## Deviations From Architect Plan
The gig name change uses `Theme.of(context).textTheme.headlineMedium` (a TextTheme style) rather than an `AppTextStyles` name. This is required because `pageTitle` is the topmost style in `AppTextStyles`; there are no named `AppTextStyles` styles two steps above it. The task explicitly permits `AppTextStyles OR TextTheme scale`. `headlineMedium` is defined in `GoogleFonts.dmSansTextTheme(...)` so the font family (DM Sans) and bold weight (w700) are preserved.

## Blockers Encountered
None.

## Ready For QA
Yes

---

# Engineer Report — Amendment: Left-align Detail Row Values

## Task
Left-align the value text in all four `_DetailRow` instances (Load in, Setlist, Gig pay, Notes) so values read naturally left-to-right after the label, rather than being pushed to the far right.

## Root Cause
`_DetailRow.build()` in `view_gig_drawer.dart` (line 320) wrapped the value `Text` in an `Expanded` with `textAlign: TextAlign.end`. This caused the value to right-align across the full remaining width, creating a split label-left / value-right layout.

## What Changed

**File:** `lib/features/gigs/widgets/view_gig_drawer.dart`

| Location | Before | After |
|---|---|---|
| `_DetailRow` value `Text`, line 320 | `textAlign: TextAlign.end` | `textAlign: TextAlign.start` |

The `Expanded` is kept so the chevron icon remains pinned to the far right (it is positioned outside the `Expanded`). Only the text alignment changes. This single-line change affects all four rows — Load in, Setlist, Gig pay, Notes — because they all share the same `_DetailRow` widget.

## Analyzer Results
Command: `flutter analyze lib/features/gigs/widgets/view_gig_drawer.dart`
Result: **0 errors, 0 warnings** (ran in 2.5s)

## Deviations From Plan
None — this was a direct task, not an Architect-planned change.

## Ready For QA
Yes

---

# Engineer Report — Amendment: Fix `_DetailRow` Label Column Width

## Task
Wrap the label `Text` in `_DetailRow` in a `SizedBox` with a fixed width so the value column starts at the same x-position on every row.

## What Changed

**File:** `lib/features/gigs/widgets/view_gig_drawer.dart`

**Width chosen:** `68` — sized to comfortably fit the longest label ("Gig pay") at callout size in DM Sans.

**Lines changed:** ~312–318 (label `Text` in `_DetailRow.build()`)

| Location | Before | After |
|---|---|---|
| `_DetailRow` label | bare `Text(label, ...)` | `SizedBox(width: 68, child: Text(label, ...))` |

The `SizedBox(width: Spacing.space8)` spacer is preserved immediately after the label `SizedBox`. The `Expanded` wrapping the value `Text` follows, unchanged. The chevron structure (`if (showChevron)` block outside `Expanded`) is fully preserved — the chevron remains pinned to the far right.

## Analyzer Results
Command: `flutter analyze lib/features/gigs/widgets/view_gig_drawer.dart`
Result: **0 errors, 0 warnings** (ran in 2.6s)

## Deviations From Plan
None.

## Ready For QA
Yes

---

# Engineer Report — Amendment: Fix `_DetailRow` Label Column Width (Full Source Verification)

## Task
Verify and document the full source of `_DetailRow.build()` before and after the `SizedBox(width: 68)` label wrap. The change was applied in the prior session; this amendment provides the complete line-by-line source record for QA.

## `_DetailRow.build()` — BEFORE (bare `Text` label, no SizedBox)

```dart
@override
Widget build(BuildContext context) {
  final row = Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Spacing.pagePadding,
      vertical: Spacing.space12,
    ),
    child: Row(
      children: [
        Text(
          label,
          style: AppTextStyles.callout.copyWith(
            color: context.colors.textMuted,
          ),
        ),
        const SizedBox(width: Spacing.space8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.start,
            style: AppTextStyles.callout.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ),
        if (showChevron) ...[
          const SizedBox(width: Spacing.space4),
          Icon(
            AppIcons.forward,
            size: 16,
            color: context.colors.textMuted,
          ),
        ],
      ],
    ),
  );

  return Column(
    children: [
      onTap != null ? InkWell(onTap: onTap, child: row) : row,
      Divider(height: 1, color: context.colors.border),
    ],
  );
}
```

## `_DetailRow.build()` — AFTER (label `Text` wrapped in `SizedBox(width: 68)`)

```dart
@override
Widget build(BuildContext context) {
  final row = Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Spacing.pagePadding,
      vertical: Spacing.space12,
    ),
    child: Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: AppTextStyles.callout.copyWith(
              color: context.colors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: Spacing.space8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.start,
            style: AppTextStyles.callout.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ),
        if (showChevron) ...[
          const SizedBox(width: Spacing.space4),
          Icon(
            AppIcons.forward,
            size: 16,
            color: context.colors.textMuted,
          ),
        ],
      ],
    ),
  );

  return Column(
    children: [
      onTap != null ? InkWell(onTap: onTap, child: row) : row,
      Divider(height: 1, color: context.colors.border),
    ],
  );
}
```

## Analyzer Results
Command: `flutter analyze lib/features/gigs/widgets/view_gig_drawer.dart`
Result: **0 errors, 0 warnings** (ran in 1.1s)

## Deviations From Plan
None. The change matches the task spec exactly — only the label `Text` gained a `SizedBox(width: 68)` wrapper. The spacer, `Expanded`, value `Text`, and chevron block are unchanged.

## Ready For QA
Yes
