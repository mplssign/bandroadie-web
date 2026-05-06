# QA Report

## Feature Slug

`bug/deploy-warnings-cleanup`

## Feature Title

Resolve Deploy/Analyzer Warnings Cleanup

## Final Verdict

**REQUIRES CHANGES**

## Validation Summary

Validated implementation against `ARCHITECT_PLAN.md` and `ENGINEER_REPORT.md`, then independently ran `git diff main`, `flutter analyze`, and `./tools/build_mobile_release.sh android-aab`. Dependency cleanup goals were met: `golden_toolkit` is removed from both `pubspec.yaml` and `pubspec.lock`, and `cupertino_icons` is not declared in `pubspec.yaml`. Build output matched Engineer claims (MaterialIcons and lucide tree-shaking only, no CupertinoIcons warning). However, diff scope includes out-of-plan file changes, so approval is blocked.

## Architect Scope Review

- Scope adherence: violated
- Files modified: deviations noted below
- Files off-limits: violations noted below

## Completeness Check

- All Architect tasks implemented: no
- Missing tasks: none
- Blocking issue: Architect scope requires minimal/surgical changes to approved files only, but additional unrelated files are modified in this branch diff vs `main`.

## Behavior Verification

- Validation method: runtime command validation + code/diff inspection
- Result: cleanup behavior matches expected; scope control does not

## Regression Check

- Risk level: MEDIUM
- Systems reviewed: dependency graph (`pubspec.yaml`, `pubspec.lock`), release build output, analyzer baseline, scoped UI files listed for conditional edits
- Regressions found: no functional regressions observed in validated commands; process/scope regression present (out-of-scope edits)

## Database Safety

Not applicable

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors

## Test Results

Not run

## Diff Safety Review

- Secrets: none found
- Debug artifacts: none found
- Unrelated changes: found
  - `lib/features/calendar/calendar_tab_content.dart` (formatting-only wrap)
  - `lib/features/home/home_screen.dart` (formatting-only wrap)
  - `lib/features/home/home_tab_content.dart` (formatting-only wrap)
  - `web/version.json` (build number changed 128 -> 132)
  - `pubspec.yaml` (contains approved `golden_toolkit` removal, plus unplanned version bump 1.2.13+128 -> 1.2.13+132)

## Verification Details for Requested Checks

1. `pubspec.yaml` no longer contains `golden_toolkit`: confirmed.
2. `pubspec.lock` no longer contains `golden_toolkit`: confirmed across full lockfile scan.
3. No unintended changes in diff: **not confirmed**; unintended changes exist (listed above).
4. Independent analyzer run: confirmed 0 errors.
5. Build output match: confirmed; only MaterialIcons and lucide tree-shaking lines present, no CupertinoIcons warning.
6. `cupertino_icons` in `pubspec.yaml`: confirmed absent, therefore no removal action required.
7. Conditional files untouched: confirmed `lib/features/bands/band_form_screen.dart` and `lib/features/setlists/new_setlist_screen.dart` show no diff vs `main`.

## Issues Found

### Critical (must fix before commit)

1. Out-of-scope diff content must be removed from this feature branch before approval:
   - formatting-only changes in `lib/features/calendar/calendar_tab_content.dart`
   - formatting-only changes in `lib/features/home/home_screen.dart`
   - formatting-only changes in `lib/features/home/home_tab_content.dart`
   - build/version drift in `web/version.json`
   - unplanned version bump in `pubspec.yaml`

### Warnings (should fix)

1. None.

### Suggestions (optional)

1. Keep the branch diff limited to dependency cleanup artifacts and report files to preserve a clean QA gate.
