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

## Preview Cycle Limitations

This is a **preview/evaluation configuration** to allow Tony to assess Forui's visual design before committing to production. The following limitations apply:

### Props Ignored in Preview

The wrappers preserve their full API contracts (call sites unchanged), but the following props are **no-ops** in the Forui preview:

#### AppButton

- `backgroundColor`
- `borderRadius`
- `elevation`
- `disabledBackgroundColor`
- `disabledForegroundColor`
- `padding`

#### AppScaffold

- `backgroundColor`
- `floatingActionButton` (not supported by FScaffold)

#### AppAppBar

- `backgroundColor`

#### AppIconButton

- `color`
- `size`

#### AppCard

- `padding`

#### AppTextField / AppTextFormField

- `decoration` (full InputDecoration not supported)
- `prefixIcon`
- `suffixIcon`
- `minLines`
- `maxLength`
- `textCapitalization`
- `textInputAction`
- `textAlign`
- `style`
- `inputFormatters`
- `autofillHints`
- `onSubmitted`
- `onEditingComplete`
- `onTap`
- `autofocus`
- `readOnly`

#### AppSwitch

- `activeColor`
- `activeTrackColor`
- `useAdaptiveSwitch`

#### AppCheckbox

- `activeColor`
- Tristate (indeterminate) — null values treated as false

#### AppDropdown

- `hint`
- Format function uses `toString()` (may not be ideal for all types)

#### AppBottomSheet

- `backgroundColor`
- `shape`
- `isScrollControlled`
- `useSafeArea`
- `barrierColor`

#### AppProgressIndicator

- `color`
- `strokeWidth`
- Circular determinate mode (always indeterminate)

### Why These Limitations Exist

Forui's API does not expose style override hooks in the same way Material does. Material buttons accept `ButtonStyle` objects with granular property control; Forui buttons accept `FButtonStyleDelta` but the plan explicitly says **"drop for preview"** to avoid the blocker patterns from implementation attempts 1 and 2.

This is acceptable for preview because:

1. **Call sites don't break** — wrappers still compile with ignored props
2. **Visual evaluation is the goal** — Tony wants to see Forui's default aesthetic
3. **Production customization is future work** — if Tony approves Forui, a follow-up cycle will implement proper style overrides

## Call Site Coverage

- **AppDropdown:** 0 call sites (unused; 5 raw `DropdownButton` usages bypass facade)
- **AppChip:** 0 call sites (unused; custom chip widgets exist but don't use this wrapper)
- **All other wrappers:** Actively used across 100+ call sites in `lib/features/`

This means **12 of 14 swapped wrappers** will be visible in Tony's preview. AppDropdown and AppChip swaps provide future-proofing but no visual coverage.

## Future Work

If Tony approves Forui after this preview:

1. **Cycle 2:** Implement proper style override support via `FButtonStyleDelta`, `FScaffoldStyleDelta`, etc.
2. **Cycle 3:** Customize Forui theme to match BandRoadie's rose accent (`#F43F5E`) and dark-only aesthetic
3. **Cycle 4:** Address AppChip (build custom Forui chip widget or investigate FTappable API)
4. **Cycle 5:** Fix facade gap — migrate 5 raw `DropdownButton` usages to AppDropdown

If Tony rejects Forui, revert this branch and continue with Material-only facade.
