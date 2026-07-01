# Architect Plan

## Feature Slug
`view-gig-drawer-polish`

## Feature Title
ViewGigDrawer Visual Polish — Font sizes, value alignment, row height, drawer height, Navigate button border

---

## Problem Summary

The `ViewGigDrawer` needs six visual improvements:
1. Gig name (header) font size too small
2. Day + date/time font size too small
3. Detail row values are right-aligned — should be left-aligned
4. Detail rows are too short vertically
5. Drawer overall height should increase to accommodate taller rows
6. Navigate button has no border outline

---

## Scope

Single file: `lib/features/gigs/widgets/view_gig_drawer.dart`
No state, navigation, data, or backend changes.

---

## Existing System Analysis

### AppTextStyles scale (ascending)

| Style | Font size | Weight |
|---|---|---|
| `navLabel` / `badge` | 11px | w600 |
| `footnote` / `label` | 13px | w600 |
| `callout` / `body` | 16px | w400 |
| `calloutEmphasized` / `button` | 16px | w600 |
| `headline` | 17px | w600 |
| `title3` / `sectionHeader` / `cardTitle` | 20px | w600 |
| `pageTitle` | 21px | w700 |
| `displayLarge` | 28px | w700 |

Source: `lib/app/theme/design_tokens.dart`, lines 309–383.

### Spacing tokens relevant to row padding

| Token | Value |
|---|---|
| `Spacing.space12` | 12.0 |
| `Spacing.space16` | 16.0 |

### Current drawer structure (`view_gig_drawer.dart`)

**Total height control — line 98–100:**
```dart
constraints: BoxConstraints(
  maxHeight: MediaQuery.of(context).size.height * 0.9,
),
```
The Column uses `mainAxisSize: MainAxisSize.min`, so actual height is content-driven. The `0.9` factor is a cap only. Taller rows increase the natural height; this cap prevents the sheet from exceeding 90% of screen height.

**Gig name — line 143–146:**
```dart
Text(
  gig.name,
  style: AppTextStyles.pageTitle.copyWith(   // 21px, w700
    color: context.colors.textPrimary,
  ),
),
```

**Day/date line — line 184–188:**
```dart
Text(
  _formatFullDate(gig.date),
  style: AppTextStyles.headline.copyWith(    // 17px, w600
    color: context.colors.textPrimary,
  ),
),
```

**Time range line — line 191–195:**
```dart
Text(
  gig.timeRange,
  style: AppTextStyles.headline.copyWith(    // 17px, w600
    color: context.colors.textPrimary,
  ),
),
```

**`_DetailRow` row padding — lines 304–307:**
```dart
padding: const EdgeInsets.symmetric(
  horizontal: Spacing.pagePadding,
  vertical: Spacing.space12,               // 12px top + 12px bottom = 24px total
),
```

**Navigate button — lines 161–167:**
```dart
IconButton(
  icon: const Icon(LucideIcons.navigation2),
  color: AppColors.primary,
  iconSize: 20,
  onPressed: () => _openNavigation(context),
  tooltip: 'Navigate',
),
```
No `style` is currently set; the button renders without a border.

**`_DetailRow` value text — lines 317–324:**
```dart
Expanded(
  child: Text(
    value,
    textAlign: TextAlign.end,              // right-aligned
    style: AppTextStyles.callout.copyWith(
      color: context.colors.textPrimary,
    ),
  ),
),
```

---

## Proposed Changes

### Change 1 — Gig name font size

**Location:** line 144, `ViewGigDrawer.build`

| | Value |
|---|---|
| Current | `AppTextStyles.pageTitle` (21px, w700) |
| Replace with | `AppTextStyles.displayLarge` (28px, w700) |

`displayLarge` is defined as `title3.copyWith(fontSize: 28)` in design_tokens.dart line 363 — it is an existing named style on the scale.

---

### Change 2 — Day/date and time range font size

**Locations:** lines 186 and 193, `ViewGigDrawer.build`

Both `_formatFullDate` and `gig.timeRange` texts currently use `AppTextStyles.headline` (17px, w600).

| | Value |
|---|---|
| Current | `AppTextStyles.headline` (17px, w600) |
| Replace with | `AppTextStyles.title3` (20px, w600) |

`title3` is the next named step up from `headline` in the scale (17 → 20). `pageTitle` (21px) is skipped because it is w700 and these are secondary content lines, not a primary title. `title3` at w600 is the correct semantic weight for date/time context labels.

---

### Change 3 — Detail row value left-alignment

**Location:** line 319, `_DetailRow.build`

| | Value |
|---|---|
| Current | `textAlign: TextAlign.end` |
| Replace with | *(remove the `textAlign` parameter — defaults to `TextAlign.start`)* |

The `Expanded` widget already fills remaining horizontal space. With `textAlign: start`, the value text will left-align within that space, placing it immediately after the 8px spacer that follows the label. No layout restructuring needed.

---

### Change 4 — Detail row vertical padding

**Location:** line 306, `_DetailRow.build`

| | Value |
|---|---|
| Current | `vertical: Spacing.space12` (12px each side = 24px total) |
| Replace with | `vertical: Spacing.space16` (16px each side = 32px total) |

`Spacing.space16` is the next defined spacing token above `space12` in design_tokens.dart.

---

### Change 5 — Navigate button border outline

**Location:** lines 161–167, `ViewGigDrawer.build`

Add a `style` parameter to the existing `IconButton` using `IconButton.styleFrom`:

