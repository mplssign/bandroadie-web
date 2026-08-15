# QA Report

## Feature Slug

`feature/detail-sheet-sizing-venue-back`

## Feature Title

Detail Sheet Sizing & Venue Back Button (Root Cause Corrected)

## Final Verdict

**APPROVED-PENDING-VISUAL-CONFIRMATION**

## Validation Summary

Code review confirms the root cause fix is correctly implemented: `showAppBottomSheet()` now forwards `mainAxisMaxRatio` with explicit `?? (9 / 16)` fallback (NOT a bare pass-through). All 5 target call sites correctly pass either `0.95` (view sheets) or `1.0` (edit sheets). Flutter analyze passes (0 errors, 8 pre-existing warnings unrelated to this work). However, given this project's known device/browser access constraints AND the history of the previous round being approved on code review alone yet having zero visible effect, this verdict explicitly requires visual confirmation on actual hardware before production deployment.

## Architect Scope Review

- **Scope adherence:** Compliant
- **Files modified:** As expected (9 modified + 1 created)
- **Files off-limits:** Not touched (band_member_edit_drawer.dart confirmed untouched)
- **Deviations:** None

## Completeness Check

- **All Architect tasks implemented:** Yes
- **Missing tasks:** None

All tasks from the corrected Architect plan completed:

1. ✅ Added `mainAxisMaxRatio` parameter to `app_bottom_sheet.dart` with mandatory `?? (9 / 16)` fallback
2. ✅ Updated 3 view sheet call sites to pass `mainAxisMaxRatio: 0.95`
3. ✅ Updated 2 edit sheet call sites to pass `mainAxisMaxRatio: 1.0`
4. ✅ Updated 2 `showModalBottomSheet` files' internal constraints (0.9 → 0.95)
5. ✅ Created `ContactDetailDrawer` following `BandMemberDetailDrawer` pattern
6. ✅ Wired ContactDetailDrawer into `contacts_view.dart`
7. ✅ Added back button to VenueDetailScreen

## Behavior Verification

- **Validation method:** Code-path analysis only (no device/browser access available)
- **Result:** Code changes match expected implementation from Architect plan
- **Visual verification status:** **NOT PERFORMED** — Cannot be performed in this environment

### What Was Verified by Code Inspection

**Critical Implementation Detail (Primary Focus):**

- ✅ **Confirmed:** [app_bottom_sheet.dart](lib/components/ui/app_bottom_sheet.dart) line 38 uses `mainAxisMaxRatio: mainAxisMaxRatio ?? (9 / 16)` — an **explicit fallback**, NOT `mainAxisMaxRatio: mainAxisMaxRatio` bare pass-through
- ✅ This is the exact fix that was caught and corrected after the first round; verified it remains correct and was not reverted

**Parameter Forwarding:**

- ✅ New `double? mainAxisMaxRatio` parameter added to function signature (line 27)
- ✅ Forwarded to Forui's `showFSheet()` with `?? (9 / 16)` fallback preserving backward compatibility
- ✅ Documentation added explaining parameter purpose (lines 12-14)

**Call Site Updates (5 files):**

- ✅ [view_gig_drawer.dart](lib/features/gigs/widgets/view_gig_drawer.dart) line 45: `mainAxisMaxRatio: 0.95` ✓
- ✅ [band_member_detail_drawer.dart](lib/features/contacts/widgets/band_member_detail_drawer.dart) line 42: `mainAxisMaxRatio: 0.95` ✓
- ✅ [contact_detail_drawer.dart](lib/features/contacts/widgets/contact_detail_drawer.dart) line 36: `mainAxisMaxRatio: 0.95` ✓
- ✅ [add_edit_event_bottom_sheet.dart](lib/features/events/widgets/add_edit_event_bottom_sheet.dart) line 67: `mainAxisMaxRatio: 1.0` ✓
- ✅ [add_block_out_drawer.dart](lib/features/calendar/widgets/add_block_out_drawer.dart) line 92: `mainAxisMaxRatio: 1.0` ✓

**Internal Constraint Updates (2 files using showModalBottomSheet):**

- ✅ [view_rehearsal_drawer.dart](lib/features/rehearsals/widgets/view_rehearsal_drawer.dart) line 147: `maxHeight: 0.95` ✓
- ✅ [view_block_out_drawer.dart](lib/features/calendar/widgets/view_block_out_drawer.dart) line 74: `maxHeight: 0.95` ✓

**New Contact Drawer:**

