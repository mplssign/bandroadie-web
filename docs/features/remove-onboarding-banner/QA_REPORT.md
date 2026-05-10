# QA Report — Remove Onboarding Banner

## Feature Slug

`bug/remove-onboarding-banner`

---

## Validation Status

**🔴 REQUIRES CHANGES**

---

## Critical Issues

### Issue 1: Branch Contains Wrong Feature Commits

**Severity:** BLOCKER

**Finding:**
The branch `bug/remove-onboarding-banner` currently has HEAD at commit `8bc79d1` with message "fix(contacts): replace EmailDomainShortcutBar with DomainChip for consistency". This commit, along with `23b3bff` on this branch, are from the email domain shortcuts feature, NOT the onboarding banner removal feature.

**Evidence:**
```bash
$ git log --oneline main..bug/remove-onboarding-banner
8bc79d1 fix(contacts): replace EmailDomainShortcutBar with DomainChip for consistency
23b3bff feat(ui): add email domain shortcut chips to all email fields
```

Both commits are unrelated to onboarding banner removal.

**Required Action:**
1. Reset this branch to main: `git reset --hard main`
2. Re-apply the onboarding banner changes
3. Commit with proper message: `fix(home): remove onboarding banner from dashboard empty state`

**QA Protocol Reference:** QA.md Phase 1 — Branch must be in reviewable state

---

### Issue 2: Implementation Not Committed

**Severity:** BLOCKER

**Finding:**
The onboarding banner removal changes exist only in the working tree (unstaged). No commit exists for this feature's implementation.

**Evidence:**
```bash
$ git status --short
 M docs/features/email-domain-shortcut-bar/QA_REPORT.md
 M lib/app/theme/design_tokens.dart
 M lib/components/ui/brand_action_button.dart
 M lib/features/home/widgets/empty_home_state.dart
```

All changes are unstaged modifications.

**Required Action:**
After fixing Issue 1, stage and commit the changes:
```bash
git add lib/app/theme/design_tokens.dart lib/components/ui/brand_action_button.dart lib/features/home/widgets/empty_home_state.dart
git commit -m "fix(home): remove onboarding banner from dashboard empty state"
```

**QA Protocol Reference:** ENGINEER.md Phase 6 requires implementation to be committed before QA

---

### Issue 3: Unrelated File Modified

**Severity:** BLOCKER

**Finding:**
File `docs/features/email-domain-shortcut-bar/QA_REPORT.md` has been modified in the working tree. This file is from a different feature and is NOT in the Architect's approved file list.

**Evidence:**
```bash
$ git status --short
 M docs/features/email-domain-shortcut-bar/QA_REPORT.md  # ← Unrelated file
 M lib/app/theme/design_tokens.dart
 M lib/components/ui/brand_action_button.dart
 M lib/features/home/widgets/empty_home_state.dart
```

The diff shows formatting changes (adding blank lines) to a QA report from the email domain shortcuts feature.

**Required Action:**
Discard changes to unrelated file:
```bash
git checkout HEAD -- docs/features/email-domain-shortcut-bar/QA_REPORT.md
```

**Architect Plan Reference:** "Files to Modify" section lists only 3 files — this file is not approved

**Guardrails Reference:** Section 7 — "Modify only files in the Architect plan"

---

## Implementation Validation (Approved Files Only)

Despite the workflow issues, I validated the actual code changes to verify they match the Architect plan.

### ✅ Task 1: Animation Count Updated

**File:** `lib/features/home/widgets/empty_home_state.dart`

**Expected:** Change `List.generate(4, ...)` to `List.generate(3, ...)` on lines for fade and slide animations

**Verified:**
- ✅ Line 58: Comment updated "4 sections" → "3 sections"
- ✅ Line 58: `List.generate(4, (index) {` → `List.generate(3, (index) {`
- ✅ Line 70: `List.generate(4, (index) {` → `List.generate(3, (index) {`

**Code Analysis:**
The animation system correctly reduces from 4 to 3 sections. Animation timing and curves remain unchanged (150ms stagger interval, Curves.easeOut).

---

### ✅ Task 2: Banner Instantiation Removed

**File:** `lib/features/home/widgets/empty_home_state.dart`

**Expected:** Remove lines 143-147 (banner call and spacing)

