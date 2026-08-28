# QA Report

## Feature Slug

bug/forui-form-field-labels

## Feature Title

Forui-wrapped form fields render with no label/hint because callers pass Material `InputDecoration`/`style`, which the wrapper silently drops.

## Final Verdict

Round 1 (historical): **REQUIRES CHANGES**

Current (Round 2 re-check): **APPROVED**

## Validation Summary

Validated implementation against the Architect plan via full code-path diff review against merge base (`origin/main`), targeted call-site spot checks, scoped grep scans, and analyzer execution. Confirmed the primary Tony-reported symptom files were migrated to wrapper-native `labelText`/`hintText`, and the two surgical edits in setlist detail were applied as planned. Validation was code-path analysis only; runtime manual screen execution was not performed in this QA pass.

## Architect Scope Review

- Scope adherence: violated
- Files modified: mostly as expected (exact 34 Architect-listed source files in `git diff --name-only` / `git diff --stat`)
- Files off-limits: not touched (`lib/main.dart`, `lib/features/setlists/setlist_repository.dart` unchanged)

## Completeness Check

- All Architect tasks implemented: no
- Missing tasks:
  - Dead wrapper `style: TextStyle(...)` props were not fully removed across the scoped migration set.

## Behavior Verification

- Validation method: code-path analysis
- Result: partial match; key label/hint/icon migrations are present, but some behavior drift was introduced in raw field migrations.

## Regression Check

- Risk level: MEDIUM
- Systems reviewed: contacts forms, auth inputs, setlist rename/search/notes surfaces, band form helpers, event editor helper, lyrics editor, financial entry and gig pay inputs, shared currency input
- Regressions found: potential UX/behavior regressions listed below

## Database Safety

Not applicable.

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 13 warnings.

## Test Results

Not run.

## Diff Safety Review

- Secrets: none found
- Debug artifacts: none found
- Unrelated changes: no unrelated source files in diff stat; no iOS / `pubspec.lock` churn present

## Code Efficiency Review

- Dead code / unused imports, vars, params: found (`errorText` now unused in `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart:292`)
- Redundant restating comments: none found
- Unnecessary abstraction for single call sites: none found
- Unneeded defensive checks (impossible-case guards, try/catch): none found
- Duplicated logic that should reuse existing code: none found
- Overall assessment: acceptable, but not complete per Architect requirements

## Issues Found

### Critical (must fix before commit)

1. Remaining dead wrapper `style: TextStyle(...)` props still exist in Architect-scoped files, violating the migration requirement to remove dead `decoration`/`style` wrapper props.
   - `lib/features/contacts/widgets/invite_members_screen.dart:310`
   - `lib/features/contacts/widgets/title_pill_selector.dart:169`
   - `lib/features/profile/my_profile_screen.dart:463`
   - `lib/features/profile/my_profile_screen.dart:1033`
   - `lib/features/setlists/widgets/custom_tuning_modal.dart:382`
   - `lib/features/setlists/widgets/custom_tuning_modal.dart:412`
   - `lib/features/setlists/widgets/bulk_add_songs_overlay.dart:496`
   - `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart:518`
   - `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart:963`
   - `lib/features/bands/band_form_screen.dart:1702`
   - `lib/features/bands/band_form_screen.dart:2074`
   - `lib/features/lyrics/widgets/lyrics_editor_sheet.dart:639`

### Warnings (should fix)

1. Behavior drift in lyrics editor migration: previous `TextField` used `expands: true` and `textAlignVertical: TextAlignVertical.top`; migrated `AppTextField` now uses `minLines: 10` and no `expands`, which may alter expected editor sizing/fill behavior.
   - `lib/features/lyrics/widgets/lyrics_editor_sheet.dart:636`
2. Add-type dialog no longer surfaces inline validation text (`errorText`) after migrating to `AppTextField`; variable is now unused, suggesting user feedback path was removed.
   - `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart:292`
   - `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart:315`

### Suggestions (optional)

1. After addressing critical/warning issues, rerun manual verification steps from Architect plan for Contacts, Auth, Setlists, Financials, and Lyrics to confirm UI and interaction parity at runtime.

---

## Round 2 Re-Check (Fix Verification)

## Final Verdict

**APPROVED**

## Validation Summary

Re-ran QA as a targeted fix-verification pass against `origin/main`, focused on the three previously-blocking findings and a scope sanity re-check. Verification included structural call-site scanning of all Architect-listed files, direct diff checks, and analyzer execution. Validation method was code-path analysis and static tooling only; runtime/manual UI testing was not performed in this pass.

## Targeted Findings Verification

1. Dead `style:`/`decoration:` cleanup:
   - Ran balanced-parenthesis call-site scan (not single-line regex) across all files in the Architect "Files To Modify" list.
   - Result: zero `style:` and zero `decoration:` arguments remain inside `AppTextField(...)` / `AppTextFormField(...)` calls.
2. Lyrics editor exception file:
   - `git diff --name-only origin/main -- lib/features/lyrics/widgets/lyrics_editor_sheet.dart` returned no output.
   - Confirmed the file is now fully reverted relative to `origin/main` and no longer part of the active diff.
3. Add Type dialog (`_showAddTypeDialog`) behavior:
   - Confirmed conditional error rendering exists in widget tree (`if (errorText != null) ... Text(errorText!)`) in `AlertDialog` content.
   - Confirmed live update flow remains logically correct via `setDialogState(() => errorText = ...)` on validation failures.
4. Scope re-confirmation:
   - `git diff --name-only origin/main` shows exactly 33 changed Dart files.
   - No non-Dart tracked files appear in diff.
   - Docs follow-up files are present as untracked changes under `docs/features/forui-form-field-labels/`.
5. Analyzer authoritative count:
   - Command run: `flutter analyze`
   - Result: 0 errors, 8 warnings, 4 infos (12 total issues reported).

## Regression Check

- Risk level: LOW
- Systems reviewed: wrapper call-site argument migration scope, lyrics editor exception handling, financial add-type dialog validation feedback path, overall changed-file boundaries
- Regressions found in this re-check: none

## Database Safety

Not applicable.

## Issues Found (Round 2)

None.
