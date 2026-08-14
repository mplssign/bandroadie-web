# QA Report

## Feature Slug

`bug/forui-sheet-missing-material-ancestor`

## Feature Title

Fix Material Ancestor Missing in Forui Bottom Sheets

## Final Verdict

**REQUIRES MANUAL VERIFICATION** (Code-level review: APPROVED)

## Executive Summary

This fix addresses a **runtime crash** caused by Material-dependent widgets (InkWell, ListTile, SwitchListTile) being unable to find a Material ancestor when presented inside Forui bottom sheets. The root fix wraps the builder output in `Material(type: MaterialType.transparency)` inside `showAppBottomSheet`, matching Flutter's own pattern.

**Critical constraint**: This QA review is limited to code-level analysis, static checks, and unit tests. I do **not** have access to a real device or browser to perform runtime testing. Therefore, I **cannot confirm** the actual crash is fixed or that the 7 affected flows render correctly post-fix.

**Recommendation**: Tony (or manual QA) must physically run the app and verify at minimum:

1. Open a gig with a linked setlist from Home → Setlist row no longer shows red error box
2. Spot-check 2-3 other affected flows (venue navigation picker, member edit drawer permissions)
3. Confirm unaffected sheets still work (DayDetailBottomSheet, etc.)

Do **not** merge solely on this code-level QA approval without manual runtime verification.

---

## Validation Summary

**Code-level validation completed**:

- ✅ Git diff verified: Exactly 4-line change to `lib/components/ui/app_bottom_sheet.dart`, no other files modified
- ✅ Static analysis passed: `flutter analyze` returned 0 errors (8 pre-existing warnings unrelated to this change)
- ✅ Unit tests passed: 5/5 tests in `test/components/ui/app_bottom_sheet_test.dart`
- ✅ Widget tree traced: All 7 affected files confirmed to have Material-dependent widgets that will resolve the new Material ancestor
- ✅ Flutter framework cross-check: Confirmed Flutter's own `BottomSheet` wraps builder in Material (lines 407-427 in `package:flutter/src/material/bottom_sheet.dart`)
- ✅ Double-Material nesting safety: Verified 2 affected files (calendar_subscription_dialog.dart, setlist_picker_bottom_sheet.dart) already have nested Materials—this is safe and standard in Flutter
- ✅ Architect scope compliance: Only the approved file was modified, no files off-limits were touched

**Manual runtime validation NOT performed**:

- ❌ Cannot confirm ViewGigDrawer Setlist row crash is fixed (requires app launch + interaction)
- ❌ Cannot confirm 6 other affected flows render correctly (requires device/browser)
- ❌ Cannot confirm 5 regression-check flows are unaffected (requires device/browser)

---

## Architect Scope Review

### Scope Adherence

**Compliant**. Only the file listed in "Files to Modify" was changed. No additional refactoring, formatting, or out-of-scope modifications.

### Files Modified

**As expected**: `lib/components/ui/app_bottom_sheet.dart` — Added Material wrapper with exactly the code specified in the Architect plan.

### Files Off-Limits

**Not touched** (verified via `git diff main --name-only`):

- ✅ All 7 affected files (view_gig_drawer.dart, venue_detail_screen.dart, band_member_detail_drawer.dart, band_member_edit_drawer.dart, calendar_subscription_dialog.dart, setlist_picker_bottom_sheet.dart, key_picker_bottom_sheet.dart) were NOT modified—correctly repaired by the root fix.
- ✅ All 5 unaffected files (day_detail_bottom_sheet.dart, add_block_out_drawer.dart, pause_creator.dart, set_break_creator.dart, custom_tuning_modal.dart) were NOT modified.
- ✅ `lib/main.dart` — Not touched (init order unchanged).

---

## Completeness Check

### All Architect Tasks Implemented

**Code tasks: Yes. Manual tasks: No (cannot perform runtime testing).**

| Task                                                   | Status           | Notes                                                |
| ------------------------------------------------------ | ---------------- | ---------------------------------------------------- |
| Task 1: Verify current failure state                   | ❌ NOT PERFORMED | No device/browser access to observe red error box    |
| Task 2: Implement root fix in app_bottom_sheet.dart    | ✅ COMPLETED     | Exact code from plan applied                         |
| Task 3-9: Verify 7 affected flows post-fix             | ❌ NOT PERFORMED | Cannot launch app or interact with UI                |
| Task 10: Verify 5 unaffected sheets (regression check) | ❌ NOT PERFORMED | Cannot launch app or interact with UI                |
| Task 11: Run flutter analyze                           | ✅ COMPLETED     | 0 errors, 8 pre-existing warnings                    |
| Task 12: Generate implementation report                | ✅ COMPLETED     | Engineer report exists and documents code completion |