**Verified:**
- ✅ Removed: `const SizedBox(height: Spacing.space32)`
- ✅ Removed: `// Empty hero message` comment
- ✅ Removed: `_buildAnimatedSection(0, _EmptyHeroSection())`
- ✅ Retained: `const SizedBox(height: 34)` for proper spacing before first card

**Code Analysis:**
Banner completely removed from widget tree. Spacing adjustment maintains proper layout between app bar and first empty-state card.

---

### ✅ Task 3: Rehearsal Section Re-indexed

**File:** `lib/features/home/widgets/empty_home_state.dart`

**Expected:** Change section index from 1 to 0

**Verified:**
- ✅ Line 133: `_buildAnimatedSection(1,` → `_buildAnimatedSection(0,`
- ✅ Widget content unchanged: `EmptySectionCard(title: 'No Rehearsal Scheduled', ...)`

---

### ✅ Task 4: Gigs Section Re-indexed

**File:** `lib/features/home/widgets/empty_home_state.dart`

**Expected:** Change section index from 2 to 1

**Verified:**
- ✅ Line 146: `_buildAnimatedSection(2,` → `_buildAnimatedSection(1,`
- ✅ Widget content unchanged: `EmptySectionCard(title: 'No Upcoming Gigs', ...)`

---

### ✅ Task 5: Quick Actions Re-indexed

**File:** `lib/features/home/widgets/empty_home_state.dart`

**Expected:** Change section index from 3 to 2

**Verified:**
- ✅ Line 161: `_buildAnimatedSection(3,` → `_buildAnimatedSection(2,`
- ✅ Conditional rendering preserved: `if (widget.onAddEvent != null || widget.onCreateSetlist != null)`

---

### ✅ Task 6: Widget Class Deleted

**File:** `lib/features/home/widgets/empty_home_state.dart`

**Expected:** Delete `_EmptyHeroSection` class (lines 217-247 per Architect plan)

**Verified:**
- ✅ Lines 199-257 removed (64 lines total)
- ✅ Entire `_EmptyHeroSection` class deleted
- ✅ Includes: Container, BoxDecoration, Row, Icon, Text widgets
- ✅ File now ends at line 191 (was 257)

**Code Analysis:**
Class is completely removed. No references remain in the codebase (verified via grep).

---

### ✅ Task 7: Comment Updated (design_tokens.dart)

**File:** `lib/app/theme/design_tokens.dart`

**Expected:** Update comment on line 223 to remove reference to removed card

**Verified:**
- ✅ Line 223: `/// Matches the "Let's get this show started" hero card styling` removed
- ✅ Replaced with: `/// Brand gradient styling for primary action cards`

**Code Analysis:**
Comment update removes outdated reference while maintaining documentation clarity. No code changes, only documentation.

---

### ✅ Task 8: Comment Updated (brand_action_button.dart)

**File:** `lib/components/ui/brand_action_button.dart`

**Expected:** Update comment on line 10 to remove reference to removed card

**Verified:**
- ✅ Line 10: `/// - Gradient background matching "Let's get this show started" hero card` removed
- ✅ Replaced with: `/// - Brand gradient background with rose accent`

**Code Analysis:**
Comment update removes outdated reference while maintaining documentation clarity. No code changes, only documentation.

---

### ✅ Task 9: Static Analysis Passed

**Command:** `flutter analyze`

**Result:** ✅ PASS — 0 errors, 0 warnings

**Engineer Report Evidence:**
```
Analyzing bandroadie...
No issues found! (ran in 4.6s)
```

**Spot Check:**
Engineer report indicates unused import warnings were resolved by removing `google_fonts` and `brand_colors` imports. This is correct and justified.

---

### ✅ Unused Imports Removed

**File:** `lib/features/home/widgets/empty_home_state.dart`

**Finding:**
Two imports were removed that are not explicitly listed in Architect tasks:
- Line 4: `import 'package:google_fonts/google_fonts.dart';` removed
- Line 7: `import 'package:bandroadie/app/theme/brand_colors.dart';` removed

**Justification:**
- Both imports were ONLY used by the deleted `_EmptyHeroSection` widget
- `google_fonts` was used for the banner title text style
- `brand_colors` was used for the icon color
- Removing them was necessary to resolve `flutter analyze` warnings
- This aligns with ENGINEER.md Phase 5: "Fix only errors caused directly by this implementation"

**Status:** ✅ ACCEPTABLE DEVIATION — Documented in Engineer Report, justified, no functional impact

---

## Completeness Check

