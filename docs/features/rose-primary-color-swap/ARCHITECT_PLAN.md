# ARCHITECT_PLAN.md — Rose Primary Color Swap

## Feature Slug

`feature/rose-primary-color-swap`

## Problem Summary

BandRoadie's current brand primary color is rose-700 (`#BE123C`). The design system must be updated to use shadcn/Forui's Rose reference theme primary (`#FF2056`, equivalent to `oklch(0.645 0.246 16.439)`). This is a design-token alignment — no functional changes, no widget structure changes, no new dependencies.

## Root Cause

**Not applicable** — this is not a bug fix. This is a deliberate design token change to align BandRoadie's primary color with the shadcn/Forui Rose reference theme.

**Confidence:** N/A (design decision, not a diagnosed failure)

## Reference Docs Consulted

None required — this is a color token swap with no system-level architecture implications.

## Existing System Analysis

### Current State

- `AppColors.primary` is defined as `Color(0xFFBE123C)` (rose-700) in `design_tokens.dart` line 153
- `BrandColors.dark.primaryDim` is `Color(0xFFBE123C)` in `brand_colors.dart` line 60
- `BrandColors.light.primaryDim` is `Color(0xFFBE123C)` in `brand_colors.dart` line 82
- `app_theme.dart` line 619 references `AppColors.primary` dynamically with a trailing comment `// Rose-700 #BE123C`

### Documentation/Code Mismatch (Pre-existing)

The doc comment on `design_tokens.dart` line 152 claims "Rose-500: brighter and more stage-ready than previous rose-700" but the code on line 153 is still `Color(0xFFBE123C)` with the comment `// rose-700`. This inconsistency predates this feature and will be corrected as part of the token swap.

### Exclusion: Tuning Color-Coding

`lib/features/setlists/tuning/tuning_helpers.dart` lines 282-283 define guitar tuning colors:

```dart
'open e': const Color(0xFFBE123C),
'open_e': const Color(0xFFBE123C),
```

This is domain-specific color-coding for guitar tunings, unrelated to brand theming. Changing it would silently break tuning badge colors. This file **must not be modified**.

## Proposed Solution

Replace the three hex literals `0xFFBE123C` with `0xFFFF2056` in exactly three locations:

1. `lib/app/theme/design_tokens.dart` line 153 — `AppColors.primary`
2. `lib/app/theme/brand_colors.dart` line 60 — `BrandColors.dark.primaryDim`
3. `lib/app/theme/brand_colors.dart` line 82 — `BrandColors.light.primaryDim`

Also correct two comment inaccuracies:

4. `design_tokens.dart` line 152 — update the doc comment to accurately describe the new `#FF2056` value as the shadcn/Forui Rose primary (not "Rose-500... than previous rose-700")
5. `app_theme.dart` line 619 — update the trailing comment from `// Rose-700 #BE123C` to reflect the new value

Optional drive-by fix (not required for acceptance): 6. `lib/features/setlists/widgets/special_item_card.dart` line 13 — the comment claims "rose accent (#BE123C)" but the code reads `context.colors.primaryDim` dynamically, so it will pick up the new value automatically. The comment may be updated to reference the new hex or removed in favor of the dynamic reference.

## Database Impact

**Not applicable** — this is a client-side UI token change only. No database schema, RLS policies, RPC functions, or migrations are affected.

## Flutter Architecture Changes

**None** — no state management changes, no widget structure changes, no new providers, no new repositories. This is a pure constant value swap.

Affected systems:

- **Theme system** — the three color constants change value
- **All widgets that reference `AppColors.primary` or `context.colors.primaryDim`** — they will render with the new color automatically

## Files to Create

**None**

## Files to Modify

| File                                                   | What changes                                                                                                                                                                                                                            |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/app/theme/design_tokens.dart`                     | Line 152: Update doc comment to accurately describe the new `#FF2056` as the shadcn/Forui Rose primary<br>Line 153: Change `Color(0xFFBE123C)` to `Color(0xFFFF2056)` and update inline comment from `// rose-700` to reflect new value |
| `lib/app/theme/brand_colors.dart`                      | Line 60: Change `primaryDim: Color(0xFFBE123C)` to `Color(0xFFFF2056)` in `BrandColors.dark`<br>Line 82: Change `primaryDim: Color(0xFFBE123C)` to `Color(0xFFFF2056)` in `BrandColors.light`                                           |
| `lib/app/theme/app_theme.dart`                         | Line 619: Update trailing comment from `// Rose-700 #BE123C` to reflect new hex value (code already reads `AppColors.primary` dynamically — no functional change)                                                                       |
| `lib/features/setlists/widgets/special_item_card.dart` | _(Optional)_ Line 13: Update comment from `#BE123C` to `#FF2056` or remove hex reference in favor of dynamic `primaryDim` mention                                                                                                       |

