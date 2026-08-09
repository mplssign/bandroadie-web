# QA Report

## Feature Slug

`bug/song-lookup-keyboard-scroll-blocked-v2`

---

## Feature Title

Fix Song Lookup Overlay Keyboard Scroll Blocking (v2 — Second Attempt)

---

## Final Verdict

**APPROVED** _(with mandatory device testing required before merge — see Device Testing section)_

---

## Validation Summary

Reviewed implementation against Architect plan via code-path analysis. The fix correctly addresses the root cause identified in the Architect plan: the previous fix (PR #134) only toggled a 16px margin instead of consuming the actual keyboard height (~336px). This implementation adds a `Padding(bottom: keyboardHeight)` widget that constrains the scrollable ListView viewport by the actual keyboard height from `MediaQuery.of(context).viewInsets.bottom`, forcing the list to end above the keyboard rather than extending underneath it. All Architect tasks completed, `flutter analyze` passes with 0 errors, diff is clean, and no regressions detected in code analysis.

**Critical context:** This is the second attempt at this exact bug. PR #134 passed code review, analyzer, and QA code-path analysis but **failed device testing** — it only toggled 16px instead of consuming the actual keyboard height. This QA review validates correctness via code reading, but **device testing is non-negotiable** before merge.

---

## Architect Scope Review

- **Scope adherence:** Compliant
- **Files modified:** As expected — only `lib/features/setlists/widgets/song_lookup_overlay.dart`
- **Files off-limits:** Not touched — all 8 files with the same unverified pattern remain unchanged as required

---

## Completeness Check

- **All Architect tasks implemented:** Yes
- **Missing tasks:** None

**Task verification:**

1. ✅ Modified `build()` method in `song_lookup_overlay.dart`
   - Container margin simplified from conditional `EdgeInsets.fromLTRB(...)` to uniform `const EdgeInsets.all(Spacing.space16)`
   - Added `Padding(padding: EdgeInsets.only(bottom: keyboardHeight))` wrapping ClipRRect
   - SafeArea bottom toggle preserved (defensive code)
   - Outdated comment removed
2. ✅ Verified `flutter analyze` passes — confirmed 0 errors
3. ✅ Generated `git diff` — confirmed only expected changes
4. ✅ Created `ENGINEER_REPORT.md` — complete and accurate

---

## Behavior Verification

**Validation method:** Code-path analysis only (device testing not performed by QA)

**Result:** Matches expected behavior based on code structure

### Root Cause Addressed

**Previous fix (PR #134) failure mode:**

- Read `keyboardHeight` from `viewInsets.bottom` (e.g., 336px) ✅
- Used it only as boolean condition to toggle SafeArea and margin ❌
- Changed Container bottom margin from 16px → 0px when keyboard up ❌
- Container remained unconstrained — expanded to fill SafeArea/Material/screen ❌
- ListView viewport extended 336px underneath keyboard ❌
- Removing 16px margin had no effect against 336px keyboard obstruction ❌

**Current fix approach:**

- Reads `keyboardHeight` from `viewInsets.bottom` (e.g., 336px) ✅
- Wraps content in `Padding(bottom: keyboardHeight)` ✅
- Padding shrinks Column's available height by actual keyboard dimension ✅
- Expanded ListView constrained to viewport that ends above keyboard ✅
- Container margin now uniform 16px (simplified from conditional toggle) ✅

### Layout Trace (Keyboard Up — 336px)

Assuming iPhone 12 (844px screen height):

```
Screen: 0 to 844px
Keyboard: covers 508px to 844px (336px tall)

Material (transparent): fills screen 0 to 844px
└─ SafeArea (bottom: false): 0 to 844px
   └─ Container (margin: 16px all sides)
      ├─ Outer bounds: 0 to 844px
      ├─ Inner bounds (decoration + child): 16px to 828px
      └─ Padding (bottom: 336px)
         └─ Child (ClipRRect → Column → ListView): 16px to 492px
```

**Result:** ListView viewport ends at y=492px, keyboard top is at y=508px. The 16px gap (492 to 508) is the Container's bottom margin showing the background Material. The scrollable list is entirely above the keyboard.

### Why This Should Work (Unlike PR #134)

PR #134 failed because it only removed 16px of spacing — a cosmetic change against a 336px obstruction. This fix directly consumes the keyboard height as a layout constraint. The Padding widget forces the Column (and thus the Expanded ListView) to fit within reduced vertical space. The ListView's viewport cannot extend underneath the keyboard because its parent container is explicitly constrained by the keyboard dimension.

This is the standard Flutter pattern for keyboard avoidance in custom dialogs.

### Confidence Level

**Code structure is correct.** The layout math validates. The pattern is standard Flutter.

**However:** The previous fix also "looked correct" in code review and passed static analysis. It only failed when tested on a real device. For this specific bug class (keyboard interaction, viewport calculation, iOS-specific behavior), code-path analysis is necessary but not sufficient.

**Honest assessment:** I am confident this fix addresses the root cause, but I have not exercised the runtime behavior. Device testing is required to confirm the keyboard height is correctly applied and the ListView scrolls as expected.

---

## Regression Check

**Risk level:** LOW

**Systems reviewed:**

| System             | Risk Assessment                                                               |
| ------------------ | ----------------------------------------------------------------------------- |
| Gigs               | No changes — unaffected                                                       |
| Rehearsals         | No changes — unaffected                                                       |
| Setlists / Catalog | **Modified** — Song Lookup overlay layout changed; no business logic affected |
| Members / RBAC     | No changes — unaffected                                                       |
| Auth / Session     | No changes — unaffected                                                       |
| Routing            | No changes — unaffected                                                       |
| Notifications      | No changes — unaffected                                                       |

**Regressions found:** None detected in code analysis

### Regression Risk Rationale

- Single file modified (`song_lookup_overlay.dart`)
- No database, auth, routing, or initialization order changes
- No shared state or cross-feature mutations
- Pure layout fix — no business logic changes
- Standard Flutter pattern (Padding with MediaQuery viewInsets)
- No new dependencies or abstractions introduced
- No FocusNode, TextEditingController, or ScrollController disposal changes
- No setState after async gaps
- No rebuild frequency changes

### Edge Cases Reviewed

1. **Keyboard dismissed while overlay open:** `keyboardHeight` → 0, `Padding(bottom: 0)` — no visual change, layout reflows smoothly ✅
2. **SafeArea toggle interaction:** SafeArea bottom disabled when keyboard up (defensive code, does not conflict with Padding approach) ✅
3. **Container margin consistency:** Now uniform 16px all sides (previously conditional bottom margin) — simpler, no visual regression ✅
4. **ClipRRect interaction:** Padding wraps ClipRRect (not inside it) — clipping behavior unchanged ✅
5. **Rotation (portrait ↔ landscape):** `viewInsets.bottom` updates automatically, Padding adjusts — should handle correctly (requires device testing to confirm) ⚠️

---

## Database Safety

**Not applicable** — pure client-side UI layout fix with no database, Supabase, RPC, or migration changes.

---

## Analyzer Results

**Command:** `flutter analyze`  
**Result:** 0 errors, 0 warnings

**Output:**

```
Analyzing bandroadie...
No issues found! (ran in 5.6s)
```

No issues introduced by this change.

---

## Test Results

**Not run** — no test coverage exists for `song_lookup_overlay.dart`. The Architect plan does not require unit tests for this UI layout fix. Device testing is the required verification method.

---

## Diff Safety Review

**Secrets:** None found ✅  
**API keys:** None found ✅  
**Debug artifacts:** None found ✅

- No `print()` statements
- No `TODO` comments
- No temporary flags
- No test scaffolding in production code

**Unrelated changes:** None found ✅

- Diff shows only expected changes to `build()` method
- No formatting-only churn
- No accidental file deletions
- No changes to imports, class structure, or other methods

**Diff summary:**

- Lines 358-363: Container margin simplified (conditional → uniform)
- Lines 364-375: Padding widget added wrapping ClipRRect
- Total: 14 lines changed (8 removed, 14 added, net +6 lines)

---

## Device Testing Requirement

### ⚠️ MANDATORY PRE-MERGE VERIFICATION ⚠️

This fix **MUST be tested on a real iPhone** (or iPhone simulator with software keyboard) before merge. Code-path analysis is not sufficient for this bug class.

**Why device testing is non-negotiable:**

1. **Historical precedent:** PR #134 passed code review and QA code-path analysis but failed device testing. It only toggled 16px instead of consuming the actual keyboard height. The bug was only detectable at runtime.

2. **Platform-specific behavior:** Keyboard interaction on iOS involves system-level APIs (`MediaQuery.viewInsets.bottom`), viewport calculations, and touch scrolling behavior that cannot be fully validated via static analysis.

3. **Architect plan requirement:** The verification plan explicitly requires device testing with specific test cases (see below).

### Required Test Procedure

**Platform:** iPhone (physical device or Xcode simulator with software keyboard enabled)

**Test case 1 — Primary bug verification:**

1. Build and deploy app to iPhone
2. Navigate to any setlist (e.g., "Catalog" or a show setlist)
3. Tap "Add Song" → Song Lookup overlay appears
4. Verify search field auto-focuses and keyboard appears (~336px tall)
5. Type search query returning 10+ results (e.g., "the")
6. **Critical test:** Attempt to scroll the results list while keyboard is visible
7. **Expected:** Results list scrolls smoothly, bottom items are accessible
8. **Previous bug (PR #134):** Results list does not scroll, or bottom items remain hidden under keyboard

**Test case 2 — Keyboard dismissal:**

9. Dismiss keyboard (swipe down or tap outside search field on iOS 15+)
10. Verify results list scrolls normally
11. Verify overlay margins remain consistent (16px on all sides, no visual glitch)

**Test case 3 — Edge cases:**

12. Rotate device (portrait ↔ landscape) with keyboard up — verify layout adjusts correctly
13. Test on iPhone with home indicator (e.g., iPhone 12+) — verify SafeArea handling
14. Test on iPhone without home indicator (e.g., iPhone SE) — verify no bottom gap issue
15. Rapidly show/hide keyboard — verify no flicker or layout thrashing

**Test case 4 — End-to-end functionality:**

16. Search for catalog song → tap to add → verify success message
17. Search for external song → tap to add → verify enrichment review flow
18. Verify duplicate detection works correctly
19. Verify search debouncing (250ms delay) works as expected

### QA Confidence Statement

**What I verified:**

- ✅ Implementation matches Architect plan
- ✅ Root cause correctly addressed in code structure
- ✅ Layout math validates (Padding constrains viewport by keyboard height)
- ✅ Standard Flutter pattern applied correctly
- ✅ No regressions in code analysis
- ✅ Clean diff, no artifacts or secrets
- ✅ Analyzer passes

**What I did NOT verify:**

- ❌ Runtime behavior on iPhone
- ❌ Actual keyboard height consumption
- ❌ Scroll gesture behavior with keyboard visible
- ❌ Layout reflow on keyboard show/hide
- ❌ Rotation handling with keyboard up
- ❌ Cross-platform behavior (Android, Web, macOS)

**Verdict rationale:**

I am marking this **APPROVED** because the implementation is correct in code structure, matches the Architect plan, and addresses the identified root cause. The fix uses the standard Flutter pattern for keyboard avoidance and should resolve the bug.

However, **"should work" based on code reading is not the same as "confirmed working" via device testing.** PR #134 taught us this lesson. The code looked correct, passed review, and failed on a real device.

**This approval is contingent on successful device testing.** Do not merge until Test Case 1 (steps 1-8 above) is confirmed passing on a physical iPhone or simulator.

---

## Issues Found

### Critical (must fix before merge)

**None** — pending device testing

### Warnings (should fix)

**None**

### Suggestions (optional)

**None**

---

## Additional Context

### Files With Same Pattern (Out of Scope)

The following 8 files use the same flawed 16px-margin toggle pattern from PR #134:

1. `lib/features/setlists/widgets/bulk_add_songs_overlay.dart`
2. `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
3. `lib/features/setlists/widgets/song_enrichment_review_sheet.dart`
4. `lib/features/setlists/widgets/custom_tuning_modal.dart`
5. `lib/features/gigs/widgets/pause_creator.dart`
6. `lib/features/gigs/widgets/set_break_creator.dart`
7. `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`
8. `lib/features/songs/widgets/song_notes_drawer.dart`

These were explicitly marked **off-limits** in the Architect plan. They require individual device testing to confirm the bug exists in each context and will be addressed in a separate future ticket if validated.

**QA verified:** None of these files were modified ✅

### Architectural Pattern Established

If device testing confirms this fix works, the `Padding(bottom: MediaQuery.of(context).viewInsets.bottom)` pattern should be applied to the 8 files listed above (after individual validation). The 16px-margin toggle approach is ineffective for keyboard avoidance.

---

## QA Sign-Off

**QA Agent:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-08-08  
**Validation Method:** Code-path analysis + static analysis  
**Architect Plan Version:** `ARCHITECT_PLAN.md` (song-lookup-keyboard-scroll-blocked-v2)  
**Engineer Report Version:** `ENGINEER_REPORT.md` (song-lookup-keyboard-scroll-blocked-v2)

**Final Statement:**

Implementation is correct and ready for device testing. The fix directly addresses the root cause that caused PR #134 to fail. Merge only after confirming Test Case 1 (keyboard scrolling) passes on a real iPhone.

---

**END OF QA_REPORT.md**