**Status:** ✅ PASS — All Architect tasks completed

| Task | Description | Status |
|------|-------------|--------|
| 1 | Update animation generation count | ✅ Complete |
| 2 | Remove banner instantiation | ✅ Complete |
| 3 | Re-index Rehearsal section | ✅ Complete |
| 4 | Re-index Gigs section | ✅ Complete |
| 5 | Re-index Quick Actions section | ✅ Complete |
| 6 | Delete `_EmptyHeroSection` class | ✅ Complete |
| 7 | Update comment in design_tokens.dart | ✅ Complete |
| 8 | Update comment in brand_action_button.dart | ✅ Complete |
| 9 | Run `flutter analyze` | ✅ Complete |
| 10 | Generate git diff | ✅ Complete |

---

## Behavior Verification

**Validation Method:** Code Path Analysis

**Root Cause Addressed:** ✅ YES

The banner was hardcoded into the widget tree with no conditional rendering logic. Removing the `_EmptyHeroSection` class and its instantiation completely eliminates the banner from the dashboard empty state.

**Expected Behavior After Fix:**
- Dashboard empty state displays 3 sections (was 4):
  1. "No Rehearsal Scheduled" card (animation index 0, was 1)
  2. "No Upcoming Gigs" card (animation index 1, was 2)
  3. Quick Actions row (animation index 2, was 3, conditional on callbacks)
- Staggered entrance animations play with 150ms intervals (unchanged behavior)
- Banner never appears under any condition

**Unaffected Behavior:**
- Empty-state cards continue to render independently
- Quick Actions conditional logic preserved
- Animation timing and curves unchanged
- Parent widgets (home_screen.dart, home_tab_content.dart) unaware of change

---

## Regression Check

**System Impact Map Validation:**

| System | Status | Notes |
|--------|--------|-------|
| Gigs | ✅ No Impact | No changes to gig domain |
| Rehearsals | ✅ No Impact | No changes to rehearsal domain |
| Setlists / Catalog | ✅ No Impact | No changes to setlist domain |
| Members / RBAC | ✅ No Impact | No changes to auth or permissions |
| Auth / Session | ✅ No Impact | No changes to auth flow |
| Routing | ✅ No Impact | No changes to navigation |
| Notifications | ✅ No Impact | No changes to notification system |
| Platform (iOS/Android/Web/macOS) | ✅ No Impact | UI rendering only, no platform-specific code |

**Specific Regression Risks:**

1. **Animation System**
   - **Risk:** Incorrect index mapping could cause animation timing issues
   - **Mitigation:** Code path analysis confirms all indices correctly decremented by 1
   - **Status:** ✅ LOW RISK — Animation logic preserved, only iteration count reduced

2. **Widget Lifecycle**
   - **Risk:** FocusNode or controller disposal issues
   - **Mitigation:** No controllers introduced or removed, only widget tree structure changed
   - **Status:** ✅ NO RISK — No lifecycle changes

3. **Rebuild Performance**
   - **Risk:** Unnecessary rebuilds
   - **Mitigation:** Build method structure unchanged, only widget count reduced
   - **Status:** ✅ NO RISK — Performance improved (fewer widgets to build)

**Overall Regression Risk:** **LOW**

**Rationale:**
- Isolated change to single file's widget tree
- No shared state modifications
- No database, RLS, or backend involvement
- Animation system logic unchanged, only count reduced
- Independent widgets preserved

---

## Database Safety

**Status:** ✅ NOT APPLICABLE

This is a UI-only change. No database tables, RLS policies, RPC functions, migrations, or triggers are involved.

---

## Diff Safety Review

**Validation:** ✅ PASS (approved files only)

| Safety Check | Status | Notes |
|--------------|--------|-------|
| No secrets or API keys | ✅ PASS | No hardcoded credentials |
| No debug artifacts | ✅ PASS | No `print()`, `debugPrint()`, or TODO hacks |
| No test scaffolding | ✅ PASS | No test code in production files |
| No accidental deletions | ✅ PASS | Only intentional deletion of `_EmptyHeroSection` |
| No environment variables | ✅ PASS | No config changes |
| No formatting-only churn | ✅ PASS | All changes functional (except necessary comment updates) |
| Only approved files modified | ❌ FAIL | Unrelated file modified (see Issue 3) |

---

## Files Changed

