# ARCHITECT_PLAN.md

## Feature: calendar-forui-consolidation

**Feature Identifier:** `feature/calendar-forui-consolidation`  
**Type:** feature  
**Branch Name:** `feature/calendar-forui-consolidation`

---

## Summary

Migrate `view_block_out_drawer.dart` from raw Flutter `showModalBottomSheet` to the app's Forui-wrapped `showAppBottomSheet` facade for consistency with all other calendar bottom sheets. This is a visual/structural consolidation to complete the calendar feature's Forui adoption; no functional, database, RLS, or RPC changes are involved.

---

## Root Cause Analysis

### Problem Confirmed in Code

**File:** `lib/features/calendar/widgets/view_block_out_drawer.dart`  
**Lines:** 25–37  
**Issue:** The `show()` static method calls raw Flutter `showModalBottomSheet`:

```dart
static Future<void> show(
  BuildContext context, {
  required BlockOutSpan existingBlockOut,
  required bool canEdit,
  required VoidCallback onEdit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ViewBlockOutDrawer(
      existingBlockOut: existingBlockOut,
      canEdit: canEdit,
      onEdit: onEdit,
    ),
  );
}
```

**Expected pattern (from sibling files):**

`lib/features/calendar/widgets/day_detail_bottom_sheet.dart` (lines 39–49) and `lib/features/calendar/widgets/add_block_out_drawer.dart` (lines 89–109) both use `showAppBottomSheet` from `lib/components/ui/app_bottom_sheet.dart`, which wraps Forui's `showFSheet` with app-level defaults.

**Why this matters:**

All other bottom-sheet-style widgets in the calendar feature (3 files: `day_detail_bottom_sheet.dart`, `add_block_out_drawer.dart`, `calendar_subscription_dialog.dart`) present via `showAppBottomSheet`. The house pattern (17 files app-wide) is that each sheet hand-builds its own rounded-container + drag-handle shell because Forui preview's `backgroundColor`/`shape` params are no-ops. This is expected and not a defect. The gap is that `view_block_out_drawer.dart` alone bypasses the facade entirely, making it the only calendar bottom sheet not on the Forui sheet API.

This is the same bug class as previously fixed in `az_search_field.dart` (search field decoration) and contact/venue form label gaps — a facade swap that didn't propagate to one sibling file during initial Forui adoption.

---

### Secondary Item: calendar_grid.dart Hardcoded Colors

**File:** `lib/features/calendar/widgets/calendar_grid.dart`  
**Finding:** One instance of `Colors.white` found on line 544:

```dart
color: isToday ? Colors.white : context.colors.textPrimary,
```

**Analysis:**