## Files Off-Limits

| File                                                                  | Reason                                                                                                                                                                                                                    |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/tuning/tuning_helpers.dart`                    | Lines 282-283 define guitar tuning color-coding (`'open e'` / `'open_e': Color(0xFFBE123C)`) unrelated to brand theming. Changing this would silently break tuning badge colors. Must have **zero diff**.                 |
| `lib/app/theme/brand_colors.dart` (lines 64 and 86 — `primarySubtle`) | These use `0x4DF43F5E` and `0x1AF43F5E`, which are alpha-blended versions of an even older rose shade. This is a pre-existing drift issue tracked for a future token-architecture cleanup. Out of scope for this feature. |
| All other files                                                       | No other files should be modified. This is a targeted token swap — no refactoring, no formatting, no opportunistic cleanup.                                                                                               |

## System Impact Map

| System                                 | Impact                                                                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | Unaffected (reads theme tokens, no logic change)                                                                       |
| Rehearsals                             | Unaffected (reads theme tokens, no logic change)                                                                       |
| Setlists / Catalog                     | Unaffected (reads theme tokens, no logic change)                                                                       |
| Members / RBAC                         | Unaffected                                                                                                             |
| Auth / Session                         | Unaffected                                                                                                             |
| Routing                                | Unaffected                                                                                                             |
| Notifications                          | Unaffected                                                                                                             |
| Theme System                           | **Affected** — three color constants change value; all widgets that reference them render with new color automatically |
| Platform (iOS / Android / Web / macOS) | **Affected** — visual change only; all platforms pick up new color                                                     |

## Regression Risk

**LOW**

Rationale:

- Only three color constant values change — no logic, no state, no widget structure
- All consumers of these tokens are read-only references — they do not mutate the color or depend on its specific hex value for correctness
- No database, no auth, no routing, no initialization order affected
- Tuning color-coding is explicitly protected (zero diff on `tuning_helpers.dart`)
- No new dependencies, no new files
- This is a visual-only change — worst-case failure mode is "the app looks different," not "the app crashes or loses data"

## Engineer Task Breakdown

### Task 1 — Update `design_tokens.dart`

- Open `lib/app/theme/design_tokens.dart`
- Line 152: Replace the doc comment with an accurate description of the new `#FF2056` as the shadcn/Forui Rose primary (not "Rose-500... than previous rose-700")
- Line 153: Change `Color(0xFFBE123C)` to `Color(0xFFFF2056)`
- Line 153 inline comment: Change `// rose-700` to reflect the new value (e.g., `// shadcn/Forui Rose primary`)

### Task 2 — Update `brand_colors.dart`

- Open `lib/app/theme/brand_colors.dart`
- Line 60 (dark theme): Change `primaryDim: Color(0xFFBE123C),` to `primaryDim: Color(0xFFFF2056),`
- Line 82 (light theme): Change `primaryDim: Color(0xFFBE123C),` to `primaryDim: Color(0xFFFF2056),`

### Task 3 — Update `app_theme.dart` comment

- Open `lib/app/theme/app_theme.dart`
- Line 619: Change trailing comment from `// Rose-700 #BE123C` to `// shadcn/Forui Rose #FF2056`
- Verify no functional change (code already reads `AppColors.primary` dynamically)

### Task 4 — (Optional) Update `special_item_card.dart` comment

- Open `lib/features/setlists/widgets/special_item_card.dart`
- Line 13: Update comment from `#BE123C` to `#FF2056`, or remove hex reference in favor of "reads `primaryDim` dynamically"
- This is a documentation-only change — code already reads `context.colors.primaryDim`

### Task 5 — Verify exclusions

- Run `git diff lib/features/setlists/tuning/tuning_helpers.dart`
- Assert output is empty (file has zero diff)
- Run `git diff` and verify only the four files listed in "Files to Modify" appear in the diff
- Count changed hex literals: must be exactly 3 (design_tokens.dart line 153, brand_colors.dart lines 60 and 82)

### Task 6 — Run static analysis

- Run `flutter analyze`
- Assert 0 errors
- Assert 0 warnings related to color definitions

## Verification Plan

### Tier 1 — Pre-deployment (Compile-Time Verification)

