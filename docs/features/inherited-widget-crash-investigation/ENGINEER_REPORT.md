# Engineer Report

## Feature Slug

`bug/inherited-widget-crash-investigation`

---

## Branch

`bug/inherited-widget-crash-investigation`

---

## Phase Implemented

**Phase 5 — WheelCalendar Negative-Width Root Cause Analysis & Fix**

---

## Summary of Work

Implemented the constraint clamp fix in `calendar_grid.dart` to prevent the WheelCalendar `BoxConstraints` negative-width exception that has been contaminating all logout testing since the investigation began.

### Changes Applied

**File Modified:** `lib/features/calendar/widgets/calendar_grid.dart`

**Line 41 — Before:**

```dart
final availableWidth = constraints.maxWidth - 24;
```

**Line 41 — After:**

```dart
// Clamp to 0 minimum to prevent negative width when drawer overlay restricts constraints
final availableWidth = (constraints.maxWidth - 24).clamp(0.0, double.infinity);
```

**Total Footprint:**

- 1 file modified
- 1 line changed (wrapped in `.clamp()`)
- 1 inline comment added (explaining why clamp is required)
- 0 lines deleted
- 0 new imports required

**Git Diff:**

```diff
diff --git a/lib/features/calendar/widgets/calendar_grid.dart b/lib/features/calendar/widgets/calendar_grid.dart
index 0b5307a..238e275 100644
--- a/lib/features/calendar/widgets/calendar_grid.dart
+++ b/lib/features/calendar/widgets/calendar_grid.dart
@@ -38,7 +38,8 @@ class CalendarGrid extends StatelessWidget {
       builder: (context, constraints) {
         // Compute responsive day cell size to fill container width
         // Subtract FCalendar's internal horizontal padding (12px left + 12px right = 24px total)
-        final availableWidth = constraints.maxWidth - 24;
+        // Clamp to 0 minimum to prevent negative width when drawer overlay restricts constraints
+        final availableWidth = (constraints.maxWidth - 24).clamp(0.0, double.infinity);
         final cellWidth = availableWidth / 7;
```

---

## Validation — Static Analysis

**Command:** `flutter analyze`

**Result:** ✅ **PASS** — 0 errors

**Output:** Analyzer completed successfully with 10 pre-existing warnings in unrelated files (bulk_entry_screen.dart, song_card.dart, test files). Zero new warnings or errors introduced by the `calendar_grid.dart` change.

**Conclusion:** Code change is syntactically correct, compiles cleanly, and passes all static analysis checks.

---

## Validation — On-Device Testing

### Device Testing Status: ❌ **BLOCKED — REQUIRES MANUAL TESTING BY TONY**

**Attempted Platform:** iOS physical device (`00008150-00026D523490C01C` - "Tonys iPhone")

**Command Executed (2 attempts):**

```bash
./run.sh 00008150-00026D523490C01C 2>&1 | tee ~/Desktop/phase5_wheelcalendar_fix.log
```

**Result:** Both attempts stalled during the build/deployment phase with output stuck at:

```
Launching lib/main.dart on Tonys iPhone (wireless) in debug mode...
```

**Root Cause:** Wireless iOS debugging from this environment is non-functional. The terminal shows the launch message but never progresses to build completion or app deployment.

**Impact:** Cannot verify TEST 1–4 from the Architect Plan's Verification Plan in Phase 5.

---

## Outstanding Validation — Manual Testing Required

The following tests from **Phase 5 Engineer Task Breakdown > Task 2** must be performed manually by Tony on the physical iOS device before this fix can pass QA:

### TEST 1 — WheelCalendar Exception Resolution (PRIMARY FIX VALIDATION)

**Critical Update from Manager Gate Review:**  
TEST 1 pass criterion is **"zero exceptions or assertions of any kind in the console during drawer open/close"**, NOT just checking for the specific `BoxConstraints has a negative minimum width` message. If a _different_ exception appears after the fix, treat TEST 1 as failed and report it.

**Steps:**

