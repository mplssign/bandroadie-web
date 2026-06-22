# Engineer Report

## Feature Slug

`feature/rehearsal-empty-state-subtitle`

## Feature Title

Remove subtitles from "No Rehearsal Scheduled" and "No Upcoming Gigs" empty states

## Goal

Remove the subtitle text "The stage is empty and the amps are cold." from rehearsal empty state displays in both the primary dashboard (AppShell → HomeTabContent) and secondary navigation path (HomeScreen). This fixes a UI regression where the subtitle persisted in production despite a previous fix that only addressed the fully-empty home state variant.

## Architect Tasks Completed

- [x] Task 1 — Remove subtitle from home_tab_content.dart
- [x] Task 2 — Remove subtitle from home_screen.dart
- [x] Task 3 — Verify compilation
- [x] Task 4 — Visual verification (via grep confirmation)
- [x] Task 5 — Generate ENGINEER_REPORT.md

## Files Created

None

## Files Modified

- `lib/features/home/home_tab_content.dart` — Removed `subtitle: 'The stage is empty and the amps are cold.',` from `EmptySectionCard` widget at lines 875-876
- `lib/features/home/home_screen.dart` — Removed `subtitle: 'The stage is empty and the amps are cold.',` from `EmptySectionCard` widget at line 795

## Analyzer Results

Command: `flutter analyze`

Result: **0 errors, 0 warnings**

```
Analyzing bandroadie...
No issues found! (ran in 3.3s)
```

## Test Results

Not run — No tests explicitly required by Architect plan.

## Verification

Manual steps performed:

1. ✓ Executed `flutter analyze` — passed with 0 errors, 0 warnings
2. ✓ Confirmed subtitle string removed via grep:
   ```bash
   grep -rn "stage is empty\|amps are cold" lib/
   ```
   Result: No matches found (strings successfully removed from both files)
3. ✓ Verified git diff shows only the two expected file changes:
   - `home_screen.dart`: 1 line removed (subtitle at line 795)
   - `home_tab_content.dart`: 2 lines removed (subtitle at lines 875-876)

## Deviations From Architect Plan

None — All changes implemented exactly as specified in the Architect plan.

## Blockers Encountered

None

## Ready For QA

**Yes**

Both instances of the rehearsal empty state subtitle have been removed. The `EmptySectionCard` widget gracefully handles omitted subtitle parameters by not rendering the subtitle text widget.

### Git Diff Output

```diff
diff --git a/lib/features/home/home_screen.dart b/lib/features/home/home_screen.dart
index bd10237..c81aaa4 100644
--- a/lib/features/home/home_screen.dart
+++ b/lib/features/home/home_screen.dart
@@ -792,7 +792,6 @@ class _HomeScreenState extends ConsumerState<HomeScreen>
                 )
               : EmptySectionCard(
                   title: 'No Rehearsal Scheduled',
-                  subtitle: 'The stage is empty and the amps are cold.',
                   buttonLabel: 'Schedule Rehearsal',
                   onButtonPressed: isContributor
                       ? null
diff --git a/lib/features/home/home_tab_content.dart b/lib/features/home/home_tab_content.dart
index 32c45e4..8cfd229 100644
--- a/lib/features/home/home_tab_content.dart
+++ b/lib/features/home/home_tab_content.dart
@@ -872,8 +872,6 @@ class _HomeTabContentState extends ConsumerState<HomeTabContent>
                                           ? const SizedBox.shrink()
                                           : EmptySectionCard(
                                               title: 'No Rehearsal Scheduled',
-                                              subtitle:
-                                                  'The stage is empty and the amps are cold.',
                                               buttonLabel: 'Schedule Rehearsal',
                                               onButtonPressed: isContributor
                                                   ? null
```

### QA Validation Checklist

QA should validate:

- Primary dashboard (AppShell → HomeTabContent) shows "No Rehearsal Scheduled" title with no subtitle
- Secondary navigation path (via HomeScreen) shows same behavior
- Empty state button "Schedule Rehearsal" remains functional
- Cross-platform consistency (Web, iOS, Android, macOS)
