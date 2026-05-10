# ARCHITECT PLAN — Print Options Dark Mode Fix

**Feature ID**: `bug/print-options-dark-mode`  
**Type**: Bug fix  
**Branch**: `bug/print-options-dark-mode`  
**Confidence**: HIGH

---

## Problem Summary

The Print Options bottom sheet renders with a hardcoded light gray background (`#D1D5DB`) when displayed, regardless of whether the app is in dark mode or light mode. This creates a jarring visual inconsistency where the bottom sheet appears in light mode while the rest of the app is in dark mode.

**Expected Behavior**: The Print Options bottom sheet background should match the app's current theme (dark in dark mode, light in light mode).

**Actual Behavior**: The bottom sheet always displays with a light gray background color.

**Affected Platforms**: iOS, Android, macOS, Web (all platforms)

---

## Root Cause Analysis

**Location**: `lib/features/setlists/widgets/print_options_bottom_sheet.dart`, lines 48-54

**Root Cause**: The `showModalBottomSheet` static method has a **hardcoded backgroundColor** parameter:

```dart
return showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: const Color(0xFFD1D5DB),  // ← HARDCODED LIGHT GRAY
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  ),
  builder: (context) => PrintOptionsBottomSheet(...),
);
```

The color `0xFFD1D5DB` is a light gray (approximately Tailwind's gray-300), which completely ignores Flutter's theme system and the app's `BrandColors` theme extension.

The rest of the bottom sheet widget correctly uses `context.colors` for all internal styling (text, borders, buttons), but the modal backdrop itself is forced to light mode by this single hardcoded value.

**Confidence**: **HIGH** — Direct observation in code. The fix is unambiguous.

---

## Diagnosis Evidence

1. **Hardcoded color at modal level**: Line 50 explicitly sets `backgroundColor: const Color(0xFFD1D5DB)`
2. **Theme-aware colors used internally**: Throughout the widget (lines 300+), the implementation correctly uses `context.colors.surface`, `context.colors.textPrimary`, `context.colors.border`, etc.
3. **Design tokens available**: `lib/app/theme/brand_colors.dart` defines proper surface colors:
   - Dark mode: `surface: Color(0xFF18181B)`, `surfaceElevated: Color(0xFF27272A)`
   - Light mode: `surface: Color(0xFFFAFAFA)`, `surfaceElevated: Color(0xFFF4F4F5)`
4. **Context extension available**: `BrandColorsX` extension provides `context.colors` accessor (already used throughout the widget)

---

## Proposed Solution

Replace the hardcoded `backgroundColor` with a theme-aware color from Flutter's `ThemeData`.

### Change Required

**File**: `lib/features/setlists/widgets/print_options_bottom_sheet.dart`

**Line 48-54** — Replace:

```dart
return showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: const Color(0xFFD1D5DB),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  ),
  builder: (context) => PrintOptionsBottomSheet(...),
);
```

With:

```dart
return showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
  ),
  builder: (context) => PrintOptionsBottomSheet(...),
);
```

**Rationale**: 
- `Theme.of(context).colorScheme.surface` is the standard Material 3 surface color, which is already configured correctly in `app_theme.dart` to use `BrandColors.dark.surface` for dark mode
- This is the minimal change — one line replacement
- No new colors introduced; uses existing theme infrastructure
- Consistent with Material Design guidelines for modal surfaces

---

## Files to Modify

1. **`lib/features/setlists/widgets/print_options_bottom_sheet.dart`**
   - Line 50: Replace hardcoded `Color(0xFFD1D5DB)` with `Theme.of(context).colorScheme.surface`
   - **No other changes required**

---

## System Impact Assessment

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | affected — print options rendering only |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Database | not applicable |
| RLS | not applicable |
| RPC | not applicable |
| Edge Functions | not applicable |

---

## Testing Checklist

### Visual Verification (All Platforms)

- [ ] Dark mode: Print Options bottom sheet has dark background
- [ ] Dark mode: All text, icons, and controls inside sheet are visible and properly themed
- [ ] Light mode (if toggled): Bottom sheet has light background
- [ ] No visual artifacts or z-index issues with the modal backdrop
- [ ] Border radius remains 16px at top corners
- [ ] Drag handle is visible against the background

### Regression Testing

- [ ] All print options toggles function correctly
- [ ] Font size sliders work as expected
- [ ] Saved layouts can be selected, saved, and deleted
- [ ] Preview navigation works
- [ ] Bottom action bar (Save Layout, Preview buttons) renders correctly

### Platform Coverage

- [ ] iOS
- [ ] Android
- [ ] macOS
- [ ] Web

---

## Migration & Rollback

**Migration**: None required — client-side UI change only  
**Rollback**: Trivial — revert the one-line change  
**Breaking Changes**: None

---

## Additional Context

- **No new design tokens required**: All colors already exist in `BrandColors`
- **No architecture changes**: Existing pattern of using `Theme.of(context).colorScheme` is already used throughout the app
- **No performance impact**: Same rendering path, just pulling color from theme instead of const
- **Consistent with codebase patterns**: Other bottom sheets and modals use theme-aware colors (see `lib/components/`, `lib/features/contacts/`, etc.)

---

## Implementation Notes for Engineer

1. Make the one-line change on line 50
2. Run `flutter analyze` — must pass with 0 errors
3. Visually test on at least one platform (macOS or Web is fastest)
4. Confirm the bottom sheet background color matches the app's dark theme
5. Verify no regressions in print options functionality

**Do not**:
- Refactor any other part of the print options widget
- Change any other colors or styles
- Add new color constants
- Modify the internal widget tree

This is a surgical fix — one line, one problem, one solution.

---

**Status**: Ready for implementation  
**Blocked by**: None  
**Next Phase**: Engineer implementation
