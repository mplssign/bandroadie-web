# Engineer Report

## Feature Slug

`bug/remove-onboarding-banner`

---

## Feature Title

Remove Onboarding Banner from Dashboard Empty State

---

## Goal

Permanently remove the red "Let's get this show started!" banner card from the dashboard empty state. The banner currently displays when a band has no upcoming gigs or rehearsals, but should be removed while preserving the existing empty-state cards ("No Rehearsal Scheduled" and "No Upcoming Gigs") and Quick Actions row.

---

## Architect Tasks Completed

- [x] Task 1 — Update animation generation count (4→3)
- [x] Task 2 — Remove banner instantiation and adjust spacing
- [x] Task 3 — Re-index "No Rehearsal Scheduled" section (1→0)
- [x] Task 4 — Re-index "No Upcoming Gigs" section (2→1)
- [x] Task 5 — Re-index "Quick Actions" section (3→2)
- [x] Task 6 — Delete `_EmptyHeroSection` widget class
- [x] Task 7 — Update comment in design_tokens.dart
- [x] Task 8 — Update comment in brand_action_button.dart
- [x] Task 9 — Run `flutter analyze`
- [x] Task 10 — Generate git diff

**Status:** All 10 tasks completed successfully

---

## Files Created

None

---

## Files Modified

1. `lib/features/home/widgets/empty_home_state.dart`
   - Removed `_EmptyHeroSection` widget class (lines 195-261)
   - Removed banner instantiation from build method
   - Updated animation generation from 4 to 3 sections
   - Re-indexed remaining animated sections (0, 1, 2)
   - Removed unused imports (`google_fonts`, `brand_colors`)
   - Adjusted spacing (removed `Spacing.space32`, kept one `SizedBox(height: 34)`)

2. `lib/app/theme/design_tokens.dart`
   - Updated comment on line 223 from "Matches the 'Let's get this show started' hero card styling" to "Brand gradient styling for primary action cards"

3. `lib/components/ui/brand_action_button.dart`
   - Updated comment on line 10 from "Gradient background matching 'Let's get this show started' hero card" to "Brand gradient background with rose accent"

---

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors, 0 warnings

```
Analyzing bandroadie...
No issues found! (ran in 4.6s)
```

**Note:** Initial run detected 2 unused import warnings (`google_fonts`, `brand_colors`) which were resolved by removing the imports that were only used by the deleted `_EmptyHeroSection` widget.

---

## Test Results

Not run — no automated tests exist for `EmptyHomeState` widget per Architect plan

---

## Verification

### Manual steps performed:

1. **Branch verification**
   - Confirmed branch: `bug/remove-onboarding-banner`
   - Working tree status: Clean (except for pre-existing untracked files and one unrelated docs modification)

2. **Code changes verification**
   - Reviewed all modified files
   - Confirmed banner widget class deletion
   - Confirmed animation indices updated correctly
   - Confirmed spacing adjustments maintain visual consistency
   - Confirmed comment updates remove references to deleted card

3. **Static analysis**
   - `flutter analyze` passes with 0 errors, 0 warnings
   - No syntax errors introduced
   - No linting issues introduced

4. **Import cleanup**
   - Removed 2 unused imports that were only needed by deleted widget
   - All remaining imports are in use

### Code integrity checks:

- ✅ Animation system remains functional (3 sections instead of 4)
- ✅ Empty-state cards ("No Rehearsal Scheduled", "No Upcoming Gigs") preserved
- ✅ Quick Actions row preserved
- ✅ Staggered entrance animation logic unchanged (same intervals, curves)
- ✅ No changes to parent widgets (`home_screen.dart`, `home_tab_content.dart`)
- ✅ No changes to shared widgets (`empty_section_card.dart`, `quick_actions_row.dart`)
- ✅ No database, RLS, auth, or routing changes
- ✅ No dependency additions or removals

---

## Deviations From Architect Plan

**Minor deviation (within scope):**

The Architect plan specified removing the banner instantiation and associated spacing (lines 143-147). During implementation, I also removed 2 unused imports (`google_fonts`, `brand_colors`) that were only needed by the deleted `_EmptyHeroSection` widget. This was necessary to resolve warnings from `flutter analyze` and is consistent with the Engineer protocol requirement to fix errors/warnings directly caused by the implementation.

**Justification:**

- Unused imports were a direct result of deleting the `_EmptyHeroSection` class
- Removing them is a code hygiene best practice
- No functional impact — only affects import statements
- Aligns with the "fix only errors caused directly by this implementation" rule in ENGINEER.md Phase 5

---

## Blockers Encountered

None

---

## Ready For QA

**Yes**

### QA should verify:

