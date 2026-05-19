# ARCHITECT PLAN — ConfirmActionDialog Dark Mode Fix

## 1. Feature Slug

`bug/confirm-action-dialog-dark-mode`

## 2. Problem Summary

The shared `ConfirmActionDialog` component (`lib/components/ui/confirm_action_dialog.dart`) has a hardcoded light gray background color (`const Color(0xFFD1D5DB)`) at line 61. This causes the modal to always render in light mode, regardless of whether the app is set to dark mode or light mode.

The issue was reported via the "Delete Setlist?" confirmation dialog, where a screenshot confirmed the modal appeared with a light background even though the app was in dark mode.

## 3. Root Cause

**Confidence Level:** HIGH

**File:** `lib/components/ui/confirm_action_dialog.dart`  
**Line:** 61

**Current Code:**

```dart
@override
Widget build(BuildContext context) {
  return AlertDialog(
    backgroundColor: const Color(0xFFD1D5DB),  // ← HARDCODED LIGHT GRAY
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Spacing.cardRadius),
    ),
```

The color `0xFFD1D5DB` is a light gray (approximately Tailwind's gray-300) that completely ignores Flutter's theme system and the app's `BrandColors` theme extension.

**Why it fails:**

- The `AlertDialog` widget has an explicit `backgroundColor` parameter set to a hardcoded `const Color(0xFFD1D5DB)`
- This color value is compile-time constant and never evaluates the current theme
- Flutter's theme system is correctly configured (`BrandColors.dark.surface = Color(0xFF18181B)`, `BrandColors.light.surface = Color(0xFFFAFAFA)`), but the dialog bypasses it entirely

**Correct Implementation:**

```dart
backgroundColor: context.colors.surface,
```

This uses the `BrandColors` theme extension accessor, which automatically returns:

- `Color(0xFF18181B)` (dark zinc) in dark mode
- `Color(0xFFFAFAFA)` (light zinc) in light mode

## 4. Reference Docs Consulted

- **Source files:**
  - `lib/components/ui/confirm_action_dialog.dart` (lines 1-130)
  - `lib/features/setlists/setlists_screen.dart` (lines 480-520) — call sites
  - `lib/features/setlists/setlists_tab_content.dart` (lines 115-160) — call sites

- **Theme configuration:**
  - `lib/app/theme/brand_colors.dart` (lines 1-80) — theme token definitions
  - Verified `BrandColors.dark.surface = Color(0xFF18181B)`
  - Verified `BrandColors.light.surface = Color(0xFFFAFAFA)`

- **Previous related work:**
  - `docs/features/dark-mode-modal-regression/ARCHITECT_PLAN.md` — fixed `event_editor_drawer.dart` and `calendar_subscription_dialog.dart` for the same hardcoded color issue
  - `docs/features/bug/print-options-dark-mode/ARCHITECT_PLAN.md` — fixed `print_options_bottom_sheet.dart` for the same hardcoded color issue
  - Both prior plans correctly identified and fixed `Color(0xFFD1D5DB)` → theme-aware color

- **Call Site Audit:**
  - All usages of `showConfirmActionDialog` confirmed via grep search
  - 4 total call sites identified (2 in `setlists_screen.dart`, 2 in `setlists_tab_content.dart`)
  - All call sites use the shared component — no inline customization or overrides
  - Fix at component level will automatically resolve all call sites

## 5. Existing System Analysis

### Current Behavior

The `ConfirmActionDialog` is a reusable confirmation modal invoked via the `showConfirmActionDialog` helper function. It is used exclusively for setlist operations in the current codebase.

**Call Sites (4 total):**

1. **Delete Setlist** — `lib/features/setlists/setlists_screen.dart` line 485
   - Context: User long-presses a setlist in the Setlists screen and selects "Delete Setlist"
   - Modal title: "Delete Setlist?"
   - Destructive action (red button)

2. **Duplicate Setlist** — `lib/features/setlists/setlists_screen.dart` line 513
   - Context: User long-presses a setlist in the Setlists screen and selects "Duplicate Setlist"
   - Modal title: "Duplicate Setlist?"
   - Success-colored action (green button)

3. **Delete Setlist** — `lib/features/setlists/setlists_tab_content.dart` line 123
   - Context: User swipes-to-delete a setlist in the Setlists tab
   - Modal title: "Delete Setlist?"
   - Destructive action (red button)

4. **Duplicate Setlist** — `lib/features/setlists/setlists_tab_content.dart` line 149
   - Context: User taps the duplicate icon on a setlist card
   - Modal title: "Duplicate Setlist?"
   - Success-colored action (green button)

**Current Data Flow:**

```
User Action (delete/duplicate setlist)
  → showConfirmActionDialog() invoked
  → AlertDialog with backgroundColor: const Color(0xFFD1D5DB) rendered
  → Modal appears in light mode ALWAYS (bug)
  → User confirms or cancels
  → Action executes or aborts
```

**Observed Problem:**

- In dark mode, the app background is `Color(0xFF09090B)` (near-black)
- The modal renders with `Color(0xFFD1D5DB)` (light gray)
- Text colors adapt correctly to theme (via `context.colors.textPrimary` / `textSecondary`)
- Only the background is wrong

### Why the Previous Plan Missed This

The previous `dark-mode-modal-regression` plan (docs/features/dark-mode-modal-regression/ARCHITECT_PLAN.md) incorrectly classified the "Delete Setlist" modal as a **false positive**. The plan examined line 1165 of `lib/features/setlists/setlist_detail_screen.dart`, which contains an inline `AlertDialog` that correctly uses `context.colors.surface`.

However, that inline dialog is for deleting **songs** from within a setlist detail view. The "Delete Setlist" modal reported by the user is invoked from the **setlists list screen** via the shared `ConfirmActionDialog` component, which was never examined in the previous plan.

**Status of Previous Plan Fixes:**

- ✅ `event_editor_drawer.dart` line 1767 — FIXED (`color: context.colors.surface`)
- ✅ `calendar_subscription_dialog.dart` line 94 — FIXED (`backgroundColor: context.colors.surface`)
- ❌ `ConfirmActionDialog` — NOT ADDRESSED (out of scope of that plan)

This bug is **distinct** from the previous plan and was never fixed.

## 6. Proposed Solution

**Change exactly 1 line in exactly 1 file.**

**File:** `lib/components/ui/confirm_action_dialog.dart`  
**Line:** 61

**Before:**

```dart
@override
Widget build(BuildContext context) {
  return AlertDialog(
    backgroundColor: const Color(0xFFD1D5DB),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Spacing.cardRadius),
    ),
```

**After:**

```dart
@override
Widget build(BuildContext context) {
  return AlertDialog(
    backgroundColor: context.colors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Spacing.cardRadius),
    ),
```

**Rationale:**

- Use the theme-aware `context.colors.surface` token instead of a hardcoded color
- Automatically adapts to dark mode (`0xFF18181B`) and light mode (`0xFFFAFAFA`)
- Consistent with all other modals and dialogs in the app (per previous fixes)
- No imports required — `context.colors` extension is already imported via `brand_colors.dart`

**Impact:**

- All 4 call sites automatically inherit the fix
- No code changes required at call sites
- No state management changes
- No routing or navigation changes

## 7. Database Impact

**Not applicable.** This is a pure UI fix with no database schema, query, RLS policy, migration, or RPC function changes.

## 8. Flutter Architecture Changes

**Scope:** Widget-level only. No changes to theme system, state management, routing, or app architecture.

**Changes:**

- **ConfirmActionDialog:** Replace hardcoded `backgroundColor` with `context.colors.surface`

**No changes to:**

- `brand_colors.dart` — Theme tokens remain stable
- `app_theme.dart` — Theme configuration remains stable
- State management (Riverpod providers)
- Routing or navigation
- Any other files

## 9. Files to Create

**None.** This is a pure fix to an existing file.

## 10. Files to Modify

| File                                           | Change                                                                                                       |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `lib/components/ui/confirm_action_dialog.dart` | Line 61: Replace `backgroundColor: const Color(0xFFD1D5DB),` with `backgroundColor: context.colors.surface,` |

**Total changes:** 1 file, 1 line modified

## 11. Files Off-Limits

The following files are **strictly off-limits** and must NOT be modified:

| File                                               | Reason                                         |
| -------------------------------------------------- | ---------------------------------------------- |
| `lib/app/theme/brand_colors.dart`                  | Theme token definitions are stable             |
| `lib/app/theme/app_theme.dart`                     | Theme configuration is stable                  |
| `lib/features/setlists/setlists_screen.dart`       | Call site — no changes required                |
| `lib/features/setlists/setlists_tab_content.dart`  | Call site — no changes required                |
| `lib/features/setlists/setlist_detail_screen.dart` | Different modal (delete song), already correct |
| `lib/main.dart`                                    | App initialization                             |
| `supabase/`                                        | Backend code                                   |
| Any migration files                                | No database changes                            |
| Any test files                                     | Unless broken by the fix                       |

## 12. System Impact Map

| System                                 | Impact                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                             |
| Rehearsals                             | unaffected                                                             |
| Setlists / Catalog                     | **affected** — Delete/Duplicate Setlist modals use ConfirmActionDialog |
| Members / RBAC                         | unaffected                                                             |
| Auth / Session                         | unaffected                                                             |
| Routing                                | unaffected                                                             |
| Notifications                          | unaffected                                                             |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms render ConfirmActionDialog                |

## 13. Regression Risk

**Risk Level:** LOW

**Rationale:**

- Single file changed (1 line)
- Shared component used in only 4 locations (all identified and audited)
- No logic changes — only visual theming
- No state management or async behavior changes
- Theme system is stable and well-tested (per previous dark mode fixes)
- Pattern already validated in 3 previous bug fixes:
  - `event_editor_drawer.dart` (dark-mode-modal-regression)
  - `calendar_subscription_dialog.dart` (dark-mode-modal-regression)
  - `print_options_bottom_sheet.dart` (print-options-dark-mode)

**Potential Regression Vectors:**

- If `context.colors` is unavailable at build time → Would cause compile error (caught by analyzer)
- If text colors do not contrast with new background → Already verified correct via existing `context.colors.textPrimary` / `textSecondary` usage in the widget

**Mitigation:**

- QA must test all 4 call sites in both dark mode and light mode
- Verify text readability in both themes
- Confirm no other dialogs are affected

## 14. Engineer Task Breakdown

1. Open `lib/components/ui/confirm_action_dialog.dart`
2. Navigate to line 61
3. Locate the `AlertDialog` widget with `backgroundColor: const Color(0xFFD1D5DB),`
4. Replace `const Color(0xFFD1D5DB)` with `context.colors.surface`
5. Save the file
6. Run `flutter analyze` and confirm 0 errors
7. Generate `git diff` for review

**Acceptance Criteria:**

- Line 61 reads `backgroundColor: context.colors.surface,`
- No other lines modified
- `flutter analyze` passes with 0 errors

## 15. Verification Plan

**Pre-deployment:**

- Run `flutter analyze` — must pass with 0 errors
- Visual inspection of code change (single line)

**Post-deployment (Manual QA):**

### Test 1 — Delete Setlist Modal (Dark Mode)

1. Set app theme to **Dark Mode** (Settings → Appearance)
2. Navigate to Setlists screen
3. Long-press any setlist → tap "Delete Setlist"
4. **Expected:** Modal background is dark (`Color(0xFF18181B)`)
5. **Expected:** Title text is white/light gray, message text is gray (high contrast)
6. **Expected:** Buttons render correctly (red "Delete", gray "Cancel")
7. Tap "Cancel" to dismiss

### Test 2 — Duplicate Setlist Modal (Dark Mode)

1. Remain in Dark Mode
2. Long-press any setlist → tap "Duplicate Setlist"
3. **Expected:** Modal background is dark (`Color(0xFF18181B)`)
4. **Expected:** Title text is white/light gray, message text is gray
5. **Expected:** Buttons render correctly (green "Duplicate", gray "Cancel")
6. Tap "Cancel" to dismiss

### Test 3 — Delete Setlist Modal (Light Mode)

1. Set app theme to **Light Mode** (Settings → Appearance)
2. Navigate to Setlists screen
3. Long-press any setlist → tap "Delete Setlist"
4. **Expected:** Modal background is light (`Color(0xFFFAFAFA)`)
5. **Expected:** Title text is dark slate, message text is dark slate (high contrast)
6. **Expected:** Buttons render correctly (red "Delete", gray "Cancel")
7. Tap "Cancel" to dismiss

### Test 4 — Duplicate Setlist Modal (Light Mode)

1. Remain in Light Mode
2. Long-press any setlist → tap "Duplicate Setlist"
3. **Expected:** Modal background is light (`Color(0xFFFAFAFA)`)
4. **Expected:** Title text is dark slate, message text is dark slate
5. **Expected:** Buttons render correctly (green "Duplicate", gray "Cancel")
6. Tap "Cancel" to dismiss

### Test 5 — Swipe-to-Delete (Dark Mode)

1. Set app theme to Dark Mode
2. Navigate to Setlists screen
3. Swipe left on any setlist card → tap "Delete"
4. Confirm modal renders in dark mode (same criteria as Test 1)
5. Tap "Cancel"

### Test 6 — Swipe-to-Delete (Light Mode)

1. Set app theme to Light Mode
2. Navigate to Setlists screen
3. Swipe left on any setlist card → tap "Delete"
4. Confirm modal renders in light mode (same criteria as Test 3)
5. Tap "Cancel"

## 16. QA Regression Areas

QA must specifically test the following to confirm no regressions:

**ConfirmActionDialog Call Sites (Primary):**

- ✅ Delete Setlist modal (setlists_screen.dart) — dark mode
- ✅ Delete Setlist modal (setlists_screen.dart) — light mode
- ✅ Duplicate Setlist modal (setlists_screen.dart) — dark mode
- ✅ Duplicate Setlist modal (setlists_screen.dart) — light mode
- ✅ Delete Setlist modal (setlists_tab_content.dart) — dark mode
- ✅ Delete Setlist modal (setlists_tab_content.dart) — light mode
- ✅ Duplicate Setlist modal (setlists_tab_content.dart) — dark mode
- ✅ Duplicate Setlist modal (setlists_tab_content.dart) — light mode

**Other Modals (Regression Check):**

- ✅ Event Editor Drawer (add/edit event) — dark mode
- ✅ Event Editor Drawer (add/edit event) — light mode
- ✅ Calendar Subscription Dialog — dark mode
- ✅ Calendar Subscription Dialog — light mode
- ✅ Delete Song Dialog (setlist_detail_screen.dart) — dark mode
- ✅ Delete Song Dialog (setlist_detail_screen.dart) — light mode
- ✅ Block Out Drawer — dark mode
- ✅ Block Out Drawer — light mode

**Platform Coverage:**

- Test on at least 2 platforms (iOS + Web recommended, or macOS + Android)
- Confirm no platform-specific rendering issues

## 17. Rollout / Migration Strategy

**Not applicable.** This is a client-side UI fix with no backend, database, or migration dependencies.

**Deployment Steps:**

1. Merge feature branch to main
2. Deploy web via `./tools/deploy_web.sh`
3. Mobile deployments (iOS/Android) will inherit fix on next app update

**Rollback Plan:**

- Revert single commit if regression discovered
- No data migration or state cleanup required

## 18. Out of Scope

The following are explicitly **out of scope** for this fix:

1. **Fixing other unrelated modals** — Only `ConfirmActionDialog` is in scope
2. **Refactoring the dialog API** — No changes to function signature or parameters
3. **Adding dark mode toggle UI** — Theme switching is already implemented (Settings → Appearance)
4. **Migrating to Material 3 dialogs** — Current Material 2 `AlertDialog` is stable and correct
5. **Optimizing dialog animations** — No performance or animation changes
6. **Adding unit tests** — No test coverage exists for UI components; adding tests is a separate initiative
7. **Re-auditing the entire codebase for hardcoded colors** — Only the reported bug is addressed
8. **Fixing the previous `dark-mode-modal-regression` plan's false positive classification** — The plan served its purpose; this is a new, distinct bug

---

**Plan Complete. Ready for Engineer implementation.**