### Missing Manual Verification (Requires Tony or Manual QA)

Tasks 3-10 from the Architect plan require physical app interaction:

1. ViewGigDrawer Setlist/Notes rows (confirm no red error box)
2. VenueDetailScreen navigation picker (3 ListTile options render)
3. BandMemberDetailDrawer Phone/Email rows (InkWell renders)
4. BandMemberEditDrawer contributor permissions (SwitchListTile renders)
5. CalendarSubscriptionDialog interactive elements (InkWell renders)
6. SetlistPickerBottomSheet option tiles (InkWell renders)
7. KeyPickerBottomSheet key tiles (ListTile renders)
8. DayDetailBottomSheet (regression check—GestureDetector-only)
9. AddBlockOutDrawer (regression check)
10. PauseCreator, SetBreakCreator, CustomTuningModal (regression checks)

---

## Behavior Verification

### Validation Method

**Code-path analysis only** (runtime testing not performed).

### Result

**Code-level analysis confirms the fix is theoretically correct**:

1. **Widget tree traced**: For example, in `view_gig_drawer.dart`:

   ```
   showAppBottomSheet(builder: (context) => ViewGigDrawer())

   After fix:
   showFSheet(
     builder: (context) => Material(type: MaterialType.transparency)  // <-- NEW ancestor
       └─ ViewGigDrawer()
          └─ ... intermediate widgets ...
             └─ _DetailRow(onTap: ...)
                └─ InkWell()  // <-- Searches up tree, now finds Material!
   ```

2. **Flutter framework pattern validated**: Flutter's own `BottomSheet` widget (lines 407-427 in `package:flutter/src/material/bottom_sheet.dart`) wraps the builder output in a Material widget. BandRoadie's fix uses `MaterialType.transparency` which is more minimal but serves the same purpose—providing a Material ancestor for ink effects without visual styling.

3. **Double-Material nesting safety confirmed**: Two affected files already have Material widgets in their subtrees:
   - `calendar_subscription_dialog.dart`: Lines 99 (transparent Material for content container) and 452 (colored Material for button)
   - `setlist_picker_bottom_sheet.dart`: Line 597 (transparent Material wrapping InkWell)

   Nested Materials are standard in Flutter when each serves a different purpose (ancestor provider vs. surface styling). The new transparent Material at the root won't conflict.

4. **All 7 affected files confirmed to have Material-dependent widgets** (grep verification):
   - view_gig_drawer.dart: 3 ListTile (lines 129, 136, 143) + InkWell in \_DetailRow (line 504)
   - venue_detail_screen.dart: 3 ListTile in navigation picker (lines 300, 307, 314)
   - band_member_detail_drawer.dart: InkWell in \_DetailRow (line 327)
   - band_member_edit_drawer.dart: SwitchListTile (line 649)
   - calendar_subscription_dialog.dart: InkWell (line 455)
   - setlist_picker_bottom_sheet.dart: InkWell (line 599)
   - key_picker_bottom_sheet.dart: 2 ListTile (lines 91, 167)

5. **All 5 unaffected files confirmed NOT modified**: Git diff shows only `app_bottom_sheet.dart` changed.

### What Cannot Be Verified Without Runtime Testing

- Actual visual rendering of affected widgets post-fix
- Confirmation that the red error box no longer appears
- Interactive behavior (tap handlers work correctly)
- Cross-platform consistency (web, iOS, macOS, Android)

---

## Regression Check

### Risk Level

**LOW** (based on code analysis)

### Systems Reviewed

Reviewed all systems from Architect's System Impact Map:

| System             | Impact                                             | QA Status                         |
| ------------------ | -------------------------------------------------- | --------------------------------- |
| Gigs               | affected — view_gig_drawer.dart fixed              | Code-level confirmed ✅           |
| Rehearsals         | unaffected                                         | No changes ✅                     |
| Setlists / Catalog | affected — setlist_picker, key_picker fixed        | Code-level confirmed ✅           |
| Members / RBAC     | affected — member detail/edit drawers fixed        | Code-level confirmed ✅           |
| Auth / Session     | unaffected                                         | No changes ✅                     |
| Routing            | unaffected                                         | No changes ✅                     |
| Notifications      | unaffected                                         | No changes ✅                     |
| Contacts / Venues  | affected — venue_detail_screen.dart fixed          | Code-level confirmed ✅           |
| Calendar           | affected — calendar_subscription_dialog.dart fixed | Code-level confirmed ✅           |
| Platform (all)     | affected — crash was cross-platform                | Cannot verify runtime behavior ⚠️ |