```dart
IconButton(
  icon: const Icon(LucideIcons.navigation2),
  color: AppColors.primary,
  iconSize: 20,
  onPressed: () => _openNavigation(context),
  tooltip: 'Navigate',
  style: IconButton.styleFrom(
    side: const BorderSide(
      color: AppColors.primary,
      width: BrandButton.borderWidth,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
    ),
  ),
),
```

| Token | Value | Source |
|---|---|---|
| Border color | `AppColors.primary` (rose-700) | Matches existing icon color |
| Border width | `BrandButton.borderWidth` (1.5) | design_tokens.dart line 236 |
| Border radius | `Spacing.buttonRadius` (8.0) | design_tokens.dart line 35 |

`IconButton.styleFrom(side:)` is the idiomatic M3 approach (Flutter ≥3.7). No wrapper widget needed. `BrandButton` and `Spacing` are already imported via `design_tokens.dart` (imported at line 7 of the widget file).

No new imports required.

---

### Change 6 — Drawer max height

**Location:** line 99, `ViewGigDrawer.build`

| | Value |
|---|---|
| Current | `MediaQuery.of(context).size.height * 0.9` |
| Replace with | `MediaQuery.of(context).size.height * 0.92` |

Row padding increases from 24px to 32px per row (+8px). With up to 4 detail rows, total added height is ≤32px. Increasing the cap from 0.90 to 0.92 adds ~2% of screen height (~17px on a 375pt screen) as headroom. The Column's `mainAxisSize: MainAxisSize.min` means height is still content-driven; this cap only prevents clipping on small screens.

---

## Implementation Boundaries

### Files to modify

| File | What changes |
|---|---|
| `lib/features/gigs/widgets/view_gig_drawer.dart` | Lines 99, 144, 161–167, 186, 193, 306, 319 — 7 targeted edits |

### Files explicitly off-limits

| File | Reason |
|---|---|
| `lib/app/theme/design_tokens.dart` | No new styles; must use existing named styles only |
| All other files | No other system is touched |

### Migration policy
Not required.

### New dependencies
Not allowed — none needed.

### New files
None.

---

## Engineer Task Breakdown

Tasks are independent within the single file and may be applied in any order, but list them sequentially for clarity:

1. **Line 144** — Change `AppTextStyles.pageTitle` → `AppTextStyles.displayLarge` for gig name
2. **Line 186** — Change `AppTextStyles.headline` → `AppTextStyles.title3` for full date text
3. **Line 193** — Change `AppTextStyles.headline` → `AppTextStyles.title3` for time range text
4. **Line 306** — Change `vertical: Spacing.space12` → `vertical: Spacing.space16` in `_DetailRow` padding
5. **Line 319** — Remove `textAlign: TextAlign.end` from value `Text` in `_DetailRow`
6. **Lines 161–167** — Add `style: IconButton.styleFrom(side: ..., shape: ...)` to Navigate `IconButton`
7. **Line 99** — Change `* 0.9` → `* 0.92` on `maxHeight` constraint

After all edits, run `flutter analyze` and confirm 0 errors.

---

## Workspace State Note

**Dirty tree detected before branch creation.**

Current branch: `feat/view-gig-drawer` with 6 modified and 2 untracked files — all belonging to the in-progress `view-gig-drawer` feature. These are unrelated to `view-gig-drawer-polish`.

Per guardrails: do not auto-stash. The Engineer must ensure the branch is created from `main` cleanly. Branch creation is attempted via `git checkout -b feat/view-gig-drawer-polish main` which creates the new branch at `main`'s HEAD while preserving working-tree changes.

---

## System Impact Map

| System | Impact |
|---|---|
| Gigs | affected — display only, view drawer widget |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | unaffected — layout-only change, all platforms render identically |

---

## Regression Risk

**LOW**

- Single file, display-only changes
- No state mutations, no async calls, no navigation changes
- All styles used (`displayLarge`, `title3`) are pre-existing named styles already in production
- `_DetailRow` change removes `textAlign: end`; no layout restructuring
- No shared components modified

---

## Verification Plan

### Tier 1 — Pre-deployment

Not applicable — no database or migration changes.

### Tier 2 — Post-implementation

QA should visually verify on device or simulator:

1. **Gig name** renders at the larger `displayLarge` size (28px) and is not clipped or wrapped unexpectedly on narrow screens
2. **Date line** (`_formatFullDate`) and **time range** render at `title3` size (20px) — slightly larger than before
3. **Detail row values** (Load in, Setlist name, Gig pay, Notes label) are left-aligned with the row label, not right-pushed
4. **Detail rows** are visibly taller (space16 padding vs space12)
5. **Drawer** opens without any content being clipped; all rows and the footer button are visible without scrolling on a standard screen
6. **Navigate button** shows a rose border outline (`AppColors.primary`, 1.5px, 8px radius) and the icon and tap behavior are unchanged

Run `flutter analyze` after edits: must report 0 errors, 0 warnings.

---

## QA Regression Areas

- Open `ViewGigDrawer` for a gig with all four detail rows populated (load in time, setlist, gig pay, notes) and confirm all rows display correctly
- Open for a gig with no detail rows — confirm header and date/time sections are not distorted
- Tap Setlist row — confirm navigation to `SetlistDetailScreen` still works
- Tap Notes row — confirm `GigNotesSheet` opens correctly
- Tap Navigate button — confirm maps URL launch still works; confirm rose border outline is visible around the button
- Tap Done and Edit buttons — confirm callbacks fire and drawer closes

---

## Out of Scope

- Typography changes outside `view_gig_drawer.dart`
- Any changes to `gig_notes_sheet.dart`
- Color or icon changes (border color reuses existing `AppColors.primary`)
- Responsiveness or adaptive layout changes
- Changes to `_formatFullDate` or `gig.timeRange` formatting logic
