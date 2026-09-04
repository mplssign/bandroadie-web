# UI Facade Components

This directory contains 15 wrapper widgets that provide a consistent UI abstraction layer across BandRoadie. All feature code uses these wrappers instead of calling Material or Forui widgets directly.

## Current State (Forui Preview Cycle)

As of 2026-08-12, **all 15 wrappers** have been swapped to use Forui design system internally:

### Forui-Styled Wrappers (16)

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
12. **AppDropdown** → `FSelect.rich` (10 call sites: 6 via EventDropdown, 4 direct, includes Form integration)
13. **AppSnackbar** → `showFToast`
14. **AppProgressIndicator** → `FProgress` / `FCircularProgress`
15. **AppChip** → `FBadge` + `FTappable.static` (selectable badge pattern)
16. **SheetFooter** — standard sticky footer for modal sheets/drawers (surface container + top border + shadow; primary filled rose right-aligned; cancel text left-aligned; optional full-width destructive row above)

### Implementation Notes

**AppChip:** Uses the recommended Forui pattern for interactive badges — `FBadge` wrapped in `FTappable.static` for selection and tap handling. Supports filter/action/default variants and enabled/disabled states. Integrated in Cycle 4 (feature/domain-chip-forui-consolidation).

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

- `hint` — Not natively supported in Forui. Workaround: use explicit null-value DropdownMenuItem as first item instead (preserves functionality, drops hint API)
- Supports custom format/labelBuilder functions for display text
- Supports enabled/disabled state via `enabled` parameter
- Supports Form integration via `validator`, `onSaved`, `autovalidateMode` parameters (FSelect natively implements FormField)
- Supports grouped dropdowns via `children` prop with FSelectSection (for timezone-style headers)

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

- **AppDropdown:** 10 call sites (4 direct, 6 via EventDropdown wrapper)
- **AppChip:** 6 indirect call sites via `EmailDomainShortcutBar` (4 in selection mode, 2 in tap-to-apply mode)
- **All other wrappers:** Actively used across 100+ call sites in `lib/features/`

This means **all 15 Forui-styled wrappers** are actively used and ready for production.

## Future Work

If Tony approves Forui after this preview:

1. **Cycle 2:** Address remaining StyleDelta gaps (elevation, disabled colors, etc.)
2. ~~**Cycle 3:** Customize Forui theme to match BandRoadie's rose accent (Rose-700 `#BE123C`) and reactive light/dark mode~~ — **COMPLETED** in `feature/forui-theme-integration`
3. ~~**Cycle 4:** Address AppChip (build custom Forui chip widget or investigate FTappable API)~~ — **COMPLETED** in `feature/domain-chip-forui-consolidation`
4. ~~**Cycle 5:** Fix facade gap — migrate raw `DropdownButton` usages to AppDropdown~~ — **COMPLETED** in `feature/dropdown-facade-migration`

If Tony rejects Forui, revert this branch and continue with Material-only facade.