1. Build and deploy: `./run.sh 00008150-00026D523490C01C 2>&1 | tee ~/Desktop/phase5_wheelcalendar_fix.log`
2. Log in (magic link)
3. Navigate to **Home tab**
4. Open side drawer (tap menu icon)
5. **OBSERVE:** Drawer opens smoothly
6. **VERIFY:** Console shows **ZERO exceptions or assertions of any kind**
7. Close drawer via X button (do NOT tap Log Out yet)
8. Repeat open/close 3 times

**Pass Criteria:** Zero exceptions during drawer open/close. Console output completely clean.

**If TEST 1 FAILS:** The clamp fix is insufficient or incorrect. Do not proceed to TEST 2. Report exact exception signature and investigate further.

---

### TEST 2 — Logout Crash Status (DECISIVE TEST)

**Only proceed if TEST 1 passes.**

**Steps:**

1. With app running, navigate to Home tab
2. Open side drawer
3. Tap "Log Out"
4. **OBSERVE:** Drawer closes, user redirected to LoginScreen
5. **VERIFY:** Check console for **any** exceptions or assertions

**Expected Outcome A — `_dependents.isEmpty` Crash Resolved:**

- Logout completes successfully
- User redirected to LoginScreen
- Console shows **no exceptions, no assertions**
- **Conclusion:** WheelCalendar exception was corrupting Element state → `_dependents.isEmpty` crash was downstream symptom, now fixed
- **Next Steps:** Proceed to TEST 3–4, then QA approval for merge

**Expected Outcome B — `_dependents.isEmpty` Crash Persists:**

- Logout triggers console error (likely `_dependents.isEmpty` assertion)
- Console shows **one exception only** (NOT the WheelCalendar `BoxConstraints` exception)
- **Conclusion:** WheelCalendar bug and `_dependents.isEmpty` bug are **independent**, unrelated root causes
- **Next Steps:** Document exception signature, QA approval for **WheelCalendar fix only**, defer `_dependents.isEmpty` to Phase 6

**This test is DECISIVE:** It determines whether the two crashes are causally related (Outcome A) or independent (Outcome B).

---

### TEST 3 — Logout from Calendar Tab (SECONDARY VALIDATION)

**Only proceed if TEST 2 shows Outcome A (crash resolved).**

**Steps:**

1. Log in, navigate to **Calendar tab**
2. Open side drawer, tap "Log Out"
3. **VERIFY:** Logout completes successfully (zero exceptions)

**Pass Criteria:** Logout completes with zero exceptions.

---

### TEST 4 — Drawer Operations from Other Tabs (COVERAGE VALIDATION)

**Only proceed if TEST 1–3 pass.**

**Steps:**

1. Open drawer from **Setlists tab** → verify no exceptions
2. Open drawer from **Contacts tab** → verify no exceptions

**Pass Criteria:** Zero exceptions when opening drawer from any tab.

---

### Task 4 — Rehearsal Crash Follow-Up (CONDITIONAL)

**Trigger Condition:** Only execute if TEST 2 shows **Outcome A** (logout crash resolved).

**If TEST 2 shows Outcome B (crash persists):** Skip Task 4 — the rehearsal crash was never definitively linked to this investigation's root cause.

**Steps (If Outcome A):**

1. Navigate to Home tab
2. Open existing rehearsal, tap edit
3. Type in **Location field**
4. **OBSERVE:** Does crash occur while typing?
5. Save rehearsal
6. **OBSERVE:** Does save complete successfully?

**Expected Outcome A1 — Rehearsal Crash Also Resolved:**

- No crash while editing Location field
- Rehearsal saves successfully
- **Conclusion:** Rehearsal crash was also caused by WheelCalendar Element corruption, now fixed
- **Next Steps:** Close `bug/rehearsal-location-edit-crash` branch as resolved

**Expected Outcome A2 — Rehearsal Crash Persists:**

- Crash occurs while editing Location or on save
- **Conclusion:** Rehearsal crash has a **different, undiagnosed root cause**
- **Next Steps:** File new investigation branch for rehearsal crash

---

## Files Modified

