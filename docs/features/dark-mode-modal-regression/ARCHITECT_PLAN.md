# ARCHITECT PLAN — Dark Mode Modal Regression

## 1. Feature Slug
`bug/dark-mode-modal-regression`

## 2. Problem Summary

After the recent deploy that included light mode visibility fixes (feature/light-mode-visibility-fixes), several bottom sheets and modals now appear in light mode when the app is set to dark mode. The affected screens are:

1. **Add/Edit event bottom sheet** (lib/features/events/widgets/event_editor_drawer.dart)
2. **Edit Gig screen/sheet** (uses EventEditorDrawer)
3. **Schedule Rehearsal screen/sheet** (uses EventEditorDrawer)
4. **Block Out screen/sheet** (lib/features/calendar/widgets/add_block_out_drawer.dart)
5. **Delete Setlist confirmation modal** (lib/features/setlists/setlist_detail_screen.dart)
6. **Subscribe to Calendar Feed modal** (lib/features/calendar/widgets/calendar_subscription_dialog.dart)

## 3. Root Cause — Per Widget Analysis

### EventEditorDrawer (Add/Edit Event, Gig, Rehearsal)
**File:** `lib/features/events/widgets/event_editor_drawer.dart`  
**Line:** 1748  
**Root Cause:** **Cause A — Hardcoded light color (HIGH CONFIDENCE)**

**Evidence:**
```dart
return Container(
  decoration: BoxDecoration(
    color: const Color(0xFFD1D5DB),  // Gray-300 - hardcoded light color
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(20),
      topRight: Radius.circular(20),
    ),
  ),
```

This hardcoded light gray `Color(0xFFD1D5DB)` is always applied regardless of theme. This bug pre-existed the light mode fix but only became visible when users tested in dark mode after the light mode work.

**Fix:** Replace with `context.colors.surface` to respect current theme.

---

### Calendar Subscription Dialog
**File:** `lib/features/calendar/widgets/calendar_subscription_dialog.dart`  
**Line:** 64  
**Root Cause:** **Cause A — Hardcoded light color (HIGH CONFIDENCE)**

**Evidence:**
```dart
return Dialog(
  backgroundColor: const Color(0xFFD1D5DB),  // Gray-300 - hardcoded light color
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Spacing.cardRadius),
  ),
```

Same hardcoded light gray `Color(0xFFD1D5DB)` as EventEditorDrawer. Always renders in light mode regardless of theme.

**Fix:** Replace with `context.colors.surface` to respect current theme.

---

### Block Out Drawer
**File:** `lib/features/calendar/widgets/add_block_out_drawer.dart`  
**Line:** 427  
**Root Cause:** **No issue — Uses theme colors correctly (HIGH CONFIDENCE)**

**Evidence:**
```dart
decoration: BoxDecoration(
  color: context.colors.surface,
  borderRadius: BorderRadius.only(
    topLeft: Radius.circular(20),
    topRight: Radius.circular(20),
  ),
),
```

This widget correctly uses `context.colors.surface` which adapts to theme. No fix needed.

**Status:** FALSE POSITIVE — Not affected by regression.

---

### Delete Setlist Modal
**File:** `lib/features/setlists/setlist_detail_screen.dart`  
**Line:** 1165  
**Root Cause:** **No issue — Uses theme colors correctly (HIGH CONFIDENCE)**

**Evidence:**
```dart
builder: (context) => AlertDialog(
  backgroundColor: context.colors.surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Spacing.cardRadius),
  ),
```

This widget correctly uses `context.colors.surface` which adapts to theme. No fix needed.

**Status:** FALSE POSITIVE — Not affected by regression.

---

### Delete Song Dialog
**File:** `lib/features/setlists/setlist_detail_screen.dart`  
**Line:** 2687  
**Root Cause:** **No issue — Uses theme colors correctly (HIGH CONFIDENCE)**

