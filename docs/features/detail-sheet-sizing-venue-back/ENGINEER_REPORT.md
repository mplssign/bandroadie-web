# Engineer Report

## Feature Slug

`feature/detail-sheet-sizing-venue-back`

## Feature Title

Detail Sheet Sizing & Venue Back Button (Both Corrections Applied)

## Goal

Fix sheet height constraints by addressing the actual binding constraint in Forui's `showFSheet` default parameters. Correction #1: Add `mainAxisMaxRatio` parameter to allow taller sheets. Correction #2: Forward `useSafeArea` parameter to prevent header/status bar collisions on notched devices. View sheets use ~85-90% of screen height, edit sheets use full screen height with proper safe area handling. Add explicit back button to VenueDetailScreen. Create read-only Contact view drawer following established pattern.

## Architect Tasks Completed

### Core Implementation (Correction #1 + Correction #2)

- [x] **Task 1** — Add `mainAxisMaxRatio` parameter to `showAppBottomSheet()` in `lib/components/ui/app_bottom_sheet.dart`
  - Added optional `double? mainAxisMaxRatio` parameter
  - Forwarded to `showFSheet()` with mandatory `?? (9 / 16)` fallback to preserve backward compatibility
  - Updated documentation to explain parameter purpose

- [x] **Task 2** — Forward `useSafeArea` parameter to `showFSheet()` in `lib/components/ui/app_bottom_sheet.dart`
  - Parameter already declared but was dropped (dead code)
  - Now forwarded to `showFSheet()` as `useSafeArea: useSafeArea`
  - Defaults to `false` for backward compatibility

### View Sheet Call Sites (mainAxisMaxRatio: 0.95 + useSafeArea: true)

### View Sheet Call Sites (mainAxisMaxRatio: 0.95 + useSafeArea: true)

- [x] **Task 3** — Update `view_gig_drawer.dart` call site (line 41)
  - Added `mainAxisMaxRatio: 0.95` to `showAppBottomSheet()` call
  - Added `useSafeArea: true` to `showAppBottomSheet()` call
  - Internal `Container(maxHeight: 0.95)` unchanged from prior round

- [x] **Task 4** — Update `band_member_detail_drawer.dart` call site (line 38)
  - Added `mainAxisMaxRatio: 0.95` to `showAppBottomSheet()` call
  - Added `useSafeArea: true` to `showAppBottomSheet()` call
  - Internal `Container(maxHeight: 0.95)` unchanged from prior round

- [x] **Task 5** — Update `contact_detail_drawer.dart` call site (line 34)
  - Added `mainAxisMaxRatio: 0.95` to `showAppBottomSheet()` call
  - Added `useSafeArea: true` to `showAppBottomSheet()` call
  - File already created in prior round, wired into `contacts_view.dart`
  - Internal `Container(maxHeight: 0.95)` already present

### Edit Sheet Call Sites (mainAxisMaxRatio: 1.0 + useSafeArea: true)

- [x] **Task 6** — Update `add_edit_event_bottom_sheet.dart` call site (line 63)
  - Added `mainAxisMaxRatio: 1.0` to `showAppBottomSheet()` call
  - Added `useSafeArea: true` to `showAppBottomSheet()` call
  - This is the wrapper that invokes `EventEditorDrawer`

- [x] **Task 7** — Update `add_block_out_drawer.dart` call site (line 88)
  - Added `mainAxisMaxRatio: 1.0` to `showAppBottomSheet()` call
  - Added `useSafeArea: true` to `showAppBottomSheet()` call

### Pre-Existing Changes from Prior Round

- [x] **Task 8** — Internal `Container(maxHeight: 0.95)` in view sheets
  - Already present in `view_gig_drawer.dart` (line 245)
  - Already present in `band_member_detail_drawer.dart` (line 134)
  - Already present in `view_rehearsal_drawer.dart` (line 147)
  - Already present in `view_block_out_drawer.dart` (line 74)
  - Already present in `contact_detail_drawer.dart` (line 82)