1. **Empty state display** (all platforms: iOS, Android, Web, macOS)
   - The "Let's get this show started!" banner does NOT appear
   - "No Rehearsal Scheduled" card displays as the first card
   - "No Upcoming Gigs" card displays as the second card
   - Quick Actions row displays when applicable

2. **Entrance animations**
   - Staggered animations play correctly with 3 sections
   - No timing issues or visual glitches

3. **Spacing and layout**
   - Spacing between elements matches design tokens
   - No visual regression compared to pre-change layout (except banner removal)

4. **Non-empty state** (regression check)
   - When gigs/rehearsals exist, home screen displays them correctly
   - No impact on populated home screen state

### Platforms requiring manual testing:

- iOS (device/simulator)
- Android (device/emulator)
- Web (Chrome, Safari, Firefox)
- macOS

---

## Git Diff

```diff
diff --git a/lib/app/theme/design_tokens.dart b/lib/app/theme/design_tokens.dart
index f50cdf3..c624784 100644
--- a/lib/app/theme/design_tokens.dart
+++ b/lib/app/theme/design_tokens.dart
@@ -220,7 +220,7 @@ class StandardCardBorder {
 }

 /// Brand action button styling (rose-outlined buttons)
-/// Matches the "Let's get this show started" hero card styling
+/// Brand gradient styling for primary action cards
 class BrandButton {
   BrandButton._();

diff --git a/lib/components/ui/brand_action_button.dart b/lib/components/ui/brand_action_button.dart
index 04709ec..61948c2 100644
--- a/lib/components/ui/brand_action_button.dart
+++ b/lib/components/ui/brand_action_button.dart
@@ -7,7 +7,7 @@ import 'package:bandroadie/app/theme/design_tokens.dart';
 /// rose-accent styling (gradient background + rose border).
 ///
 /// Features:
-/// - Gradient background matching "Let's get this show started" hero card
+/// - Brand gradient background with rose accent
 /// - Rose-accent border at 20% opacity
 /// - Optional leading icon
 /// - Loading state with spinner
diff --git a/lib/features/home/widgets/empty_home_state.dart b/lib/features/home/widgets/empty_home_state.dart
index 3eacbe7..5cbd7bb 100644
--- a/lib/features/home/widgets/empty_home_state.dart
+++ b/lib/features/home/widgets/empty_home_state.dart
@@ -1,10 +1,8 @@
 import 'dart:io';

 import 'package:flutter/material.dart';
-import 'package:google_fonts/google_fonts.dart';

 import '../../../app/theme/design_tokens.dart';
-import 'package:bandroadie/app/theme/brand_colors.dart';
 import 'empty_section_card.dart';
 import 'home_app_bar.dart';
 import 'quick_actions_row.dart';
@@ -57,8 +55,8 @@ class _EmptyHomeStateState extends State<EmptyHomeState>
       vsync: this,
     );

-    // Create staggered animations for 4 sections
-    _fadeAnimations = List.generate(4, (index) {
+    // Create staggered animations for 3 sections
+    _fadeAnimations = List.generate(3, (index) {
       final start = index * 0.15;
       final end = (start + 0.4).clamp(0.0, 1.0);
       return Tween<double>(begin: 0.0, end: 1.0).animate(
@@ -69,7 +67,7 @@ class _EmptyHomeStateState extends State<EmptyHomeState>
       );
     });

-    _slideAnimations = List.generate(4, (index) {
+    _slideAnimations = List.generate(3, (index) {
       final start = index * 0.15;
       final end = (start + 0.4).clamp(0.0, 1.0);
       return Tween<Offset>(
@@ -128,16 +126,11 @@ class _EmptyHomeStateState extends State<EmptyHomeState>
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
-                const SizedBox(height: Spacing.space32),
-
-                // Empty hero message
-                _buildAnimatedSection(0, _EmptyHeroSection()),
-
                 const SizedBox(height: 34),

                 // Rehearsal section
                 _buildAnimatedSection(
-                  1,
+                  0,
                   EmptySectionCard(
                     title: 'No Rehearsal Scheduled',
                     subtitle: 'The stage is empty and the amps are cold.',
@@ -150,7 +143,7 @@ class _EmptyHomeStateState extends State<EmptyHomeState>

                 // Gigs section
                 _buildAnimatedSection(
-                  2,
+                  1,
                   EmptySectionCard(
                     title: 'No Upcoming Gigs',
                     subtitle:
@@ -165,7 +158,7 @@ class _EmptyHomeStateState extends State<EmptyHomeState>
                 // Quick actions (only shown when at least one action is available)
                 if (widget.onAddEvent != null || widget.onCreateSetlist != null)
                   _buildAnimatedSection(
-                    3,
+                    2,
                     Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
@@ -196,58 +189,3 @@ class _EmptyHomeStateState extends State<EmptyHomeState>
     );
   }
 }
-
-/// Hero section for empty state with encouraging copy
-class _EmptyHeroSection extends StatelessWidget {
-  @override
-  Widget build(BuildContext context) {
-    return Container(
-      width: double.infinity,
-      padding: const EdgeInsets.all(Spacing.space24),
-      decoration: BrandButton.decoration,
-      child: Column(
-        crossAxisAlignment: CrossAxisAlignment.start,
-        children: [
-          Row(
-            children: [
-              Container(
-                width: 48,
-                height: 48,
-                decoration: BoxDecoration(
-                  color: AppColors.primary.withValues(alpha: 0.15),
-                  borderRadius: BorderRadius.circular(12),
-                ),
-                child: const Icon(
-                  Icons.rocket_launch_rounded,
-                  color: AppColors.primary,
-                  size: 24,
-                ),
-              ),
-              const SizedBox(width: Spacing.space16),
-              Expanded(
-                child: Column(
-                  crossAxisAlignment: CrossAxisAlignment.start,
-                  children: [
-                    Text(
-                      "Let's get this show started!",
-                      style: GoogleFonts.dmSans(
-                        fontSize: 14,
-                        fontWeight: FontWeight.w700,
-                        color: context.colors.textPrimary,
-                      ),
-                    ),
-                    const SizedBox(height: Spacing.space4),
-                    Text(
-                      'Add your first gig or rehearsal below.',
-                      style: AppTextStyles.cardSubtitle,
-                    ),
-                  ],
-                ),
-              ),
-            ],
-          ),
-        ],
-      ),
-    );
-  }
-}
```