**Evidence:**
```dart
class _DeleteSongDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
      ),
```

This widget correctly uses `context.colors.surface` which adapts to theme. No fix needed.

**Status:** FALSE POSITIVE — Not affected by regression.

---

## 4. Reference Docs Consulted

- **Source files:**
  - `lib/features/events/widgets/event_editor_drawer.dart` (lines 1-1900)
  - `lib/features/events/widgets/event_form_fields.dart` (lines 1-1000)
  - `lib/features/calendar/widgets/calendar_subscription_dialog.dart` (lines 1-1000)
  - `lib/features/calendar/widgets/add_block_out_drawer.dart` (lines 1-1000)
  - `lib/features/setlists/setlist_detail_screen.dart` (lines 260-300, 1155-1200, 2677-2750)

- **Theme configuration:**
  - `lib/app/theme/brand_colors.dart` (lines 1-150)
  - `lib/app/theme/app_theme.dart` (lines 1-400)
  - `lib/shared/widgets/glass_surface.dart` (lines 1-200)
  - `lib/components/ui/frosted_glass_bar.dart` (lines 1-200)

- **Git history:**
  - Commit `f95d637` — "chore: bump build version"
  - Commit `7c32cb5` — "chore(ui): update app shell styling"

## 5. Existing System Analysis

### Current Color Source Per Affected Widget

| Widget | File | Line | Current Color Source | Should Use |
|--------|------|------|---------------------|------------|
| EventEditorDrawer | event_editor_drawer.dart | 1748 | `const Color(0xFFD1D5DB)` | `context.colors.surface` |
| CalendarSubscriptionDialog | calendar_subscription_dialog.dart | 64 | `const Color(0xFFD1D5DB)` | `context.colors.surface` |
| BlockOutDrawer | add_block_out_drawer.dart | 427 | `context.colors.surface` | ✓ Correct |
| Delete Setlist Modal | setlist_detail_screen.dart | 1165 | `context.colors.surface` | ✓ Correct |
| Delete Song Dialog | setlist_detail_screen.dart | 2687 | `context.colors.surface` | ✓ Correct |

### Theme System (No Changes Needed)

The theme system is working correctly:
- `BrandColors.dark.surface = Color(0xFF18181B)` — Correct dark zinc color
- `BrandColors.light.surface = Color(0xFFFAFAFA)` — Correct light color
- `context.colors.surface` correctly returns theme-appropriate color based on brightness

The issue is NOT with the theme system — it's with individual widgets hardcoding colors instead of using theme tokens.

## 6. Proposed Solution

### Fix 1: EventEditorDrawer Background Color
**File:** `lib/features/events/widgets/event_editor_drawer.dart`  
**Line:** 1748

**Before:**
```dart
decoration: BoxDecoration(
  color: const Color(0xFFD1D5DB),
  borderRadius: BorderRadius.only(
    topLeft: Radius.circular(20),
    topRight: Radius.circular(20),
  ),
),
```

**After:**
```dart
decoration: BoxDecoration(
  color: context.colors.surface,
  borderRadius: BorderRadius.only(
    topLeft: Radius.circular(20),
    topRight: Radius.circular(20),
  ),
),
```

**Rationale:** Use theme-aware surface color token instead of hardcoded gray-300. Automatically adapts to dark mode (0xFF18181B) and light mode (0xFFFAFAFA).

---

### Fix 2: Calendar Subscription Dialog Background Color
**File:** `lib/features/calendar/widgets/calendar_subscription_dialog.dart`  
**Line:** 64

**Before:**
```dart
return Dialog(
  backgroundColor: const Color(0xFFD1D5DB),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Spacing.cardRadius),
  ),
```

**After:**
```dart
return Dialog(
  backgroundColor: context.colors.surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Spacing.cardRadius),
  ),
```

**Rationale:** Use theme-aware surface color token instead of hardcoded gray-300. Automatically adapts to dark mode (0xFF18181B) and light mode (0xFFFAFAFA).