_Not applicable_ — this feature has no database or backend components. All verification is compile-time or runtime Flutter.

### Tier 2 — Post-deployment (Flutter Tests)

**POST-DEPLOY TEST 1: Verify `AppColors.primary` hex value**

```dart
test('AppColors.primary is #FF2056', () {
  expect(AppColors.primary.value, equals(0xFFFF2056));
});
```

**POST-DEPLOY TEST 2: Verify `BrandColors.dark.primaryDim` hex value**

```dart
test('BrandColors.dark.primaryDim is #FF2056', () {
  expect(BrandColors.dark.primaryDim.value, equals(0xFFFF2056));
});
```

**POST-DEPLOY TEST 3: Verify `BrandColors.light.primaryDim` hex value**

```dart
test('BrandColors.light.primaryDim is #FF2056', () {
  expect(BrandColors.light.primaryDim.value, equals(0xFFFF2056));
});
```

**POST-DEPLOY TEST 4: Verify tuning colors unchanged**

```dart
test('Open E tuning color is unchanged (not brand primary)', () {
  final openETuning = TuningHelpers.tuningColors['open_e'];
  expect(openETuning?.value, equals(0xFFBE123C)); // Must remain old value
});
```

**POST-DEPLOY TEST 5: Verify no other color constants changed**
Run `git diff` and assert:

- Exactly 3 lines contain `0xFFFF2056` (design_tokens.dart line 153, brand_colors.dart lines 60 and 82)
- No other `Color(0xFF...)` literals changed anywhere in the diff
- `primarySubtle` (lines 64 and 86 in brand_colors.dart) still uses `0x4DF43F5E` and `0x1AF43F5E`

## QA Regression Areas

### Primary Validation (Must Test)

1. **Visual inspection** — primary color appears as `#FF2056` (brighter rose) in:
   - CTA buttons (e.g., "Create Setlist", "Add Song")
   - Active navigation indicators
   - Focus rings on form inputs
   - Links
2. **Tuning badges** — Open E tuning badges still render as the darker `#BE123C` (not the new primary color)
3. **Theme consistency** — both light and dark modes render the new primary color consistently

### Contrast Note (Not a Blocker)

White-on-primary text contrast changes from ~8:1 (old `#BE123C`) to ~3.75:1 (new `#FF2056` with pure white foreground). This is below WCAG AA's 4.5:1 for normal text, though:

- Consistent with shadcn/Forui's own choice of near-white foreground on this primary
- Above the 3:1 threshold for large text and UI components
- BandRoadie uses primary color predominantly for large CTA buttons and UI components, not body text

QA should note this in the report but it is not a blocker — this is an intentional design alignment with the reference theme.

### Regression Testing (Should Not Break)

- Setlist creation and editing
- Song card interactions
- Navigation between screens
- Form inputs and validation states
- Modal overlays and bottom sheets

None of these should have functional regressions — this is a visual-only change.

## Rollout / Migration Strategy

**Not applicable** — no database migrations, no backend changes, no feature flags. The new color will appear immediately after the Flutter app is rebuilt and deployed.

For web (Vercel deployment):

- Run `flutter build web --release`
- Deploy via `cd build/web && vercel --prod`
- Incognito load to confirm new primary color renders

For native platforms (iOS / Android / macOS):

- Rebuild and redeploy as normal
- No special migration steps required

## Out of Scope

Explicitly **not included** in this feature:

1. **Neutral palette** — background, surface, border, and text colors are unchanged. Forui's stock `neutralLight` and `neutralDark` presets already match the reference theme exactly.
2. **`primarySubtle` drift fix** — `BrandColors.dark.primarySubtle` (`0x4DF43F5E`) and `BrandColors.light.primarySubtle` (`0x1AF43F5E`) reference an even older rose shade. This is a pre-existing drift issue tracked for a future token-architecture cleanup.
3. **Component logic changes** — no widget structure changes, no state management changes, no new dependencies.
4. **Contrast adjustments** — the new `#FF2056` primary with white foreground produces ~3.75:1 contrast, below WCAG AA's 4.5:1 for normal text. This is intentional (matches the shadcn reference) and is not adjusted in this feature. If contrast becomes a UX issue, it will be addressed in a separate feature.
5. **Tuning color-coding** — `tuning_helpers.dart` lines 282-283 (`'open e'` / `'open_e': Color(0xFFBE123C)`) are unrelated domain logic and must not be modified.

---

**Architect: Approved for Engineering**  
**Date:** 2026-08-14  
**Risk Level:** LOW  
**Estimated Implementation Time:** 10 minutes