| File                                               | Change Type | Lines Added | Lines Deleted | Description                                                                                     |
| -------------------------------------------------- | ----------- | ----------- | ------------- | ----------------------------------------------------------------------------------------------- |
| `lib/features/calendar/widgets/calendar_grid.dart` | Modified    | 1           | 0             | Added `.clamp(0.0, double.infinity)` to `availableWidth` calculation (line 41) + inline comment |

---

## Files Explicitly NOT Modified (Per Architect Plan)

| File                                         | Reason                                                                                   |
| -------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `lib/features/shell/app_shell.dart`          | `IndexedStack` pattern is correct; bug is in constraint handling, not shell architecture |
| `lib/features/home/widgets/side_drawer.dart` | Drawer behavior is correct; Calendar must handle small constraints defensively           |
| `lib/features/auth/auth_state_provider.dart` | Phase 3 fix remains in place (correct, may still be relevant pending TEST 2 outcome)     |
| `lib/features/auth/auth_gate.dart`           | No changes needed unless TEST 2 shows Outcome B                                          |
| `lib/main.dart`                              | Phase 4 diagnostic override already reverted; no further changes needed                  |

---

## Blockers

**BLOCKER: Device deployment non-functional from this environment**

- Wireless iOS debugging stalls during build/deployment
- Two deployment attempts both hung at "Launching lib/main.dart" phase
- No error messages provided — deployment simply stops progressing
- Cannot execute TEST 1–4 without physical device access

**Required Action:** Tony must manually run TEST 1–4 on the physical iOS device using the command:

```bash
./run.sh 00008150-00026D523490C01C 2>&1 | tee ~/Desktop/phase5_wheelcalendar_fix.log
```

---

## Next Steps

### If TEST 1 Passes and TEST 2 Shows Outcome A (Both Crashes Resolved):

1. ✅ Proceed to TEST 3–4 for full coverage validation
2. ✅ Execute Task 4 (rehearsal crash follow-up) to determine if original bug is resolved
3. ✅ Run `flutter analyze` one final time before commit (should continue to pass)
4. ✅ Commit changes with message: `fix(calendar): prevent negative-width BoxConstraints in CalendarGrid when drawer restricts layout`
5. ✅ QA approval for merge to main

### If TEST 1 Passes but TEST 2 Shows Outcome B (WheelCalendar Fixed, Auth Crash Persists):

1. ✅ Proceed to TEST 3–4 to verify WheelCalendar fix is universal
2. ❌ Skip Task 4 (rehearsal crash unrelated)
3. ✅ Document exact `_dependents.isEmpty` exception signature from TEST 2 for Phase 6
4. ✅ Commit WheelCalendar fix with message: `fix(calendar): prevent negative-width BoxConstraints in CalendarGrid (Phase 5 partial resolution)`
5. ✅ QA approval for **WheelCalendar fix only**
6. 🔄 Proceed to Phase 6 investigation for independent `_dependents.isEmpty` crash

### If TEST 1 Fails (Different Exception Appears):

1. ❌ Do NOT proceed to TEST 2–4
2. 🔍 Capture exact exception signature and full stack trace
3. 🔍 Investigate whether clamp produces unexpected behavior in Forui's `FCalendar.wheel` internals (third-party code)
4. 🔄 Return to Architect for revised solution plan

---

## Self-Audit for AI Bloat (Per GUARDRAILS.md §7a)

**Audit Checklist:**

- [x] **No dead code:** `.clamp()` is the minimal fix; no unused variables or unreachable branches introduced
- [x] **No redundant comments:** Inline comment explains _why_ clamp is required (prevents negative width during drawer overlay), not _what_ the code does
- [x] **No unnecessary abstractions:** Single-line fix with no wrapper functions, no helper methods for a one-off calculation
- [x] **No defensive code for impossible cases:** Clamp is defensive against a _real_ edge case (drawer overlay restricts constraints), not speculative protection
- [x] **No duplicated logic:** No existing helper/repository method performs constraint clamping; this is the first and only location requiring it
- [x] **No over-engineering:** Most direct implementation — wrapping existing calculation in `.clamp()`, zero abstractions

