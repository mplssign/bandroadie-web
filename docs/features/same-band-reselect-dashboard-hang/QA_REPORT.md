# QA Report

## Feature Slug

bug/same-band-reselect-dashboard-hang

## Feature Title

Dashboard Hang on Same-Band Reselection

## Final Verdict

**APPROVED**

## Validation Summary

Code-path analysis confirms all 4 band selection handlers correctly implement the same-band guard (close switcher → check band → early return). Guards read `activeBandIdProvider` before any state mutation, preventing `resetForBandChange()` calls on same-band taps. Flutter analyze passes with 0 errors. Implementation matches Architect plan with documented Manager-approved deviation (close-first ordering). Runtime device testing deferred to manual QA per plan section 16.

## Architect Scope Review

- Scope adherence: **compliant** (with Manager-approved deviation from plan section 10 guard placement)
- Files modified: **as expected** (4 files: home_screen.dart, app_shell.dart, calendar_screen.dart, setlists_screen.dart)
- Files off-limits: **not touched** (verified via git diff)

### Manager-Approved Deviation

Engineer Report documents Manager verification that `_BandListItem.onTap` (band_switcher.dart ~line 171) does NOT close the switcher itself. Original plan specified guard placement BEFORE close call, which would create dead-tap scenario (switcher stays open). Manager directed close-first ordering to ensure switcher always closes per plan section 16 scenario #1: "Drawer closes, dashboard shows existing data immediately."

Implementation order validated in all 4 handlers:

1. Close switcher (`_closeBandSwitcher()` or `onClose()`)
2. Read current band ID (`ref.read(activeBandIdProvider)`)
3. Early return if same band
4. Reset providers and select band (only runs for different band)

## Completeness Check

- All Architect tasks implemented: **yes**
- Missing tasks: **none**

### Task Verification

- ✅ Task 1 — Guard added in home_screen.dart:162-163 (inside `_handleBandSelected`)
- ✅ Task 2 — Guard added in app_shell.dart:314-315 (inside `onBandSelected:` callback)
- ✅ Task 3 — Guard added in calendar_screen.dart:155-156 (inside `_handleBandSelected`)
- ✅ Task 4 — Guard added in setlists_screen.dart:418-419 (inside `_handleBandSelected`)
- ✅ Task 5 — Grep verification completed (only 4 call sites exist, all modified)
- ✅ Task 6 — Analyzer run completed (0 errors)

## Behavior Verification

- Validation method: **code-path analysis** (runtime device testing deferred to manual QA)
- Result: **matches expected behavior**

### Code-Path Analysis Results

**Same-band path (bug fix):**

1. User taps currently active band
2. Switcher closes via `_closeBandSwitcher()` or `onClose()`
3. Guard reads `activeBandIdProvider` (current value at tap time)
4. `band.id == currentBandId` evaluates to `true`
5. Early return prevents `resetForBandChange()` calls
6. Dashboard retains existing data, no spinner, no reload
7. **Bug prevented:** No permanent loading state

**Different-band path (regression check):**

1. User taps different band
2. Switcher closes
3. Guard reads `activeBandIdProvider`
4. `band.id == currentBandId` evaluates to `false`
5. Execution continues to `resetForBandChange()` calls
6. Loading state set, provider chain fires, data reloads
7. **Existing behavior preserved**

**Provider access validation:**

- home_screen.dart: `_HomeScreenState extends ConsumerState<HomeScreen>` ✅
- calendar_screen.dart: `_CalendarScreenState extends ConsumerState<CalendarScreen>` ✅
- setlists_screen.dart: `_SetlistsScreenState extends ConsumerState<SetlistsScreen>` ✅
- app_shell.dart: `_BandSwitcherLayer extends ConsumerWidget` (ref from build method) ✅

All 4 implementations correctly access `ref` to read `activeBandIdProvider` at tap time (not stale closure).

## Regression Check

- Risk level: **LOW**
- Systems reviewed: Gigs, Rehearsals, Auth/Session, Routing, Band Selection Flow
- Regressions found: **none**

### Risk Analysis

**Why LOW:**

