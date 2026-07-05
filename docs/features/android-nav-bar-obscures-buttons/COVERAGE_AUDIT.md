# Coverage Audit: Bottom Inset Handling

## Summary

- **Total files with `padding.bottom`:** 36 files (40 occurrences)
- **Files with `showModalBottomSheet`:** 26 files
- **Files with `FloatingActionButton`:** 2 files (1 affected: landing_page.dart)
- **Files using `viewInsets.bottom` (keyboard-aware):** 13 files
- **Additional affected files (no `padding.bottom` but obscured):** 1 file (landing_page.dart FAB)
- **Total affected files:** 37 files (36 with `padding.bottom` + 1 FAB with hardcoded bottom position)

## Complete File Inventory

### Category 1: Critical Files (Bottom Nav and Tab Content) — 9 files

| File                                                     | Lines      | Current Pattern                                   | Keyboard Input? | Status                                                                                |
| -------------------------------------------------------- | ---------- | ------------------------------------------------- | --------------- | ------------------------------------------------------------------------------------- |
| `lib/features/home/widgets/animated_bottom_nav_bar.dart` | 185        | `padding.bottom` → height calculation             | No              | **AFFECTED** - Must fix                                                               |
| `lib/features/home/home_screen.dart`                     | 918        | `padding.bottom` → content bottom padding         | No              | **AFFECTED** - Must fix                                                               |
| `lib/features/home/home_tab_content.dart`                | 1015       | `padding.bottom` → scroll bottom padding          | No              | **AFFECTED** - Must fix                                                               |
| `lib/features/home/widgets/empty_home_state.dart`        | 184        | `padding.bottom` → content bottom padding         | No              | **AFFECTED** - Must fix                                                               |
| `lib/features/calendar/calendar_tab_content.dart`        | 514        | `padding.bottom` → scroll bottom padding          | No              | **AFFECTED** - Must fix                                                               |
| `lib/features/calendar/calendar_screen.dart`             | 534        | `padding.bottom` → scroll bottom padding          | No              | **AFFECTED** - Must fix                                                               |
| `lib/features/setlists/setlists_tab_content.dart`        | 588        | `padding.bottom` → scroll bottom padding          | No              | **AFFECTED** - Must fix                                                               |
| `lib/features/setlists/setlist_detail_screen.dart`       | 1768, 2355 | `padding.bottom` → bottom padding (2 occurrences) | No              | **AFFECTED** - Must fix (Note: Line 3113 already uses `viewPadding.bottom` correctly) |
| `lib/features/members/members_tab_content.dart`          | 318        | `padding.bottom` → scroll bottom padding          | No              | **AFFECTED** - Must fix                                                               |

### Category 2: Bottom Sheets and Drawers — 17 files

| File                                                                        | Lines    | Current Pattern                                                   | Keyboard Input? | Keyboard Handling                     | Status                                             |
| --------------------------------------------------------------------------- | -------- | ----------------------------------------------------------------- | --------------- | ------------------------------------- | -------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart`                      | 2028     | `padding.bottom` + `viewInsets.bottom`                            | **YES**         | Already adds keyboard inset           | **AFFECTED** - Needs keyboard regression testing   |
| `lib/features/gigs/widgets/view_gig_drawer.dart`                            | 412      | `padding.bottom` only                                             | No              | N/A                                   | **AFFECTED** - Must fix                            |
| `lib/features/gigs/widgets/gig_notes_sheet.dart`                            | 102      | `padding.bottom` only                                             | **YES**         | No keyboard handling currently        | **AFFECTED** - Must fix + add keyboard handling    |
| `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`                | 272      | `padding.bottom` only                                             | No              | N/A                                   | **AFFECTED** - Must fix                            |
| `lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart`                | 99       | `padding.bottom` only                                             | **YES**         | No keyboard handling currently        | **AFFECTED** - Must fix + add keyboard handling    |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`                   | 550      | `padding.bottom` + `viewInsets.bottom`                            | **YES**         | Already adds keyboard inset           | **AFFECTED** - Needs keyboard regression testing   |
| `lib/features/calendar/widgets/view_block_out_drawer.dart`                  | 161      | `padding.bottom` only                                             | No              | N/A                                   | **AFFECTED** - Must fix                            |
| `lib/features/calendar/widgets/day_detail_bottom_sheet.dart`                | 86       | `padding.bottom` only                                             | No              | N/A                                   | **AFFECTED** - Must fix                            |
| `lib/features/calendar/widgets/calendar_subscription_dialog.dart`           | 90       | `padding.bottom` + `viewInsets.bottom`                            | **YES**         | Already adds keyboard inset           | **AFFECTED** - Needs keyboard regression testing   |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart`              | 1351     | `padding.bottom` + `viewInsets.bottom` (line 718)                 | **YES**         | Already adds keyboard inset           | **AFFECTED** - Needs keyboard regression testing   |
| `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart`             | 750      | `padding.bottom` only                                             | **YES**         | No explicit keyboard handling visible | **AFFECTED** - Must fix + verify keyboard behavior |
| `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`            | 362, 475 | `padding.bottom` (2 occurrences) + `viewInsets.bottom` (line 206) | **YES**         | Already has keyboard awareness        | **AFFECTED** - Needs keyboard regression testing   |
| `lib/features/setlists/widgets/print_options_bottom_sheet.dart`             | 879      | `padding.bottom` only                                             | No              | N/A                                   | **AFFECTED** - Must fix                            |
| `lib/features/members/widgets/role_management_sheet.dart`                   | 458      | `padding.bottom` only                                             | No              | N/A                                   | **AFFECTED** - Must fix                            |
| `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`                 | 154      | `padding.bottom` only                                             | **YES**         | No keyboard handling currently        | **AFFECTED** - Must fix + verify keyboard behavior |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`     | 409      | `padding.bottom` only                                             | **YES**         | No keyboard handling currently        | **AFFECTED** - Must fix + verify keyboard behavior |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | 60       | `padding.bottom` + `viewInsets.bottom` (line 59)                  | **YES**         | Already adds keyboard inset           | **AFFECTED** - Needs keyboard regression testing   |