### Regressions Found

**None identified at code level**. However, regression testing requires manual verification:

- Unaffected sheets (GestureDetector-only) must be spot-checked to confirm no visual changes
- Affected sheets must be spot-checked to confirm Material wrapper doesn't introduce layout shifts

### Why Risk Remains LOW Despite Manual Testing Gap

1. **Single file modified**: Only `app_bottom_sheet.dart`, 4-line change
2. **MaterialType.transparency is a visual no-op**: No background color, elevation, shadow, or clipping
3. **Matches framework convention**: Flutter's own BottomSheet uses the same pattern (with non-transparent Material)
4. **No state management changes**: No controllers, providers, or repositories modified
5. **No database changes**: Pure UI fix
6. **Blast radius contained**: Only bottom sheets presented via `showAppBottomSheet` affected
7. **Unit tests pass**: Existing test coverage confirms Material wrapper doesn't break assertions

---

## Database Safety

**Not applicable**. This is a UI widget layer bug. No database tables, RLS policies, RPCs, or migrations are involved.

---

## Analyzer Results

**Command**: `flutter analyze`

**Result**: 0 errors

**Warnings breakdown**:

- 2 unused imports (pre-existing, unrelated)
- 2 unused local variables in production code (pre-existing, unrelated)
- 2 async context warnings (pre-existing, unrelated)
- 2 test file warnings (pre-existing, unrelated)

**No new warnings introduced by this implementation.**

---

## Test Results

**Command**: `flutter test test/components/ui/app_bottom_sheet_test.dart`

**Result**: Passed (5/5 tests)

All existing tests for `app_bottom_sheet.dart` pass without modification. The Material wrapper with `MaterialType.transparency` is transparent to existing test assertions, confirming it doesn't break the public API or basic behavior.

**Note**: These are unit tests of the wrapper function, not integration tests of affected UI flows. Integration/manual tests required to confirm the crash is fixed.

---

## Diff Safety Review

**Secrets**: None found ✅

**Debug artifacts**: None found ✅

- No `print()` statements
- No TODO comments
- No temporary flags
- No scaffolding code

**Unrelated changes**: None found ✅

- Only the Material wrapper added to `app_bottom_sheet.dart`
- No formatting churn
- No accidental file deletions
- No config or environment variable changes

**Git diff summary**:

```diff
- builder: builder,
+ builder: (context) => Material(
+   type: MaterialType.transparency,
+   child: builder(context),
+ ),
```

Clean, minimal, exactly as specified in the Architect plan.

---

## Issues Found

### Critical (must fix before manual runtime QA)

None.

### Warnings (should address)

None at code level. However:

**Manual runtime QA is mandatory**. This fix addresses a runtime crash. Code-level review cannot substitute for actually launching the app and exercising the affected flows. The following must be manually verified before merge:

1. **Primary repro**: Open Home → tap a gig with linked setlist → confirm Setlist row no longer shows red error box
2. **Spot-check 2-3 affected flows**: E.g., venue navigation picker (3 ListTile options), member edit drawer permissions (SwitchListTile)
3. **Spot-check 1-2 regression flows**: E.g., DayDetailBottomSheet (GestureDetector-only), PauseCreator

### Suggestions (optional)

None. The implementation matches the Architect plan exactly and uses the minimal, safest approach.

---

## Technical Deep-Dive: Why This Fix Is Correct

### Flutter Framework Validation

Cross-checked against Flutter's own `showModalBottomSheet` implementation (`package:flutter/src/material/bottom_sheet.dart`, lines 407-427):

Flutter's `BottomSheet` widget wraps the builder output in a Material widget:

```dart
Widget bottomSheet = Material(
  key: _childKey,
  color: color,
  elevation: elevation,
  surfaceTintColor: surfaceTintColor,
  shadowColor: shadowColor,
  shape: shape,
  clipBehavior: clipBehavior,
  child: NotificationListener<DraggableScrollableNotification>(
    onNotification: extentChanged,
    child: !showDragHandle
        ? widget.builder(context)  // <-- Builder output wrapped in Material
        : Stack(...),
  ),
);
```