---

## 7. Database Impact

**None.** This is a pure UI fix with no database schema, query, or RLS policy changes.

## 8. Flutter Architecture Changes

**Scope:** Widget-level only. No changes to theme system, state management, or app architecture.

**Changes:**
- **EventEditorDrawer:** Replace hardcoded color with `context.colors.surface`
- **CalendarSubscriptionDialog:** Replace hardcoded color with `context.colors.surface`

**No changes to:**
- `brand_colors.dart` — Theme tokens remain stable
- `app_theme.dart` — Theme configuration remains stable
- `glass_surface.dart` — Glass effects remain stable
- `frosted_glass_bar.dart` — Frosted glass effects remain stable
- State management (Riverpod providers)
- Routing or navigation
- Any other files

## 9. Files to Create

**None.** This is a pure fix to existing files.

## 10. Files to Modify

1. `lib/features/events/widgets/event_editor_drawer.dart` — Line 1748 (1 change)
2. `lib/features/calendar/widgets/calendar_subscription_dialog.dart` — Line 64 (1 change)

**Total changes:** 2 files, 2 lines modified

## 11. Files Off-Limits

The following files are **strictly off-limits** and must NOT be modified:

- `lib/app/theme/brand_colors.dart` — Theme token definitions are stable
- `lib/app/theme/app_theme.dart` — Theme configuration is stable
- `lib/shared/widgets/glass_surface.dart` — Recent light mode fixes are deployed and stable
- `lib/components/ui/frosted_glass_bar.dart` — Recent light mode fixes are deployed and stable
- `lib/main.dart` — App initialization
- `supabase/` — Backend code
- Any migration files
- Any test files (unless broken by the fix)

## 12. System Impact Map