### Category 3: Forms and Misc UI — 10 files

| File                                                                 | Lines | Current Pattern                                        | Keyboard Input? | Status                                             |
| -------------------------------------------------------------------- | ----- | ------------------------------------------------------ | --------------- | -------------------------------------------------- |
| `lib/features/setlists/widgets/add_to_setlist/pause_screen.dart`     | 692   | `padding.bottom` + uses `viewInsets.bottom` (line 150) | **YES**         | **AFFECTED** - Needs keyboard regression testing   |
| `lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart` | 341   | `padding.bottom` + uses `viewInsets.bottom` (line 93)  | **YES**         | **AFFECTED** - Needs keyboard regression testing   |
| `lib/features/contacts/widgets/venue_form_screen.dart`               | 536   | `padding.bottom` only                                  | **YES**         | **AFFECTED** - Must fix + verify keyboard behavior |
| `lib/features/contacts/widgets/contact_form_screen.dart`             | 374   | `padding.bottom` only                                  | **YES**         | **AFFECTED** - Must fix + verify keyboard behavior |
| `lib/features/contacts/widgets/band_members_view.dart`               | 119   | `padding.bottom` → list bottom padding                 | No              | **AFFECTED** - Must fix                            |
| `lib/features/contacts/widgets/contacts_view.dart`                   | 163   | `padding.bottom` → list bottom padding                 | No              | **AFFECTED** - Must fix                            |
| `lib/features/contacts/widgets/venues_view.dart`                     | 163   | `padding.bottom` → list bottom padding                 | No              | **AFFECTED** - Must fix                            |
| `lib/features/financials/financials_screen.dart`                     | 720   | `padding.bottom` → bottom padding                      | No              | **AFFECTED** - Must fix                            |
| `lib/features/settings/settings_screen.dart`                         | 373   | `padding.bottom` → scroll bottom padding               | No              | **AFFECTED** - Must fix                            |
| `lib/shared/utils/snackbar_helper.dart`                              | 47    | `padding.bottom` → snackbar bottom margin              | No              | **AFFECTED** - Must fix                            |

### Category 4: Files with Bottom Sheets BUT No Current padding.bottom Usage

| File                                                           | showModalBottomSheet? | Bottom Inset Handling?                                      | Status                                               |
| -------------------------------------------------------------- | --------------------- | ----------------------------------------------------------- | ---------------------------------------------------- |
| `lib/features/lyrics/widgets/lyrics_editor_sheet.dart`         | Yes (line 68)         | No bottom padding usage found                               | **NOT APPLICABLE** - No bottom inset handling needed |
| `lib/features/setlists/widgets/key_picker_bottom_sheet.dart`   | Yes (line 42)         | Has SafeArea wrapper (line 59)                              | **NOT APPLICABLE** - SafeArea handles it             |
| `lib/features/setlists/widgets/custom_tuning_modal.dart`       | Yes (line 27)         | Uses `viewInsets.bottom` (line 210) for keyboard only       | **ALREADY SAFE** - keyboard handling only            |
| `lib/features/setlists/widgets/pause_creator.dart`             | Yes (line 40)         | Uses `viewInsets.bottom` (line 150) + SafeArea (line 172)   | **ALREADY SAFE**                                     |
| `lib/features/setlists/widgets/set_break_creator.dart`         | Yes (line 20)         | Uses `viewInsets.bottom` (line 93) + SafeArea (line 112)    | **ALREADY SAFE**                                     |
| `lib/features/bands/band_form_screen.dart`                     | Yes (lines 542, 1281) | Multiple SafeArea wrappers (lines 550, 1287, 1494)          | **NOT APPLICABLE** - SafeArea handles it             |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Yes (line 62)         | Wrapper for EventEditorDrawer (already covered in Category 2) | **NOT APPLICABLE** - delegates to EventEditorDrawer  |
| `lib/components/overlays/tips_and_tricks_overlay.dart`         | Yes (line 250)        | No MediaQuery bottom inset usage, only hardcoded EdgeInsets | **NOT APPLICABLE** - No bottom inset handling        |

