# UI Facade Components

This directory contains 15 wrapper widgets that provide a consistent UI abstraction layer across BandRoadie. All feature code uses these wrappers instead of calling Material or Forui widgets directly.

## Current State (Forui Preview Cycle)

As of 2026-08-12, **14 of 15 wrappers** have been swapped to use Forui design system internally:

### Forui-Styled Wrappers (14)

1. **AppScaffold** → `FScaffold`
2. **AppAppBar** → `FHeader`
3. **AppButton** → `FButton`
4. **AppIconButton** → `FButton.icon`
5. **AppTextField** → `FTextField`
6. **AppTextFormField** → `FTextFormField`
7. **AppCard** → `FCard`
8. **AppDialog** → `FDialog`
9. **AppBottomSheet** → `FSheet`
10. **AppSwitch** → `FSwitch`
11. **AppCheckbox** → `FCheckbox`
12. **AppDropdown** → `FSelect.rich` (unused in codebase, future-proofed)
13. **AppSnackbar** → `showFToast`
14. **AppProgressIndicator** → `FProgress` / `FCircularProgress`

### Material-Only Wrappers (1)

- **AppChip** — Remains Material-only (`Chip`, `FilterChip`, `ActionChip`)
  - **Reason:** No confirmed Forui equivalent for interactive filter chips. `FBadge` is for static labels. `FTappable` primitive has unclear gesture callback API.
  - **Impact:** Zero call sites in current codebase (unused wrapper).

## Props Not Supported in Forui

The wrappers preserve their full API contracts (call sites unchanged), but the following props have **genuine Forui limitations** and cannot be fully supported:

#### AppButton

- `elevation` — Forui buttons do not expose Material-style elevation shadows
- `disabledBackgroundColor` — Use variant styling instead
- `disabledForegroundColor` — Use variant styling instead

#### AppScaffold

- `backgroundColor` — Not exposed in FScaffold API
- `floatingActionButton` — FScaffold does not have FAB concept (use footer actions instead)

#### AppAppBar

- `backgroundColor` — Not exposed in FHeader API

#### AppIconButton

- `color` — Use variant styling instead
- `size` — Use variant styling instead

#### AppTextField / AppTextFormField

- `decoration` — Full InputDecoration not supported (Forui uses different decoration model)
- `style` — Use Forui theme styling instead

#### AppSwitch

- `useAdaptiveSwitch` — Forui handles platform adaptation automatically

#### AppCheckbox

- Tristate (indeterminate) — FCheckbox does not support null values, null is treated as false

#### AppDropdown

- `hint` — Not exposed in FSelect API
- Format function uses `toString()` (may not be ideal for all types)

#### AppBottomSheet

- `backgroundColor` — StyleDelta API not publicly documented
- `shape` — StyleDelta API not publicly documented
- `isScrollControlled` — FSheet uses different scroll handling
- `useSafeArea` — FSheet uses different safe area handling
- `barrierColor` — Not exposed in FSheet API

#### AppProgressIndicator

- `color` — Use variant styling instead
- `strokeWidth` — Use variant styling instead
- Circular determinate mode — FCircularProgress always indeterminate

### Props Now Supported (Restored in This Cycle)

The following props were restored and now work correctly:

#### AppButton

- `backgroundColor` ✅
- `borderRadius` ✅
- `padding` ✅

#### AppTextField / AppTextFormField

- `prefixIcon` ✅ (via builder pattern)
- `suffixIcon` ✅ (via builder pattern)
- `minLines` ✅
- `maxLength` ✅
- `textCapitalization` ✅
- `textInputAction` ✅
- `textAlign` ✅
- `inputFormatters` ✅
- `autofillHints` ✅
- `onSubmitted` ✅ (mapped to onSubmit)
- `onEditingComplete` ✅
- `onTap` ✅
- `autofocus` ✅
- `readOnly` ✅

#### AppSwitch

- `activeColor` ✅
- `activeTrackColor` ✅

#### AppCheckbox

- `activeColor` ✅

#### AppCard

- `padding` ✅

## Call Site Coverage

- **AppDropdown:** 0 call sites (unused; 5 raw `DropdownButton` usages bypass facade)
- **AppChip:** 0 call sites (unused; custom chip widgets exist but don't use this wrapper)
- **All other wrappers:** Actively used across 100+ call sites in `lib/features/`

This means **12 of 14 swapped wrappers** will be visible in Tony's preview. AppDropdown and AppChip swaps provide future-proofing but no visual coverage.

## Future Work

If Tony approves Forui after this preview:

1. **Cycle 2:** Address remaining StyleDelta gaps (elevation, disabled colors, etc.)
2. **Cycle 3:** Customize Forui theme to match BandRoadie's rose accent (`#F43F5E`) and dark-only aesthetic
3. **Cycle 4:** Address AppChip (build custom Forui chip widget or investigate FTappable API)
4. **Cycle 5:** Fix facade gap — migrate 5 raw `DropdownButton` usages to AppDropdown

If Tony rejects Forui, revert this branch and continue with Material-only facade.