- Change is localized to 4 UI event handlers (12 lines total)
- No changes to provider lifecycle, state classes, or build methods
- No changes to database, RLS, or backend logic
- Guard only affects same-band tap case (currently broken)
- Different-band selection continues unchanged (guard doesn't fire)
- No async gaps, no lifecycle interactions, no disposal concerns
- No modifications to initialization order (GUARDRAILS §1)
- No modifications to data flow patterns (GUARDRAILS §9)

**Affected systems:**

- Gigs: unaffected (guard prevents unnecessary reset on same-band tap)
- Rehearsals: unaffected (guard prevents unnecessary reset on same-band tap)
- Routing: unaffected (tab navigation behavior unchanged)
- Auth/Session: unaffected (no auth/session code touched)

**Verified guard placement:**
All guards correctly placed BEFORE any state mutation:

- home_screen.dart:167-168 — `resetForBandChange()` unreachable on same-band path
- calendar_screen.dart:160-161 — `resetForBandChange()` unreachable on same-band path
- setlists_screen.dart:421-422 — `resetForBandChange()` unreachable on same-band path
- app_shell.dart:316-317 — `resetForBandChange()` unreachable on same-band path

## Database Safety

**Not applicable** — No database changes, migrations, RLS policies, or RPC modifications.

## Analyzer Results

Command: `flutter analyze`
Result: **0 errors**

Output:

```
Analyzing bandroadie...
No issues found! (ran in 5.6s)
```

- 0 errors
- 0 warnings
- 0 new issues introduced

## Test Results

**Not run** — Architect plan section 15 specifies "Verification is manual UI testing only" (no automated tests required for this bug fix).

## Diff Safety Review

- Secrets: **none found**
- Debug artifacts: **none** (existing `debugPrint` statements preserved, no new debug code added)
- Unrelated changes: **none** (only 4 screen files modified, 12 insertions total, 0 deletions)

### Diff Summary

```
 lib/features/calendar/calendar_screen.dart | 3 +++
 lib/features/home/home_screen.dart         | 3 +++
 lib/features/setlists/setlists_screen.dart | 3 +++
 lib/features/shell/app_shell.dart          | 3 +++
 4 files changed, 12 insertions(+)
```

All changes are guard additions (3 lines per file):

1. Read current band ID
2. Early return if same band
3. Blank line for readability

## Issues Found

**None** — Implementation is correct, complete, and safe to commit.

---

## Manual Device Testing Required

Runtime device testing is deferred to manual QA by Product Owner (Android device available). Execute the following test scenarios in priority order per Architect plan section 16:

### Priority 1: Bug Fix Verification (Primary)

#### Test 1.1: Same-band reselection on Android

**Platform:** Android device  
**Preconditions:** Dashboard loaded with gigs/rehearsals visible (no spinner)  
**Steps:**

1. Tap band avatar (top-right corner)
2. Verify band switcher drawer opens
3. Tap the currently selected band (marked with checkmark)
4. Observe behavior

**Expected:**

- Drawer closes immediately
- Dashboard shows existing data (no reload)
- No spinner appears
- No app freeze or hang

**CRITICAL:** This is the bug being fixed. If spinner appears or app hangs, implementation FAILED.

#### Test 1.2: Same-band reselection on Web

**Platform:** Web app (app.bandroadie.com)  
**Steps:** Same as Test 1.1  
**Expected:** Same behavior as Android

#### Test 1.3: Same-band reselection from all 4 screens

**Platforms:** Android (primary), Web (if time permits)  
**Screens to test:**

1. Dashboard → open band switcher → tap same band
2. Calendar → open band switcher → tap same band
3. Setlists → open band switcher → tap same band
4. Any screen with AppBar switcher → open band switcher → tap same band

**Expected for all:** Drawer closes, no reload, no spinner

### Priority 2: Regression Prevention (Secondary)

#### Test 2.1: Different-band selection still works

**Preconditions:** User is member of 2+ bands  
**Steps:**

1. Note current band name in avatar
2. Open band switcher
3. Tap a DIFFERENT band
4. Observe behavior

**Expected:**

- Drawer closes immediately
- Spinner appears briefly ("Setting up the stage...")
- Dashboard reloads with new band's gigs/rehearsals
- Band avatar updates to new band name
- No errors, no hanging

**CRITICAL:** Guard must NOT interfere with different-band selection.

#### Test 2.2: Band switcher after error state

**Preconditions:** Simulate network error (airplane mode) to trigger RPC timeout  
**Steps:**

1. Enable airplane mode
2. Switch to different band
3. Wait for error message on dashboard
4. Disable airplane mode
5. Open band switcher, tap same band
6. Verify drawer closes, error persists (no reload)
7. Open band switcher, tap DIFFERENT band
8. Verify spinner shows, error clears, fresh data loads

**Expected:**

- Same-band tap: closes drawer, error persists
- Different-band tap: triggers reload, clears error

#### Test 2.3: Multiple rapid same-band taps

**Steps:**

1. Open/close band switcher 5 times rapidly
2. Each time tap the currently active band
3. Observe behavior

**Expected:**

- Drawer closes each time
- No spinner at any point
- No hanging or performance degradation

### Priority 3: Edge Cases (If Time Permits)

#### Test 3.1: Band switcher from no-band state

**Preconditions:** New user account (or delete all bands)  
**Steps:**

1. Create first band
2. Verify band is automatically selected
3. Verify dashboard loads

**Expected:** No regression in first-band flow (guard only affects 2+ band scenario)

#### Test 3.2: Tab navigation after same-band tap

**Steps:**

1. From Dashboard, open switcher, tap same band
2. Navigate to Calendar tab
3. Navigate back to Dashboard tab

**Expected:** Dashboard shows same data, no reload, no spinner

---

## Test Pass Criteria

**Minimum for APPROVED verdict (already achieved in code review):**

- ✅ Code-path analysis confirms correct implementation
- ✅ Flutter analyze passes
- ✅ All 4 guards correctly placed
- ✅ No regressions introduced per static analysis

**Required for production deployment (manual QA):**

- Test 1.1 (Android same-band reselection) MUST PASS
- Test 2.1 (different-band selection) MUST PASS
- All other Priority 1 and 2 tests SHOULD PASS

**Failure criteria:**

- If Test 1.1 fails (spinner/hang persists), implementation FAILED — do not deploy
- If Test 2.1 fails (different-band broken), regression introduced — do not deploy

---

## QA Agent Notes

**Validation confidence: HIGH**

- Implementation is minimal (12 lines) and localized (4 event handlers)
- Code-path analysis is definitive for this type of guard logic
- No complex state interactions or async behavior to validate
- Flutter analyze confirms no type errors or static analysis issues

**Why runtime testing is deferred:**

- This is a UI interaction bug requiring physical device testing
- Code-path analysis definitively proves guard logic is correct
- Manual testing by Product Owner with actual device is more valuable than emulator testing
- Product Owner is the primary stakeholder for UX validation

**Architect plan alignment:**

- Implementation matches Architect intent (guard prevents unnecessary provider resets)
- Manager-approved deviation (close-first ordering) is well-documented and justified
- All task requirements completed
- No scope creep or architectural changes

**Commit recommendation:**
Implementation is correct and safe to commit. Manual device testing can be performed post-commit on the branch before merging to main.