- [x] **Task 9** — ContactDetailDrawer creation and wiring
  - File already exists at `lib/features/contacts/widgets/contact_detail_drawer.dart`
  - Already wired into `contacts_view.dart` (lines 120, 168)
  - Follows `BandMemberDetailDrawer` pattern with phone/email tap handlers

- [x] **Task 10** — VenueDetailScreen back button
  - Already added in prior round at line 38
  - Uses `AppIconButton` with `AppIcons.back`

## Files Created

None (all files created in prior round)

## Files Modified

### Core Fix (Correction #1 + Correction #2)

- `lib/components/ui/app_bottom_sheet.dart` — Added `mainAxisMaxRatio` parameter with `?? (9 / 16)` fallback; forwarded `useSafeArea` parameter to `showFSheet()`

### View Sheet Call Sites (Both Corrections Applied)

- `lib/features/gigs/widgets/view_gig_drawer.dart` — Added `mainAxisMaxRatio: 0.95` and `useSafeArea: true` to call site
- `lib/features/contacts/widgets/band_member_detail_drawer.dart` — Added `mainAxisMaxRatio: 0.95` and `useSafeArea: true` to call site
- `lib/features/contacts/widgets/contact_detail_drawer.dart` — Added `mainAxisMaxRatio: 0.95` and `useSafeArea: true` to call site

### Edit Sheet Call Sites (Both Corrections Applied)

- `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` — Added `mainAxisMaxRatio: 1.0` and `useSafeArea: true` to call site
- `lib/features/calendar/widgets/add_block_out_drawer.dart` — Added `mainAxisMaxRatio: 1.0` and `useSafeArea: true` to call site

### Previously Modified (Prior Round)

- `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart` — Internal `maxHeight: 0.95` (uses `showModalBottomSheet`)
- `lib/features/calendar/widgets/view_block_out_drawer.dart` — Internal `maxHeight: 0.95` (uses `showModalBottomSheet`)
- `lib/features/contacts/widgets/contacts_view.dart` — Already wired to `ContactDetailDrawer.show()`
- `lib/features/contacts/widgets/venue_detail_screen.dart` — Already has back button
- `lib/features/events/widgets/event_editor_drawer.dart` — (tracked by git status, no further changes needed)

## Analyzer Results

**Command:** `flutter analyze`  
**Result:** 0 errors, 8 warnings (all pre-existing, unrelated to this implementation)

**Pre-existing warnings (not introduced by this feature):**

- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`: unused import, unused variable, async context
- `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart`: async context
- `test/components/ui/app_text_field_test.dart`: unused variables
- `test/components/ui/app_text_form_field_test.dart`: unused variable

No new warnings introduced.

## Test Results

Not run (no test coverage exists for bottom sheet height constraints)

## Verification

### Backward Compatibility Sanity Check (Code Inspection)

**Mandatory requirement:** Verify sheets that do NOT pass `mainAxisMaxRatio` still behave as before.

**Method:** Code inspection (no device/browser access available)

**Example sheet checked:** `lib/features/setlists/widgets/song_notes_drawer.dart` (line 27)

- Calls `showAppBottomSheet` without `mainAxisMaxRatio` parameter
- Parameter defaults to `null` in function signature
- Fallback `?? (9 / 16)` in `app_bottom_sheet.dart` line 33 passes `9 / 16` to Forui
- **Result:** Preserves existing behavior (~56% max height)

**Conclusion:** By code inspection, backward compatibility is preserved. All ~136 existing call sites that don't pass the new parameter will continue to receive Forui's default 9/16 constraint.

**Visual verification status:** Unable to perform. I do not have access to a running device or browser instance to visually confirm sheet heights. QA must perform visual verification on all platforms (iOS, Android, macOS, Web) to confirm:

1. View sheets visibly increased from ~56% to ~85-90% height
2. Edit sheets visibly increased to full screen height
3. Sheets without `mainAxisMaxRatio` (e.g., song notes drawer, key picker) still render at ~56% height
4. No regressions in other sheets across the app

### Manual Steps Performed

1. ✅ Confirmed branch `feature/detail-sheet-sizing-venue-back`
2. ✅ Read `ENGINEER.md`, `GUARDRAILS.md`, `ARCHITECT_PLAN.md` (including correction section)
3. ✅ Checked current state of files modified in prior round
4. ✅ Added `mainAxisMaxRatio` parameter to `app_bottom_sheet.dart` with mandatory fallback
5. ✅ Added `mainAxisMaxRatio: 0.95` to 3 view sheet call sites
6. ✅ Added `mainAxisMaxRatio: 1.0` to 2 edit sheet call sites
7. ✅ Ran `flutter analyze` — 0 errors
8. ✅ Performed backward compatibility sanity check by code inspection
9. ✅ Verified internal `Container(maxHeight: 0.95)` values already present from prior round
10. ✅ Verified `ContactDetailDrawer` already created and wired
11. ✅ Verified `VenueDetailScreen` back button already added
12. ✅ Created and verified existence of `ENGINEER_REPORT.md`

## Deviations From Architect Plan

None. All tasks completed exactly as specified in the corrected plan.

**Note on Internal Constraints:** The Architect Plan's table in §2 lists internal `Container(maxHeight: 0.9)` for several view sheets, but actual file content shows `0.95` from prior round. This is not a deviation—the plan's correction section explicitly notes to "check current state first" rather than blindly following the table. The 0.95 value is functionally correct (95% Forui cap + 90%-95% internal = ~85-90% usable height, both achieve the goal).

## Blockers Encountered

None

## Implementation Notes

### Correction #1: mainAxisMaxRatio Parameter

#### Why the `?? (9 / 16)` Fallback Is Critical

Dart's default parameter values only apply when an argument is **omitted**, not when explicitly passed as `null`. If we forwarded `mainAxisMaxRatio: mainAxisMaxRatio` without the fallback, every call site that doesn't pass this parameter would send `null` to Forui's `showFSheet`. Per Forui's render logic, `null` means **uncapped height** (not "use default"), which would break all ~136 existing call sites.

The fallback ensures: `null` (from omitted parameter) → `9 / 16` (explicit value) → Forui applies 9/16 cap → existing behavior preserved.

### Correction #2: useSafeArea Parameter Forwarding

#### Why This Was Needed

The `useSafeArea` parameter was already declared in `showAppBottomSheet()` signature but never forwarded to `showFSheet()`. This dead code meant sheets could never opt-in to safe area handling, causing header/status bar collisions on notched devices (iPhone with Dynamic Island, etc.) when using full screen height (`mainAxisMaxRatio: 1.0`).

#### How Forui Handles useSafeArea

For `FLayout.btt` (bottom-to-top sheets):

- **`useSafeArea: true`** — Wraps content in `SafeArea(bottom: false)`, adding top padding equal to status bar + notch/Dynamic Island height (~47-59pt on notched iPhones)
- **`useSafeArea: false`** — Actively strips top padding via `MediaQuery.removePadding(removeTop: true)`

This means downstream code cannot compensate by reading `MediaQuery.of(context).padding.top`—Forui explicitly removes it from the context.

#### Interaction with Internal Container Constraints

The SafeArea padding is applied **inside** the sheet's allocated space, not outside it. This composes correctly with internal `Container(maxHeight: ...)` constraints:

1. Forui's sheet render object applies `mainAxisMaxRatio` as a hard `BoxConstraints.maxHeight` on the sheet root
2. SafeArea adds top padding inside the allocated space
3. Internal Container evaluates downstream, within the SafeArea padding

**Example (edit sheet, mainAxisMaxRatio: 1.0):**

- iPhone 14 Pro: 844pt tall screen, 59pt top safe area inset (with Dynamic Island)
- Sheet total height: 844pt (full screen)
- SafeArea top padding: 59pt
- Usable content area: 844pt - 59pt = 785pt
- Header starts 59pt from top, avoiding collision

**No changes to internal Container constraints were needed**—SafeArea padding composes correctly with existing maxHeight values.

### Blast Radius: Shared Component Modified

`app_bottom_sheet.dart` is used by 40+ sheets across the app (145 call sites in 43 files). While the change is additive (new optional parameter), any shared utility modification carries elevated regression risk. Only 5 call sites opt-in to new behavior; the other ~136 must continue working identically.

### Two-Level Height Control

Final sheet height is now controlled at two levels:

1. **Forui ancestor constraint** (via `mainAxisMaxRatio` parameter to `showFSheet`): sets maximum available height
2. **Internal `Container(maxHeight: ...)` constraint**: can tighten further within available space

Example: `mainAxisMaxRatio: 0.95` + internal `maxHeight: 0.9` = ~85% usable height (0.95 × 0.9 ≈ 0.855).

### showModalBottomSheet vs showAppBottomSheet

Two view sheets (`view_rehearsal_drawer.dart`, `view_block_out_drawer.dart`) use Flutter's native `showModalBottomSheet(isScrollControlled: true)` directly, not `showAppBottomSheet`. Per scope exclusion, we did NOT migrate them to the shared wrapper—only adjusted their internal `maxHeight` constraints. This pre-existing inconsistency remains.

## Ready For QA

**No** — Visual verification required

**Reason:** Both corrections address root causes in the shared `app_bottom_sheet.dart` component and must be visually verified on device before approval. The previous Engineer round was approved based on code review alone, which failed to detect that changes had no visible effect.

**QA Requirements:**

### 1. Visual Height Measurement (Correction #1)

Test on all platforms (iOS, Android, macOS, Web):

- **View sheets:** Confirm visible increase from ~56% to ~85-90% screen height
  - View Gig (with all optional fields filled)
  - View Band Member (with all fields filled)
  - View Contact (with all fields filled)
  - Measure using screenshot rulers or visual estimation
- **Edit sheets:** Confirm full screen height (not capped at 56%)
  - Edit Gig drawer
  - Edit Block Out drawer

### 2. Safe Area Handling (Correction #2)

Test on **notched devices** (iPhone with Dynamic Island or similar):

- **Edit sheets (mandatory—bug was visible here):**
  - Edit Gig: Confirm title/close button no longer overlap status bar
  - Edit Block Out: Confirm title/close button no longer overlap status bar
- **View sheets (defense-in-depth):**
  - View Gig, View Band Member, View Contact: Confirm headers respect safe area

- **Non-notched devices:** Verify no unintended extra padding on devices with standard status bars

### 3. Regression Testing (Shared Component Safety)

Test 3-5 representative sheets from other features to confirm no behavioral changes:

- Setlist picker
- Song notes drawer
- Key picker
- Gig notes sheet
- Calendar subscription dialog

All should still render at expected compact height (~56%) without safe area padding.

### 4. Cross-Platform Verification

- iOS: iPhone with Dynamic Island (for safe area testing)
- Android: Standard device
- macOS: Desktop mode
- Web: Browser

All sheets must render correctly on all platforms—constraint behavior may differ per platform.

### 5. Edge Cases

- View sheets with minimal content (should not be artificially tall)
- Edit sheets with keyboard visible (verify no inputs obscured)
- Dynamic Island in active/expanded states (taller than base state)
- Drag-to-dismiss gesture (verify still works on all sheets)
  - Confirm they still render at expected compact height (~56%)

3. **Functional testing**
   - Contact → View drawer → Edit flow
   - Venue back button navigation
   - Keyboard doesn't obscure inputs in edit sheets
   - All footer buttons accessible without scrolling in view sheets
4. **Edge cases**
   - Minimal content (shouldn't be artificially tall)
   - Maximum content (all optional fields filled)
   - Multi-date gigs with expenses expanded

**Known constraint:** This report documents code inspection only. I cannot perform visual verification without access to a running device or browser instance. QA must visually confirm on hardware before marking ready for production.

---

## Summary

This implementation corrects the root cause identified after the previous round failed visual testing. The binding constraint was Forui's `showFSheet` default `mainAxisMaxRatio: 9/16` applied at the ancestor level, not the individual drawer internal `Container(maxHeight: ...)` constraints. By adding the parameter to `showAppBottomSheet()` with a safe fallback and updating 5 call sites to opt-in, the feature now addresses the actual limitation. All analyzer checks pass. Visual verification on device is mandatory before QA approval.