### Category 5: Files with FloatingActionButton

| File                                             | FAB Location                             | Bottom Inset Handling?                                                  | Status                                                                           |
| ------------------------------------------------ | ---------------------------------------- | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `lib/features/landing/landing_page.dart`         | `Positioned(bottom: 24)` (lines 117-128) | Hardcoded 24px from bottom, wrapped in Scaffold with NO bottom SafeArea | **AFFECTED** - FAB will be obscured by Android nav bar (need SafeArea or inset) |
| `lib/features/financials/financials_screen.dart` | N/A                                      | Already in Category 3 (line 720 uses `padding.bottom`)                  | **AFFECTED** - covered above                                                     |

## Keyboard Regression Analysis

### Files Using BOTH `viewInsets.bottom` + `padding.bottom`

These files add keyboard height + safe area. When switching to `viewPadding.bottom`, we need to verify the behavior:

**Expected behavior:**

- On iOS: `viewPadding.bottom` remains constant (home indicator height) when keyboard opens. `viewInsets.bottom` = keyboard height. Total = correct.
- On Android: `viewPadding.bottom` should represent system nav bar even when keyboard is open. `viewInsets.bottom` = keyboard height. Need to verify no double-padding.

**Files requiring keyboard-open testing:**

1. **event_editor_drawer.dart** (lines 2027-2028)
   - Current: `viewInsets.bottom + padding.bottom`
   - After fix: `viewInsets.bottom + viewPadding.bottom`
   - **Test:** Open drawer, focus text field, verify bottom padding above keyboard

2. **add_block_out_drawer.dart** (lines 549-550)
   - Current: `viewInsets.bottom + padding.bottom`
   - After fix: `viewInsets.bottom + viewPadding.bottom`
   - **Test:** Open drawer, focus text field, verify bottom padding above keyboard

3. **calendar_subscription_dialog.dart** (lines 89-90)
   - Current: `viewInsets.bottom + padding.bottom`
   - After fix: `viewInsets.bottom + viewPadding.bottom`
   - **Test:** Open dialog, focus text field, verify bottom padding above keyboard

4. **song_details_bottom_sheet.dart** (lines 718, 1351)
   - Current: Uses both separately
   - After fix: Both change to `viewPadding.bottom`
   - **Test:** Open sheet, focus text field (if present), verify layout

5. **setlist_picker_bottom_sheet.dart** (lines 206, 362, 475)
   - Current: `viewInsets.bottom` (line 206) + `padding.bottom` (lines 362, 475)
   - After fix: All `padding.bottom` → `viewPadding.bottom`
   - **Test:** Open sheet, focus search/text field, verify bottom padding

6. **financial_entry_details_bottom_sheet.dart** (lines 59-60)
   - Current: `viewInsets.bottom + padding.bottom`
   - After fix: `viewInsets.bottom + viewPadding.bottom`
   - **Test:** Open sheet, focus text field, verify bottom padding

7. **pause_screen.dart** (lines 150, 692)
   - Current: Uses both
   - After fix: Both change to `viewPadding.bottom`
   - **Test:** Open screen, focus text field, verify bottom padding

8. **set_break_screen.dart** (lines 93, 341)
   - Current: Uses both
   - After fix: Both change to `viewPadding.bottom`
   - **Test:** Open screen, focus text field, verify bottom padding

## Action Items for Architect

1. ✅ **Inventory complete:** 37 files affected
   - 36 files with `padding.bottom` usage (40 occurrences)
   - 1 file with hardcoded FAB bottom position (landing_page.dart)
2. ⚠️  **Empirical measurement:** BLOCKED by disk space (disk 100% full)
   - Root cause confidence: HIGH (based on Flutter/Android API documentation)
   - Recommendation: Accept documentation-based evidence OR free up ~10GB disk space
3. ✅ **SafeArea consumption check:** Complete
   - No MediaQuery.removePadding found
   - No SafeArea at shell level
   - No Scaffold body consumption
4. ✅ **Keyboard regression plan:** Complete
   - 8 files require keyboard-open verification (both Android and iOS)
   - Detailed test procedure in ARCHITECT_PLAN.md "TEST 5: Keyboard Regression"
5. ✅ **Coverage audit:** Complete - all NEEDS AUDIT rows resolved