**Conclusion:** Code is minimal, direct, and earns every character. No AI-generated bloat detected.

---

## Architect Plan Adherence

**Scope Verification:**

- ✅ Modified only `lib/features/calendar/widgets/calendar_grid.dart` (1 file)
- ✅ Changed only line 41 as specified in Architect Plan Phase 5
- ✅ Added inline comment explaining clamp rationale
- ✅ No files from "Files Off-Limits" table were modified
- ✅ No new dependencies introduced
- ✅ No database migrations created
- ✅ No initialization order changes
- ✅ `flutter analyze` passes with 0 errors

**Compliance:** **100%** — Implementation matches Architect Plan Phase 5 exactly.

---

## Risk Assessment

**Overall Risk Level:** **LOW** (pending on-device validation)

**Rationale:**

- Single file modified, single line changed
- No behavioral change in normal usage (Calendar visible with `constraints.maxWidth >= 24`)
- Defensive fix — prevents crashes in abnormal constraint scenarios without affecting typical rendering
- Zero-sized rendering when hidden is acceptable (tab not visible in that scenario)
- No cross-feature changes, no API changes, no state management changes

**Remaining Risk:**

- **Unknown:** Whether the clamp fix introduces _different_ exceptions in Forui's `FCalendar.wheel` third-party code when receiving zero-width Size
- **Unknown:** Whether TEST 2 shows Outcome A or B (causal relationship vs. independent bugs)
- **Mitigation:** Manual TEST 1 must pass (zero exceptions) before proceeding to TEST 2

---

## Additional Notes

**Phase 3 Fix Remains in Place:**

The `addPostFrameCallback` fix in `lib/features/auth/auth_state_provider.dart` (from Phase 3) is still applied and has not been modified or reverted. This fix defers auth state mutations to post-frame callbacks. It may still be relevant depending on TEST 2 outcome:

- **If Outcome A:** Both fixes (Phase 3 + Phase 5) together resolved the crashes
- **If Outcome B:** Phase 3 fix was correct but insufficient; `_dependents.isEmpty` has a separate root cause requiring Phase 6 investigation

**No Bloat Detected:**

Code change is minimal and direct. The `.clamp(0.0, double.infinity)` is the smallest possible fix that satisfies the requirement (prevent negative `availableWidth`). No wrapper functions, no abstractions, no defensive checks for impossible cases.

---

## Conclusion

**Task 1 (Implement Fix):** ✅ **COMPLETE**

- `calendar_grid.dart` line 41 modified with constraint clamp
- Inline comment added explaining rationale
- `flutter analyze` passes with 0 errors
- Code change is minimal, surgical, and directly addresses root cause

**Task 2 (On-Device Testing):** ❌ **BLOCKED — REQUIRES TONY**

- Device deployment non-functional from this environment (wireless iOS debugging stalls)
- Two deployment attempts both hung during build phase
- Cannot verify TEST 1–4 without manual execution by Tony on physical device

**Task 3 (Secondary Platforms):** ⏸️ **DEFERRED**

- Cannot proceed to Android/Web/macOS testing until TEST 1–2 pass on iOS (primary platform)

**Task 4 (Rehearsal Follow-Up):** ⏸️ **CONDITIONAL**

- Only applicable if TEST 2 shows Outcome A (logout crash resolved)
- Cannot execute until TEST 1–2 complete

---

**ENGINEER STATUS:** Implementation complete and verified via static analysis. On-device validation required before QA approval.

**HANDOFF TO TONY:** Please execute TEST 1–4 from the "Outstanding Validation" section above on the physical iOS device. TEST 2 is the decisive test that determines whether this fix resolves both crashes (Outcome A) or only the WheelCalendar crash (Outcome B). Document results and report back for QA gate review.

---

_Report generated: 2026-08-19_  
_Engineer: GitHub Copilot (Claude Sonnet 4.5)_  
_Branch: `bug/inherited-widget-crash-investigation`_  
_Commit: Pending manual device validation_
