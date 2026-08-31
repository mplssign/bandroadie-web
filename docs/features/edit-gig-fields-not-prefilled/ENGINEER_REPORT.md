# Engineer Report

## Feature Slug

bug/edit-gig-fields-not-prefilled

## Feature Title

Edit Gig Fields Not Prefilled

## Goal

Restore edit-mode prefilling for the gig Name and City autocomplete fields, and apply the same controller-binding fix to rehearsal Location because it shares the same missing-controller pattern.

## Architect Tasks Completed

- [x] Task 1 — confirmed the gig autocomplete widgets were using managed controls without external controllers.
- [x] Task 2 — confirmed the drawer already seeded edit-mode state for gig name, city, and rehearsal location.
- [x] Task 3 — added a stable external controller for the gig name autocomplete.
- [x] Task 4 — added a stable external controller for the gig city autocomplete.
- [x] Task 5 — left Address and State behavior unchanged.
- [x] Task 6 — added the same controller binding to rehearsal location.
- [x] Task 7 — kept labels, hints, and create-mode behavior unchanged.
- [x] Task 8 — reviewed the final diff for scope and limited it to controller wiring.

## Files Created

- [docs/features/edit-gig-fields-not-prefilled/ENGINEER_REPORT.md](docs/features/edit-gig-fields-not-prefilled/ENGINEER_REPORT.md)

## Files Modified

- [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
- [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart)
- [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart)

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 0 warnings

## Test Results

Not run

## Code Efficiency / Bloat Check

Confirmed no dead code, unused imports/variables/parameters, redundant restating comments, single-use wrapper abstractions, or unnecessary defensive checks in the diff.

## Verification

Manual steps performed:

- Confirmed the edit drawer already seeds name, city, and rehearsal location state before widget build.
- Confirmed the gig and rehearsal autocomplete controls now receive stable external controllers.
- Ran `flutter analyze` and verified it completed with no issues.

## Deviations From Architect Plan

`event_editor_drawer.dart` was updated because the new autocomplete controllers needed a stable owner with dispose lifecycle; without that, the widget-local fix would not persist correctly across rebuilds.

## Blockers Encountered

None

## Ready For QA

Yes

## Round 2 Follow-up Fix (setState During Build)

### Regression Cause

- After Round 1, edit-mode autocomplete controllers were correctly seeded with existing values via `FAutocompleteController(text: ...)`.
- Forui `FAutocomplete` synchronously emits the controller's current value through `onChange` when attaching during widget build.
- In `EventEditorDrawer`, the `onLocationTextChanged`, `onGigNameTextChanged`, and `onGigCityTextChanged` callbacks unconditionally called `setState()` and `_markDirty()`.
- That caused `setState() or markNeedsBuild() called during build` when `GigFormFields`/`RehearsalFormFields` were still building.

### Round 2 Code Fix

- Added an equality guard at the top of each affected callback in `event_editor_drawer.dart`:
  - `onLocationTextChanged`: return early when incoming `text == _rehearsalLocationText`
  - `onGigNameTextChanged`: return early when incoming `text == _gigNameText`
  - `onGigCityTextChanged`: return early when incoming `text == _gigCityText`
- Only real text changes now execute `setState()` and `_markDirty()`.
- This preserves dirty-state behavior for user edits while ignoring the initial seeded-value echo.
- Removed unconditional `onMarkDirty()` calls from gig name/city autocomplete `onChange` in `gig_form_fields.dart` so initial controller echo cannot mark the parent dirty outside real edits.
- Added a one-time guard in `_fetchGigNameSuggestions` to skip the first seeded query pass during autocomplete attach; this prevents a `setState()` write from the filter-load path during build while preserving normal suggestion updates after initial attach.

### Round 2 Verification

- Ran `flutter analyze` after the fix: **No issues found**.
- Launched the app on a real iPhone target with `./run.sh 00008150-00026D523490C01C` and confirmed the app initializes normally with no immediate framework assertion.
- Executed a hot restart successfully (`mcp_dart_and_flut_hot_restart`) against the active VM service.
- Verified by code-path inspection that:
  - initial identical controller echo now exits without `setState()`/`_markDirty()`
  - genuine user edits (non-identical text) still mutate state and mark dirty.

### Round 2 Notes

- This follow-up is intentionally minimal and localized to the three callbacks in `event_editor_drawer.dart`.
- No persistence logic, schema, routing, auth, or initialization behavior was changed.