**Approved Files (3):**
- ✅ `lib/features/home/widgets/empty_home_state.dart` — Banner removed, animations adjusted
- ✅ `lib/app/theme/design_tokens.dart` — Comment updated
- ✅ `lib/components/ui/brand_action_button.dart` — Comment updated

**Unapproved Files (1):**
- ❌ `docs/features/email-domain-shortcut-bar/QA_REPORT.md` — Formatting changes (BLOCKER)

**Off-Limits Files:**
- ✅ `lib/features/home/home_screen.dart` — Unchanged
- ✅ `lib/features/home/home_tab_content.dart` — Unchanged
- ✅ `lib/features/home/widgets/empty_section_card.dart` — Unchanged
- ✅ `lib/features/home/widgets/quick_actions_row.dart` — Unchanged
- ✅ `lib/main.dart` — Unchanged
- ✅ All test files — Unchanged
- ✅ `supabase/` — Unchanged
- ✅ `pubspec.yaml` — Unchanged

---

## Acceptance Criteria

**From Architect Plan:**

1. ✅ Banner "Let's get this show started!" never appears
2. ✅ "No Rehearsal Scheduled" card continues to display
3. ✅ "No Upcoming Gigs" card continues to display
4. ✅ Quick Actions row preserved
5. ✅ Staggered animations work correctly with 3 sections
6. ✅ No changes to parent widgets or routing

**Code Validation Status:** 6/6 criteria met

---

## Manual Testing Recommendations

**Note:** QA Agent does not perform runtime testing per QA.md protocol. Human QA should verify:

### Platform Coverage Required
- iOS (device/simulator)
- Android (device/emulator)
- Web (Chrome, Safari, Firefox)
- macOS (desktop app)

### Test Cases

**Test Case 1: Empty State Display**
1. Navigate to dashboard with band that has no gigs or rehearsals
2. Verify banner does NOT appear
3. Verify "No Rehearsal Scheduled" card appears first
4. Verify "No Upcoming Gigs" card appears second
5. Verify Quick Actions row appears (if callbacks provided)

**Test Case 2: Entrance Animations**
1. Navigate away from dashboard
2. Return to dashboard
3. Verify staggered fade-in animations play correctly
4. Verify no timing glitches or visual artifacts

**Test Case 3: Spacing and Layout**
1. Verify spacing between app bar and first card matches design
2. Verify spacing between cards is consistent
3. Verify no layout shift or overflow

**Test Case 4: Non-Empty State (Regression)**
1. Add gig or rehearsal
2. Verify dashboard displays events correctly
3. Verify no impact on populated home screen state

---

## Summary

### Implementation Quality

**Code Changes:** ✅ EXCELLENT
- All Architect tasks completed
- Minimal, surgical changes
- No unnecessary abstractions
- Clean diff with justified deviations

**Workflow Compliance:** 🔴 CRITICAL ISSUES
- Branch contains wrong feature commits
- Implementation not committed
- Unrelated file modified

### Required Actions Before Merge

1. **Reset branch to main**
   ```bash
   git checkout bug/remove-onboarding-banner
   git reset --hard main
   ```

2. **Discard unrelated file changes**
   ```bash
   git checkout HEAD -- docs/features/email-domain-shortcut-bar/QA_REPORT.md
   ```

3. **Re-apply implementation changes**
   - Manually re-apply the 3 file changes (or cherry-pick working tree state)

4. **Commit implementation**
   ```bash
   git add lib/app/theme/design_tokens.dart lib/components/ui/brand_action_button.dart lib/features/home/widgets/empty_home_state.dart
   git commit -m "fix(home): remove onboarding banner from dashboard empty state"
   ```

5. **Run validation**
   ```bash
   flutter analyze  # Must show 0 errors, 0 warnings
   git status       # Must show clean working tree
   ```

6. **Re-submit for QA**

---

## Final Recommendation

**🔴 REQUIRES CHANGES**

**Confidence Level:** HIGH

**Blocking Issues:** 3 critical workflow violations

**Code Quality:** Excellent — implementation matches Architect plan precisely

**Next Steps:** Engineer must fix branch state, commit properly, and re-submit for QA validation

---

**QA Agent:** GitHub Copilot  
**QA Protocol Version:** QA.md (BandRoadie)  
**Validation Date:** 2026-05-09  
**Branch:** `bug/remove-onboarding-banner`  
**HEAD Commit:** `8bc79d1` (WRONG FEATURE — see Issue 1)