- ✅ [contact_detail_drawer.dart](lib/features/contacts/widgets/contact_detail_drawer.dart) created following BandMemberDetailDrawer pattern
- ✅ Phone/email tap handlers with url_launcher integration
- ✅ Conditional field display logic
- ✅ Done/Edit footer buttons
- ✅ Wired into [contacts_view.dart](lib/features/contacts/widgets/contacts_view.dart) lines 120 and 168

**Venue Back Button:**

- ✅ [venue_detail_screen.dart](lib/features/contacts/widgets/venue_detail_screen.dart) line 38-41: AppIconButton with AppIcons.back added to AppAppBar `leading`

**Backward Compatibility (Sanity Check):**

- ✅ Inspected example unchanged call site: [song_notes_drawer.dart](lib/features/setlists/widgets/song_notes_drawer.dart) line 28
- ✅ Calls `showAppBottomSheet` without `mainAxisMaxRatio` parameter
- ✅ By code inspection: parameter defaults to `null`, fallback provides `9 / 16` to Forui, preserving existing ~56% height behavior
- ✅ Conclusion: All ~12 other call sites that don't pass the new parameter will continue to work identically

### What Was NOT Verified (Device/Visual Testing Required)

**Cannot verify without running device or browser:**

- ❌ Actual visible sheet height changes on screen
- ❌ View sheets increased from ~56% to ~85-90% (visual measurement required)
- ❌ Edit sheets increased to full screen height (visual measurement required)
- ❌ Keyboard interaction in edit sheets (doesn't obscure focused inputs)
- ❌ Regression testing on other sheets (setlist picker, song notes, key picker, gig notes)
- ❌ Cross-platform behavior (iOS, Android, macOS, Web)
- ❌ Safe area handling on notched devices
- ❌ Drag-to-dismiss gesture functionality
- ❌ Contact → View drawer → Edit flow
- ❌ Venue back button navigation

**Why Visual Confirmation Is Mandatory This Time:**

The previous implementation round was approved based on code review alone (similar to what I'm doing now) and turned out to have **zero visible effect** at runtime. The Architect plan's correction section documents this failure mode explicitly. While the code changes in this round address the actual root cause that was missed before, **code review alone cannot verify that constraint precedence behaves as expected at runtime**. Visual device testing is the only way to confirm:

1. Forui's render object actually respects the forwarded `mainAxisMaxRatio` parameter
2. Constraint tightening happens in the expected order (ancestor before descendant)
3. No platform-specific edge cases interfere with the fix

## Regression Check

- **Risk level:** HIGH
- **Systems reviewed:** Gigs, Rehearsals, Setlists, Members, Contacts, Calendar, Shared UI Components
- **Regressions found (code level):** None detected by code inspection

**Rationale for HIGH risk:**

While the change is additive-only (new optional parameter with safe default), the shared component `app_bottom_sheet.dart` is used by 17 call sites across 16 files (see correction below). Any modification to a shared utility carries elevated risk. The explicit `?? (9 / 16)` fallback is critical to preventing regression — without it, all unchanged call sites would silently receive `null` instead of `9 / 16`, causing uncapped height and layout breakage across the app.

**Mitigations verified by code inspection:**

- ✅ Safe default preserved via `?? (9 / 16)` fallback
- ✅ Only 5 call sites opt-in to new behavior (17 call sites total minus 5 = 12 unchanged)
- ✅ No existing code paths altered except those explicitly passing the new parameter
- ✅ No database, auth, or session interaction

**Regression areas requiring visual verification:**

- Other sheets must render at existing height (setlist picker, song notes, key picker, gig notes, calendar subscription dialog)
- Target sheets must show visible height increase
- Keyboard interaction must work correctly in edit sheets
- All platforms (iOS, Android, macOS, Web)

## Database Safety

Not applicable — UI-only changes, no database interaction.

## Analyzer Results

**Command:** `flutter analyze`  
**Result:** 0 errors, 8 warnings (all pre-existing, unrelated to this implementation)

**Pre-existing warnings (not introduced by this feature):**

- `bulk_entry_screen.dart`: unused import, unused variable, async context
- `original_song_screen.dart`: async context
- `app_text_field_test.dart`: unused variables (test file)
- `app_text_form_field_test.dart`: unused variable (test file)

**Conclusion:** No new warnings or errors introduced.

## Test Results

Not run — no test coverage exists for bottom sheet height constraints. Manual visual verification required.

## Diff Safety Review

- **Secrets:** None found ✓
- **Debug artifacts:** None found in source code ✓
- **Unrelated changes:** None in tracked files ✓
- **Accidental file deletions:** None ✓
- **Test scaffolding in production code:** None ✓

**Stray untracked files flagged (should not be committed):**

1. ⚠️ `analyzer-output.txt` (1.8K) — Debug artifact, not part of feature scope
2. ⚠️ `docs/reference/audits/CODEBASE_AUDIT_2026-08-14.md` (23K) — Separate audit document, not part of feature scope

These files appear in `git status` as untracked but should not be included in the feature commit.

## Issues Found

### Critical (must fix before production deployment)

None at code level. **However:**

**BLOCKING REQUIREMENT: Visual Verification**

Given the project history (previous round approved on code review alone, zero visible effect at runtime), this implementation **MUST be visually verified on actual hardware** before production deployment. Specifically:

1. **Measure actual sheet heights** on device (not simulated) for all modified sheets
2. **Confirm visible height increase** from previous ~56% cap
3. **Test keyboard interaction** in edit sheets (no input obscuring)
4. **Regression test** 3-5 representative unchanged sheets (setlist picker, song notes, key picker, gig notes, calendar dialogs)
5. **Test all platforms:** iOS, Android, macOS, Web

The code changes are correct by inspection, but constraint precedence behavior must be confirmed at runtime.

### Warnings (should fix)

None.

### Corrections for Record

**Call Site Count:**

The Engineer's report states: _"shared component used by 40+ sheets (145 call sites in 43 files)"_

**Actual count via direct grep:**

```bash
grep -r "showAppBottomSheet" lib --include="*.dart" | wc -l
# Result: 18 total occurrences (1 definition + 17 call sites)

grep -r "showAppBottomSheet" lib --include="*.dart" -l | wc -l
# Result: 17 files (16 with call sites + 1 definition file)
```

**Corrected figure:** 17 call sites in 16 files

This does not affect the fix's correctness or scope (all 5 target call sites were correctly updated), but the inflated figure should not be repeated. The blast radius is lower than originally stated, though still significant for a shared component.

### Suggestions (optional)

**Consider adding to .gitignore (if not already present):**

- `analyzer-output.txt` — Debug artifact pattern
- `docs/reference/audits/CODEBASE_AUDIT_*.md` — Audit documents should likely be tracked separately or have their own commit workflow

---

## QA Verification Performed

### Environment Constraints

This QA review was performed in an AI coding environment with the following limitations:

- **No device access:** Cannot run iOS, Android, or macOS simulator/device
- **No browser access:** Cannot run or interact with Web build
- **No visual verification capability:** Cannot measure actual sheet heights or test UI interactions

### What This QA Review Validated

✅ **Code correctness** — All changes match Architect plan exactly  
✅ **Critical implementation detail** — `mainAxisMaxRatio` forwarding uses explicit fallback, NOT bare pass-through  
✅ **Backward compatibility by inspection** — Fallback preserves existing behavior for unchanged call sites  
✅ **Scope adherence** — Only approved files modified, off-limits files untouched  
✅ **Completeness** — All Architect tasks completed  
✅ **Analyzer compliance** — 0 errors, no new warnings  
✅ **Diff safety** — No secrets, debug artifacts, or unrelated changes

### What This QA Review Could NOT Validate

❌ **Visual/runtime behavior** — Actual sheet heights on screen  
❌ **Constraint precedence** — Whether Forui's render object applies `mainAxisMaxRatio` as expected  
❌ **Keyboard interaction** — Whether edit sheets handle keyboard correctly  
❌ **Regression impact** — Whether other sheets still render correctly  
❌ **Platform-specific behavior** — Cross-platform constraint handling

---

## Verdict Rationale

**Why APPROVED-PENDING-VISUAL-CONFIRMATION (not bare APPROVED):**

The code implementation is correct and complete by inspection. The critical defect from the previous round (bare pass-through that would have broken backward compatibility) is not present — the implementation correctly uses `mainAxisMaxRatio: mainAxisMaxRatio ?? (9 / 16)` with an explicit fallback.

However, the project history shows that code review alone is insufficient for this type of constraint-based layout fix. The previous Engineer round was approved based on code review and failed visual testing with zero visible effect. While this round addresses the actual root cause (Forui's `showFSheet` default), the only way to confirm constraint precedence behaves as documented is to **see the sheets render on actual hardware**.

**This is a code-level approval with mandatory visual verification gate before production deployment.**

Tony must perform visual testing per the Architect's verification plan (all platforms, measure heights, test keyboard, regression check representative sheets) before this ships. If visual testing reveals issues, the verdict would change to REQUIRES CHANGES.

---

## QA Report Metadata

- **QA Agent:** GitHub Copilot (Claude Sonnet 4.5)
- **Date:** 2026-08-14
- **Branch:** `feature/detail-sheet-sizing-venue-back`
- **Commit State:** Working tree has unstaged changes (git diff reviewed)
- **Next Step:** Visual verification on device required before production deployment