---

## Implementation Summary

Successfully removed the onboarding banner from the dashboard empty state by:

1. Deleting the `_EmptyHeroSection` widget class (64 lines removed)
2. Removing the banner from the widget tree
3. Adjusting the animation system from 4 to 3 sections
4. Re-indexing remaining sections to maintain correct staggered animation timing
5. Updating documentation comments to remove outdated references
6. Cleaning up unused imports

The remaining empty-state UI (Rehearsal card, Gigs card, Quick Actions) continues to function identically. No backend, database, or architectural changes were required. The implementation is minimal, safe, and ready for QA validation across all platforms.

---

## Remediation

**Date:** May 9, 2026  
**Trigger:** QA identified 3 blocking issues with branch state

### Issues Identified by QA

1. **Wrong commits on branch:** Commits `8bc79d1` and `23b3bff` from the email domain shortcuts feature were present on `bug/remove-onboarding-banner` branch
2. **Implementation not committed:** All code changes existed only in the working tree (unstaged)
3. **Unrelated file modified:** `docs/features/email-domain-shortcut-bar/QA_REPORT.md` had modifications not approved by Architect plan

### Remediation Steps Executed

```bash
# 1. Confirmed current state
git branch --show-current  # bug/remove-onboarding-banner
git status --short         # 4 unstaged modified files

# 2. Stashed working tree changes
git stash push -m "banner-fix-working-tree"

# 3. Reset branch to main (removed wrong commits)
git reset --hard main

# 4. Restored working tree changes
git stash pop

# 5. Resolved merge conflict and removed unrelated file
git rm docs/features/email-domain-shortcut-bar/QA_REPORT.md

# 6. Verified only 3 approved files remained staged
git status --short
# M  lib/app/theme/design_tokens.dart
# M  lib/components/ui/brand_action_button.dart
# M  lib/features/home/widgets/empty_home_state.dart

# 7. Added docs and committed
git add docs/features/remove-onboarding-banner/*.md
git commit -m "fix(home): remove onboarding banner from dashboard empty state"
```

### Final Git State

- **Branch:** `bug/remove-onboarding-banner`
- **Commits ahead of main:** 1 (commit `639892d`)
- **Working tree:** Clean
- **Files in commit:** 6 (3 implementation files + 3 documentation files)

**Verification:**
```bash
$ git log --oneline main..bug/remove-onboarding-banner
639892d (HEAD -> bug/remove-onboarding-banner) fix(home): remove onboarding banner from dashboard empty state

$ git status --short
?? dart_defines.json
```

### Root Cause Analysis

The wrong commits were present because the branch was created from or merged with another feature branch instead of being based directly on `main`. The working tree changes were never committed, likely due to an interrupted workflow.

### Resolution Confirmation

✅ All 3 QA blockers resolved:
- Removed wrong feature commits from branch history
- Committed implementation with correct message
- Discarded unrelated file modifications

Branch is now in correct state for QA validation.