```
┌─────────────────────────────────────────────────────────────────┐
│ IMPACT ANALYSIS                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ 🔴 AFFECTED: EventEditorDrawer                                  │
│    • Add Event (all types: Gig, Rehearsal, Block Out)          │
│    • Edit Gig                                                   │
│    • Edit Rehearsal                                             │
│    • Edit Block Out                                             │
│    • Used across: Calendar, Dashboard, Gigs, Rehearsals         │
│                                                                 │
│ 🔴 AFFECTED: Calendar Subscription Dialog                       │
│    • Accessed from: Calendar screen (top-right menu)            │
│    • Modal showing iCal feed URL                                │
│                                                                 │
│ ✅ NO IMPACT: Block Out Drawer                                  │
│    • Already uses context.colors.surface correctly              │
│                                                                 │
│ ✅ NO IMPACT: Delete Setlist Modal                              │
│    • Already uses context.colors.surface correctly              │
│                                                                 │
│ ✅ NO IMPACT: Delete Song Dialog                                │
│    • Already uses context.colors.surface correctly              │
│                                                                 │
│ ✅ NO IMPACT: Theme System                                      │
│    • brand_colors.dart — Stable                                 │
│    • app_theme.dart — Stable                                    │
│    • glass_surface.dart — Stable                                │
│    • frosted_glass_bar.dart — Stable                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 13. Regression Risk

**Risk Level:** LOW

**Rationale:**
1. **Minimal surface area:** Only 2 files, 2 lines changed
2. **Well-understood pattern:** Replacing hardcoded color with theme token is a standard fix
3. **Theme system stable:** `context.colors.surface` is widely used and proven
4. **No architectural changes:** Pure cosmetic fix at widget level
5. **No business logic impact:** Zero changes to event creation, editing, deletion, or persistence
6. **No database impact:** Zero schema, query, or RLS changes

**Known risks:**
- **None identified.** The fix is straightforward and isolated.

**Mitigation:**
- Visual QA in both dark and light modes before commit
- Verify no theme inheritance issues in nested contexts

## 14. Engineer Task Breakdown

### Task 1: Fix EventEditorDrawer Background Color
**File:** `lib/features/events/widgets/event_editor_drawer.dart`  
**Estimated Time:** 2 minutes

**Action:**
1. Open `lib/features/events/widgets/event_editor_drawer.dart`
2. Navigate to line 1748 (inside `Widget build(BuildContext context)`)
3. Locate the `Container` with `decoration: BoxDecoration(color: const Color(0xFFD1D5DB), ...)`
4. Replace `color: const Color(0xFFD1D5DB),` with `color: context.colors.surface,`
5. Save file

**Verification:**
- File compiles without errors
- Flutter analyzer shows no new warnings

---

### Task 2: Fix Calendar Subscription Dialog Background Color
**File:** `lib/features/calendar/widgets/calendar_subscription_dialog.dart`  
**Estimated Time:** 2 minutes

**Action:**
1. Open `lib/features/calendar/widgets/calendar_subscription_dialog.dart`
2. Navigate to line 64 (inside `Widget build(BuildContext context)` of `_CalendarSubscriptionDialogState`)
3. Locate the `Dialog` with `backgroundColor: const Color(0xFFD1D5DB),`
4. Replace `backgroundColor: const Color(0xFFD1D5DB),` with `backgroundColor: context.colors.surface,`
5. Save file

**Verification:**
- File compiles without errors
- Flutter analyzer shows no new warnings

---

**Total Estimated Time:** 4 minutes implementation + QA walkthrough

## 15. Verification Plan

### Tier 1: Code Review Checklist
- [ ] EventEditorDrawer line 1748 uses `context.colors.surface` (no hardcoded color)
- [ ] CalendarSubscriptionDialog line 64 uses `context.colors.surface` (no hardcoded color)
- [ ] No accidental changes to other files
- [ ] No new `flutter analyze` warnings in modified files
- [ ] No trailing whitespace or formatting issues

### Tier 2: Manual Dark Mode Walkthrough

**Platform:** iOS, Android, macOS, or Web (any platform running in dark mode)

**Test Cases:**

1. **Add Event — Rehearsal**
   - Open Calendar screen
   - Tap "+ Add Event"
   - Verify bottom sheet has **dark background** (zinc-800 #18181B)
   - Verify text is **light** (zinc-50 #FAFAFA)
   - Cancel and close

2. **Add Event — Gig**
   - Open Calendar screen
   - Tap "+ Add Event"
   - Switch to "Gig" tab
   - Verify bottom sheet has **dark background** (zinc-800 #18181B)
   - Verify text is **light** (zinc-50 #FAFAFA)
   - Cancel and close

3. **Edit Gig**
   - Open Dashboard or Calendar
   - Tap on an existing gig
   - Verify bottom sheet has **dark background** (zinc-800 #18181B)
   - Verify text is **light** (zinc-50 #FAFAFA)
   - Cancel and close

4. **Schedule Rehearsal**
   - Open Calendar screen
   - Tap "+ Add Event"
   - Select "Rehearsal"
   - Verify bottom sheet has **dark background** (zinc-800 #18181B)
   - Verify text is **light** (zinc-50 #FAFAFA)
   - Cancel and close

5. **Calendar Subscription Dialog**
   - Open Calendar screen
   - Tap the "Subscribe" or menu icon (top-right)
   - Select "Subscribe to Calendar Feed"
   - Verify dialog has **dark background** (zinc-800 #18181B)
   - Verify text is **light** (zinc-50 #FAFAFA)
   - Close dialog

### Tier 3: Manual Light Mode Walkthrough

**Platform:** iOS, Android, macOS, or Web (any platform running in light mode)

**Test Cases:**

1. **Add Event — Rehearsal**
   - Open Calendar screen
   - Tap "+ Add Event"
   - Verify bottom sheet has **light background** (zinc-50 #FAFAFA)
   - Verify text is **dark** (slate-950 #020617)
   - Cancel and close

2. **Add Event — Gig**
   - Open Calendar screen
   - Tap "+ Add Event"
   - Switch to "Gig" tab
   - Verify bottom sheet has **light background** (zinc-50 #FAFAFA)
   - Verify text is **dark** (slate-950 #020617)
   - Cancel and close

3. **Edit Gig**
   - Open Dashboard or Calendar
   - Tap on an existing gig
   - Verify bottom sheet has **light background** (zinc-50 #FAFAFA)
   - Verify text is **dark** (slate-950 #020617)
   - Cancel and close

4. **Schedule Rehearsal**
   - Open Calendar screen
   - Tap "+ Add Event"
   - Select "Rehearsal"
   - Verify bottom sheet has **light background** (zinc-50 #FAFAFA)
   - Verify text is **dark** (slate-950 #020617)
   - Cancel and close

5. **Calendar Subscription Dialog**
   - Open Calendar screen
   - Tap the "Subscribe" or menu icon (top-right)
   - Select "Subscribe to Calendar Feed"
   - Verify dialog has **light background** (zinc-50 #FAFAFA)
   - Verify text is **dark** (slate-950 #020617)
   - Close dialog

### Pass Criteria
- All 5 dark mode test cases show dark backgrounds and light text
- All 5 light mode test cases show light backgrounds and dark text
- No visual regressions in other screens
- No crashes or errors

## 16. QA Regression Areas

### Primary Areas (MUST TEST)
1. **Event Creation/Editing (Dark Mode)**
   - Add Event bottom sheet (all types)
   - Edit Gig screen
   - Edit Rehearsal screen
   - Block Out screen

2. **Event Creation/Editing (Light Mode)**
   - Add Event bottom sheet (all types)
   - Edit Gig screen
   - Edit Rehearsal screen
   - Block Out screen

3. **Calendar Subscription (Dark Mode)**
   - Subscribe to Calendar Feed dialog

4. **Calendar Subscription (Light Mode)**
   - Subscribe to Calendar Feed dialog

### Secondary Areas (SHOULD TEST if time allows)
5. **Other Modals (Dark Mode)**
   - Delete Setlist confirmation
   - Delete Song confirmation
   - Duplicate Setlist prompt
   - Any other AlertDialogs

6. **Other Modals (Light Mode)**
   - Delete Setlist confirmation
   - Delete Song confirmation
   - Duplicate Setlist prompt
   - Any other AlertDialogs

7. **Theme Switching**
   - Switch from Dark → Light → Dark
   - Verify modals render correctly after each switch

## 17. Out of Scope

The following are explicitly OUT OF SCOPE for this fix:

1. **Light mode improvements** — This fix only addresses dark mode regression. Light mode visibility is already addressed in the previous deploy.

2. **Theme system refactoring** — No changes to `brand_colors.dart`, `app_theme.dart`, or design tokens.

3. **Glass surface/frosted glass changes** — No changes to `glass_surface.dart` or `frosted_glass_bar.dart`. These components are stable.

4. **Opacity/blur tuning** — No changes to blur sigma, tint opacity, or edge fade strength values.

5. **Other hardcoded colors** — This fix only addresses the two widgets explicitly reported in the bug. If other widgets have similar issues, they should be filed as separate bugs.

6. **Performance optimization** — No changes to blur performance, BackdropFilter usage, or rendering efficiency.

7. **Accessibility** — No changes to contrast ratios, font sizes, or screen reader support.

8. **New features** — This is a pure bug fix. No new functionality is added.

---

## Approval Status

**Status:** AWAITING APPROVAL  
**Created:** 2026-05-06  
**Architect:** AI Architect Agent  
**Next Step:** Manager Review → Engineer Implementation → QA Validation → Commit

---

## Change Log

| Date | Change | Rationale |
|------|--------|-----------|
| 2026-05-06 | Initial plan created | Root cause analysis complete |

---

**END OF ARCHITECT PLAN**