This is white text displayed on `AppColors.primary` (rose #FF2056) background when the date is today. This is an **intentional accessibility pairing** to ensure sufficient contrast between the primary rose background and foreground text. No semantic "text on primary" token exists in `BrandColors` or `design_tokens.dart`. Creating one would require:

1. Adding a new color to `BrandColors` (both light and dark modes)
2. Verifying accessibility contrast ratios in both modes
3. Updating all callsites that currently use white-on-primary

This is **not trivial and is not risk-free**. The current `Colors.white` is Figma-aligned for this specific accessibility pairing.

**Decision:** Do not modify `calendar_grid.dart`. The hardcoded color is intentional and correctly implements the design spec.

**Note:** `CalendarColors` class (lines 24–37) contains Figma-pinned rehearsal/gig/block-out/potential marker colors sourced from `MarkerColors`. These are explicitly excluded per the feature input and were not considered for modification.

---

## Files to Modify

| File                                                       | Reason                                                          | Lines to Change                |
| ---------------------------------------------------------- | --------------------------------------------------------------- | ------------------------------ |
| `lib/features/calendar/widgets/view_block_out_drawer.dart` | Replace `showModalBottomSheet` with `showAppBottomSheet` facade | 25–37 (static `show()` method) |

**Total files modified:** 1

---

## Files Explicitly Out of Scope

All other calendar feature files (19 total) are out of scope and must NOT be modified:

**Screens & Controllers:**

- `calendar_screen.dart` — screen entry point (audited, compliant)
- `calendar_tab_content.dart` — tab content wrapper (audited, compliant)
- `calendar_controller.dart` — Riverpod state management (audited, compliant)
- `one_calendar_settings_screen.dart` — settings UI (audited, uses `AppCheckbox`, `AppIconButton`)

**Repositories & Services:**

- `block_out_repository.dart` — Supabase data access (no UI changes)
- `one_calendar_preferences_repository.dart` — preference persistence (no UI changes)
- `calendar_subscription_service.dart` — subscription logic (no UI changes)
- `auto_conflict_blocking_service.dart` — conflict detection (no UI changes)

**Widgets:**

- `calendar_app_bar.dart` — app bar with inline icon tap targets (audited, `GestureDetector` is intentional — `AppIconButton` unsuitable for inline icons)
- `calendar_bottom_nav_bar.dart` — bottom nav (audited, compliant)
- `calendar_event_card.dart` — event card (audited, uses `AppCard`)
- `calendar_grid.dart` — month grid with bespoke swipe physics (audited, no Forui widget maps onto it, uses `context.colors.*` and `AppColors.primary`, hardcoded `Colors.white` is intentional accessibility pairing — see Secondary Item analysis above)
- `day_detail_bottom_sheet.dart` — day detail sheet (audited, already uses `showAppBottomSheet`, reference pattern for this fix)
- `add_block_out_drawer.dart` — add/edit block out sheet (audited, already uses `showAppBottomSheet`, reference pattern for this fix)
- `calendar_subscription_dialog.dart` — subscription dialog (audited, already uses `showAppBottomSheet`)

**Shared/Markers:**

- `calendar_markers.dart` — event marker helpers (no UI changes)

**Models:**

- `models/calendar_event.dart` — CalendarEvent, Gig, Rehearsal, BlockOutSpan models (no UI changes)
- `models/one_calendar_preferences.dart` — OneCalendarPreferences model (no UI changes)

**Rationale:** These files were audited and found either already Forui-compliant or intentionally outside the Forui-widget pattern (e.g., `calendar_grid.dart`'s bespoke month grid, `calendar_app_bar.dart`'s inline icon targets). No changes are needed or permitted for this feature.

---

## Implementation Plan

### Task 1: Update view_block_out_drawer.dart

**What:**  
Replace the `show()` static method's raw `showModalBottomSheet` call with `showAppBottomSheet` from `lib/components/ui/app_bottom_sheet.dart`, matching the pattern used by sibling calendar drawers (`day_detail_bottom_sheet.dart`, `add_block_out_drawer.dart`).

**How:**

1. **Import the facade:**  
   Add at top of file:

   ```dart
   import '../../../components/ui/app_bottom_sheet.dart';
   ```

2. **Replace the static method (lines 25–37):**

   **Before:**

   ```dart
   static Future<void> show(
     BuildContext context, {
     required BlockOutSpan existingBlockOut,
     required bool canEdit,
     required VoidCallback onEdit,
   }) {
     return showModalBottomSheet<void>(
       context: context,
       isScrollControlled: true,
       backgroundColor: Colors.transparent,
       builder: (_) => ViewBlockOutDrawer(
         existingBlockOut: existingBlockOut,
         canEdit: canEdit,
         onEdit: onEdit,
       ),
     );
   }
   ```

   **After:**

   ```dart
   static Future<void> show(
     BuildContext context, {
     required BlockOutSpan existingBlockOut,
     required bool canEdit,
     required VoidCallback onEdit,
   }) {
     return showAppBottomSheet<void>(
       context: context,
       isScrollControlled: true,
       backgroundColor: Colors.transparent,
       builder: (_) => ViewBlockOutDrawer(
         existingBlockOut: existingBlockOut,
         canEdit: canEdit,
         onEdit: onEdit,
       ),
     );
   }
   ```

   **Changes:**
   - Line 29: `showModalBottomSheet` → `showAppBottomSheet`
   - Keep all parameters identical (no behavioral change)

3. **Why `backgroundColor` and `isScrollControlled` are kept:**  
   Per `app_bottom_sheet.dart` inline docs: `backgroundColor`, `shape`, and `isScrollControlled` are no-ops in Forui preview, but keeping them maintains parity with other sheets and prepares for future Forui GA when these params may become functional. All other calendar sheets pass these same params.

**Lines modified:** 25–37 (13 lines total in the `show()` static method)

**Verification points (for QA):**

- Visual: Drag handle, rounded top corners, Done/Edit footer, detail rows must look identical to current behavior
- Functional: Tapping Done dismisses the sheet, tapping Edit dismisses and triggers edit flow
- No regressions to view flow when tapping a block-out from the calendar grid

---

## Impact Assessment

| Area                  | Impact | Notes                                                                         |
| --------------------- | ------ | ----------------------------------------------------------------------------- |
| **Database**          | None   | No schema, query, or RPC changes                                              |
| **RLS Policies**      | None   | No permission or security changes                                             |
| **RPC Functions**     | None   | No server-side logic changes                                                  |
| **Authentication**    | None   | No auth flow changes                                                          |
| **State Management**  | None   | No provider, controller, or repository changes                                |
| **Deep Linking**      | None   | No routing or navigation changes                                              |
| **Platform-Specific** | None   | Change applies uniformly to all platforms (Web, iOS, Android, macOS)          |
| **Dependencies**      | None   | No new dependencies; `showAppBottomSheet` already exists and is used app-wide |

**Risk Level:** **Low**

This is a facade swap with no functional changes. The visual presentation already matches the app pattern (rounded container, drag handle, colored background). The only change is which API presents the sheet — from raw Flutter `showModalBottomSheet` to the Forui-wrapped `showAppBottomSheet` that all other calendar sheets already use.

---

## Testing Strategy

**QA Validation Focus:**

1. **Visual Regression:**
   - Drag handle, rounded top corners, `context.colors.surface` background must appear identical
   - Done/Edit button layout and styling must be unchanged

2. **Functional Regression:**
   - Tapping Done dismisses the sheet correctly
   - Tapping Edit (when `canEdit` is true) dismisses the sheet and triggers the edit flow (opens `add_block_out_drawer.dart` in edit mode)
   - Swipe-to-dismiss gesture still works

3. **Integration:**
   - Navigate to calendar, tap a block-out day (purple marker), verify view sheet opens
   - Test with both single-day and multi-day block-outs
   - Verify "Through <end date>" subtitle appears correctly for multi-day spans

4. **Cross-Platform:**
   - Test on Web, iOS, Android, macOS to confirm uniform behavior (sheet presentation, dismissal, animations)

**What NOT to test:**

- Block-out creation/editing logic (unchanged, handled by `add_block_out_drawer.dart`)
- Calendar grid rendering (out of scope)
- Other calendar widgets (out of scope)

---

## Git Strategy

**Branch Name:** `feature/calendar-forui-consolidation`

**Commit Message:**

```
feat(calendar): migrate view_block_out_drawer to showAppBottomSheet facade

Replace raw showModalBottomSheet with showAppBottomSheet in
view_block_out_drawer.dart to match the Forui-wrapped pattern used
by all other calendar bottom sheets (day_detail_bottom_sheet,
add_block_out_drawer, calendar_subscription_dialog).

No visual or functional changes — this is a facade consolidation
to complete the calendar feature's Forui adoption.

Files modified:
- lib/features/calendar/widgets/view_block_out_drawer.dart

Closes #calendar-forui-consolidation
```

**Merge Target:** `main`

---

## Additional Context

**Why this matters:**

The calendar feature was audited for Forui consistency. 17 files app-wide use the `showAppBottomSheet` facade, which wraps Forui's `showFSheet` and provides app-level defaults. `view_block_out_drawer.dart` is the only bottom-sheet-style widget in the calendar feature that bypasses this facade, making it inconsistent with its siblings and the broader app pattern.

**House pattern for bottom sheets:**

All sheets using `showAppBottomSheet` hand-build their own rounded-container + drag-handle shell because Forui preview's `backgroundColor`/`shape` params are currently no-ops. This is expected and documented in `app_bottom_sheet.dart`. The goal of this feature is not to eliminate that pattern but to ensure all sheets use the same underlying Forui API (`showFSheet` via `showAppBottomSheet`), not a mix of Forui and raw Flutter APIs.

**Precedent:**

This is the same bug class as previously fixed in:

- `az_search_field.dart` — search field decoration (migrated from raw `InputDecoration` to Forui `FTextField`)
- Contact/venue form label gaps — form field labels (migrated to consistent Forui form patterns)

In each case, a facade swap or pattern adoption didn't propagate to one sibling file during initial Forui migration. This is the final known gap in the calendar feature.

**Forui preview cycle note:**

As documented in `app_bottom_sheet.dart`, `backgroundColor`, `shape`, `isScrollControlled`, `useSafeArea`, and `barrierColor` params are no-ops in Forui preview. This is why all sheets build their own styled containers. When Forui reaches GA, these params may become functional, at which point a follow-up consolidation pass can remove the manual container shells. For now, the goal is API consistency, not visual simplification.

---

## Engineer Checklist

When implementing this plan:

- [ ] Modify only `lib/features/calendar/widgets/view_block_out_drawer.dart`
- [ ] Do not modify any other calendar files (19 files explicitly out of scope)
- [ ] Do not modify `calendar_grid.dart` (hardcoded `Colors.white` is intentional)
- [ ] Import `app_bottom_sheet.dart` at top of file
- [ ] Replace `showModalBottomSheet` with `showAppBottomSheet` on line 29
- [ ] Keep all parameters unchanged (`context`, `isScrollControlled`, `backgroundColor`, `builder`)
- [ ] Run `flutter analyze` — 0 errors required
- [ ] Verify no visual regressions (drag handle, rounded corners, Done/Edit buttons)
- [ ] Test on Web and macOS minimally (primary development platforms)
- [ ] Generate `git diff` for QA review
- [ ] Produce `ENGINEER_REPORT.md` documenting implementation

---

## Architect Sign-Off

**Root Cause Confirmed:** Yes — `view_block_out_drawer.dart` line 29 calls `showModalBottomSheet` instead of `showAppBottomSheet`, bypassing the Forui facade used by all other calendar bottom sheets.

**Files to Modify:** 1 file explicitly listed with exact lines and changes.

**Files Out of Scope:** 19 calendar files explicitly listed and justified.

**Database/RLS/RPC Impact:** None — this is a UI facade swap with no server-side or data-layer changes.

**Risk Assessment:** Low — facade swap with no functional changes, matching a pattern already validated in 17 other app-wide bottom sheets.

**Plan Status:** **APPROVED**

This plan is complete, unambiguous, and ready for Engineer implementation.

---

**Generated:** 2026-08-16  
**Architect:** GitHub Copilot (Claude Sonnet 4.5)