BandRoadie's fix uses `Material(type: MaterialType.transparency)` which is:

- **More minimal**: No color, elevation, shadow, or shape—purely an ancestor provider
- **Appropriate for Forui wrapper**: Forui may have its own sheet styling; the transparent Material doesn't interfere
- **Safe**: `MaterialType.transparency` is explicitly designed for providing Material ancestor without visual artifacts

### Why MaterialType.transparency Is Safe

From Flutter documentation (Material class):

> `MaterialType.transparency` — A Material widget with no background color and no elevation. This is useful when you need to provide a Material ancestor for widgets that require it (like InkWell), but don't want any visual material design.

This is the exact use case!

### Double-Material Nesting Is Standard

Two affected files already have nested Materials:

1. **calendar_subscription_dialog.dart**:
   - Line 99: `Material(color: Colors.transparent)` — content container
   - Line 452: `Material(color: success/primary)` — button background
2. **setlist_picker_bottom_sheet.dart**:
   - Line 597: `Material(color: Colors.transparent)` — wraps InkWell for option tile

After the fix, tree structure:

```
Material(transparency) from showAppBottomSheet  // <-- Ancestor provider
└─ CalendarSubscriptionDialog
   └─ Material(transparent) at line 99          // <-- Surface container
      └─ ... content ...
         └─ Material(colored) at line 452       // <-- Button styling
            └─ InkWell
```

This is standard Flutter patterns. Nested Materials are fine when each serves a purpose. The transparent Materials don't render visible layers, so there's no visual stacking or performance penalty.

---

## Manual QA Instructions (For Tony or Runtime Tester)

### Setup

1. Checkout branch: `bug/forui-sheet-missing-material-ancestor`
2. Ensure clean working tree: `git status` (only docs/ untracked is OK)
3. Launch app: `flutter run -d macos` (or web, iOS)

### Critical Path: Confirm Primary Repro Is Fixed

1. Navigate to Home dashboard
2. Tap any gig that has a linked setlist
3. Observe the ViewGigDrawer opens
4. **Expected**: Setlist row renders correctly (no red error box)
5. **Expected**: Notes row renders correctly (if gig has notes)
6. Tap Setlist row → confirm navigation to setlist detail works
7. Close drawer

**If red error box still appears, STOP. Fix did not work. Do not merge.**

### Spot-Check 2 Other Affected Flows

1. **Venue navigation picker**:
   - Navigate to Contacts → Venues → tap any venue with address
   - Tap navigation icon
   - **Expected**: Picker opens with 3 ListTile options (Apple Maps, Google Maps, Waze)
   - Tap an option → confirm picker closes, external app launches (if supported)

2. **Member edit permissions (admin only)**:
   - Navigate to Members → tap any member → tap "Edit"
   - Select "Contributor" role
   - **Expected**: Sub-permissions section renders with SwitchListTile toggles (no red error box)
   - Toggle a switch → confirm state updates
   - Cancel

### Regression Spot-Check (1-2 Unaffected Sheets)

1. **DayDetailBottomSheet** (GestureDetector-only):
   - Navigate to Calendar → tap any date with events
   - **Expected**: Sheet opens, renders correctly, no visual regression
   - Close sheet

2. **PauseCreator** (GestureDetector-only):
   - Navigate to any setlist → tap "Add Pause"
   - **Expected**: Sheet opens, renders correctly, no visual regression
   - Cancel

### Cross-Platform Verification (Recommended)

Repeat "Critical Path" on at least 2 platforms:

- ✅ Web (easiest to launch)
- ✅ iOS or macOS
- (Android optional if available)

---

## QA_REPORT.md File Confirmation

This file has been written to:

```
/Users/tonyholmes/apps/bandroadie/docs/features/forui-sheet-missing-material-ancestor/QA_REPORT.md
```

Confirming file exists on disk now.

---

## Final Recommendation

**Code-level implementation: APPROVED**

- Architect scope compliance: ✅
- Static analysis: ✅
- Unit tests: ✅
- Widget tree logic: ✅
- Flutter framework pattern: ✅
- Minimal, safe change: ✅

**Manual runtime verification: REQUIRED BEFORE MERGE**

- Cannot approve for merge without manual QA
- This fix addresses a **runtime crash**—code review alone is insufficient
- Tony must physically test the primary repro (gig detail setlist row) on at least one platform before merging

**Verdict**: REQUIRES MANUAL VERIFICATION (blocking). Do not merge until runtime QA confirms the crash is fixed and spot-checks pass.
