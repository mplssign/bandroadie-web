# ARCHITECT PLAN — bug/setlist-modals-dark-mode

## Feature Slug

`bug/setlist-modals-dark-mode`

## Problem Summary

The "Add to Setlist" bottom sheet (opened from Catalog Select mode) and its "Create New Setlist" view render in light mode unconditionally, regardless of the app's active theme. This creates a jarring visual inconsistency — the rest of the app respects dark mode, but these two surfaces do not.

## Root Cause

**Confidence Level:** HIGH (confirmed via direct code inspection)

**Failure Mode:** Hardcoded colors (#1 from investigation)

`lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` line 225 uses a hardcoded light gray color literal:

```dart
decoration: BoxDecoration(
  color: const Color(0xFFD1D5DB),  // Tailwind gray-300
  borderRadius: BorderRadius.circular(Spacing.cardRadius),
),
```

This bypasses the theme system entirely. The correct approach is to use `context.colors.surface`, which resolves to:

- Dark mode: `0xFF18181B` (zinc-900)
- Light mode: `0xFFFAFAFA` (zinc-50)

**Note:** "Create New Setlist" is not a separate dialog. It's a different view (`_isCreatingNew` state toggle) within the same `_SetlistPickerSheet` widget. Both views share the same root container, so one fix resolves both issues.

**Related Issue (not in scope of reported bug):**
`lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart` line 415 has the identical hardcoded color in a delete confirmation `AlertDialog`. This plan includes the fix for consistency, but it's a separate entry point (tuning picker) not mentioned in the bug report.

## Reference Docs Consulted

No dedicated theming reference documentation exists under `docs/reference/`. The following files were inspected directly:

- `lib/app/theme/design_tokens.dart` — Defines `AppColors`, `Spacing`, `AppTextStyles`
- `lib/app/theme/brand_colors.dart` — Defines `BrandColors` theme extension with dark/light variants and `context.colors` accessor
- `lib/app/theme/app_theme.dart` — Wires `BrandColors` into Material 3 `ThemeData`

The theme system is correctly implemented. The bug is isolated to two widgets that bypass it.

## Existing System Analysis

**Current Behavior:**

1. User opens Catalog detail screen → taps "Select" → selects songs → taps "Add X to Setlist"
2. `showSetlistPickerBottomSheet()` is called (line 75 of `setlist_picker_bottom_sheet.dart`)
3. `showModalBottomSheet()` opens with `backgroundColor: Colors.transparent` (correct)
4. Inside, `_SetlistPickerSheet` builds a `Container` with hardcoded `color: const Color(0xFFD1D5DB)` (line 225)
5. This color is light gray regardless of theme
6. When user taps "Create New Setlist", `_isCreatingNew` toggles to true, showing a text field form in the same container
7. Both views (list of setlists and create new form) share the same hardcoded background

**Data Flow:**

- No data flow issue — purely a presentation layer bug
- The widget correctly accesses theme via `context.colors` in other places (borders, text colors)
- Only the main container background bypasses the theme system

## Proposed Solution

Replace hardcoded color literals with theme-aware references:

1. **Primary fix** — `setlist_picker_bottom_sheet.dart` line 225:

   ```dart
   // Before:
   color: const Color(0xFFD1D5DB),

   // After:
   color: context.colors.surface,
   ```

2. **Related fix** — `tuning_picker_bottom_sheet.dart` line 415:

   ```dart
   // Before:
   backgroundColor: const Color(0xFFD1D5DB),

   // After:
   backgroundColor: context.colors.surface,
   ```

Both changes are single-line replacements. No logic, state management, or layout changes required.

## Database Impact

**Not applicable** — UI-only change. No migrations, RLS policies, RPC functions, or triggers affected.

## Flutter Architecture Changes

**Affected:**

- `SetlistPickerBottomSheet` widget (presentation only)
- `TuningPickerBottomSheet` delete confirmation dialog (presentation only)

**Not Affected:**

- State management (no Riverpod providers modified)
- Repositories (no data access changes)
- Controllers (no business logic changes)
- Theme system (already correctly implemented)

## Files to Create

None

## Files to Modify

| File                                                             | Change                                                                    |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` | Line 225: Replace `const Color(0xFFD1D5DB)` with `context.colors.surface` |
| `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart`  | Line 415: Replace `const Color(0xFFD1D5DB)` with `context.colors.surface` |

## Files Off-Limits

| File                                                  | Reason                                                                                                           |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                       | Init order must not change (Guardrails §1)                                                                       |
| `lib/app/theme/design_tokens.dart`                    | Theme system already correct                                                                                     |
| `lib/app/theme/brand_colors.dart`                     | Theme extension already correct                                                                                  |
| `lib/app/theme/app_theme.dart`                        | ThemeData configuration already correct                                                                          |
| `lib/features/setlists/widgets/setlists_app_bar.dart` | Hardcoded light gray (line 153) is **intentional** — provides contrast for band name overlaid on dark band image |

## System Impact Map

| System                                 | Impact                                                       |
| -------------------------------------- | ------------------------------------------------------------ |
| Gigs                                   | unaffected                                                   |
| Rehearsals                             | unaffected                                                   |
| Setlists / Catalog                     | **affected** (UI only — Select mode bottom sheet appearance) |
| Members / RBAC                         | unaffected                                                   |
| Auth / Session                         | unaffected                                                   |
| Routing                                | unaffected                                                   |
| Notifications                          | unaffected                                                   |
| Platform (iOS / Android / Web / macOS) | **affected** (all — shared Flutter theming)                  |

## Regression Risk

**Level:** LOW

**Rationale:**

- Two single-line changes
- No logic modifications
- No state management changes
- Theme system validates correct color resolution via `BrandColors` extension
- Isolated to two bottom sheet widgets
- No dependencies on other features
- Change is idempotent — if re-run, produces identical result

**Risk Factors:**

- None identified

## Engineer Task Breakdown

Execute in order. Do not skip. Do not reorder.

### Task 1 — Fix setlist picker bottom sheet

Edit `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`:

- Locate line 225: `color: const Color(0xFFD1D5DB),`
- Replace with: `color: context.colors.surface,`
- Verify no other hardcoded color literals in the file (except intentional badge colors)

### Task 2 — Fix tuning picker delete dialog

Edit `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart`:

- Locate line 415: `backgroundColor: const Color(0xFFD1D5DB),`
- Replace with: `backgroundColor: context.colors.surface,`
- Verify no other hardcoded color literals in the file

### Task 3 — Validate changes

Run:

```bash
flutter analyze
```

Confirm 0 errors, 0 warnings related to modified files.

### Task 4 — Visual verification (manual)

1. Set device to dark mode
2. Open Catalog detail screen
3. Tap "Select"
4. Select one or more songs
5. Tap "Add X to Setlist"
6. **Verify:** Bottom sheet background is dark (`0xFF18181B`), not light gray
7. Tap "Create New Setlist"
8. **Verify:** Create form background is dark, matching the app theme
9. Open any song card → tap tuning field → open tuning picker → select custom tuning → tap delete
10. **Verify:** Delete confirmation dialog background is dark

## Verification Plan

### Tier 1 — Pre-deployment

Not applicable — no database changes.

### Tier 2 — Post-deployment

Not applicable — no database changes.

**Manual UI Verification (required):**

1. Confirm `flutter analyze` passes with 0 errors
2. Hot reload on macOS and iOS simulators
3. Verify bottom sheet backgrounds respect dark mode
4. Toggle system theme → verify bottom sheets adapt
5. Verify text remains legible (sufficient contrast)

## QA Regression Areas

QA must specifically test:

### Primary Validation

1. **Catalog Select mode flow (dark mode):**
   - Open Catalog → Select songs → "Add to Setlist"
   - Confirm bottom sheet renders with dark background
   - Confirm "Create New Setlist" view also renders with dark background
   - Confirm text/icons have correct contrast

2. **Catalog Select mode flow (light mode):**
   - Same flow as above
   - Confirm bottom sheet renders with light background
   - Confirm no visual regressions (text legibility, spacing)

3. **Tuning picker delete dialog (dark mode):**
   - Open any song card → tap tuning → open tuning picker
   - Select custom tuning → tap delete icon
   - Confirm delete confirmation dialog renders with dark background

4. **Tuning picker delete dialog (light mode):**
   - Same flow as above
   - Confirm dialog renders with light background

### Regression Checks

1. **Other bottom sheets:**
   - Song details bottom sheet (tap any song card)
   - Key picker bottom sheet (tap key field in song details)
   - Verify no visual regressions (these already use `context.colors.surface`)

2. **Theme toggle:**
   - Open Catalog → enter Select mode → open "Add to Setlist" drawer → leave open
   - Switch system theme (Settings → Display → Dark/Light)
   - Return to app → verify drawer background adapts (hot reload may be required)

3. **Cross-platform:**
   - Repeat primary validation on iOS, Android, Web, macOS
   - Confirm consistent appearance across platforms

## Rollout / Migration Strategy

Not applicable — no database migration, no staged rollout required. Deploy as standard feature branch merge.

## Out of Scope

- Other bottom sheets (already correctly themed)
- Light mode improvements (app is dark-mode-first, light mode exists but is not primary)
- Refactoring the bottom sheet widget (no architectural changes per Guardrails §7)
- Creating theming reference documentation (documentation task, not part of this bug fix)
- Fixing `setlists_app_bar.dart` line 153 (intentional light gray for image overlay contrast — not a bug)
