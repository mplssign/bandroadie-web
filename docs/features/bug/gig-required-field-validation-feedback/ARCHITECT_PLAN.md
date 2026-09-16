# Architect Plan

## Feature Slug

`bug/gig-required-field-validation-feedback`

## Feature Title

Add Event form gives no indication of which required fields are missing

## Problem Summary

In the Add Event bottom sheet (create mode), the Create button is disabled whenever
a required field is empty — `Gig Name` and `City` for a gig, `Location` for a
rehearsal. Nothing on the form tells the user which field is required, why the
button is disabled, or what to fill in. Tony hit this on iOS trying to create a
gig, but the Add Event sheet is shared across all four platforms, so the same
behavior ships everywhere.

## Root Cause

**HIGH confidence.** `_canSave` in [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L3135-L3146)
computes button enablement, in create mode, as a boolean check that required
autocomplete text fields (`_gigNameText`, `_gigCityText`,
`_rehearsalLocationText`) are non-empty:

```dart
return switch (_eventType) {
  EventType.gig => (_gigNameText?.trim().isNotEmpty ?? false) &&
      (_gigCityText?.trim().isNotEmpty ?? false),
  EventType.rehearsal =>
    (_rehearsalLocationText?.trim().isNotEmpty ?? false),
  EventType.blockOut => true,
};
```

The drawer already carries a complete inline-error path — a `_fieldErrors:
Map<String, String>` map ([event_editor_drawer.dart#L240](lib/features/events/widgets/event_editor_drawer.dart#L240)),
population from `_handleSave` after running `EventFormData.validate()`
([event_editor_drawer.dart#L1836-L1866](lib/features/events/widgets/event_editor_drawer.dart#L1836-L1866)),
prop threading to `GigFormFields` / `RehearsalFormFields` under `fieldErrors:`,
render via `FAutocomplete(forceErrorText: ...)` on the gig-name, city, and
rehearsal-location fields ([gig_form_fields.dart#L978-L979](lib/features/events/widgets/gig_form_fields.dart#L978-L979),
[gig_form_fields.dart#L1028-L1029](lib/features/events/widgets/gig_form_fields.dart#L1028-L1029),
[rehearsal_form_fields.dart#L169-L170](lib/features/events/widgets/rehearsal_form_fields.dart#L169-L170)),
and clearing on user typing. That whole path is dead in the reported scenario
because `_canSave` gates the button off, so `_handleSave` never runs and
`_fieldErrors` never gets populated. On top of that, there is no proactive
"required" affordance on the labels themselves.

Block-outs already return `true` unconditionally in `_canSave` and rely on
`_saveBlockOut` to validate — that pattern is the correct one; gigs and
rehearsals should match it.

## Existing System Analysis

- `EventEditorDrawer` (single-source-of-truth create/edit sheet for gigs,
  rehearsals, block-outs) hosts `_canSave` and `_handleSave`. `_handleSave`
  already performs the correct sequence: clear errors → rehearsal-location
  guard → contact-resolution guard → `EventFormData.validate()` → map validation
  strings to `_fieldErrors['name'|'city'|'location']` for inline rendering,
  keep the first error in `_errorMessage` for the top-of-form error banner
  ([event_form_fields.dart#L161-L184](lib/features/events/widgets/event_form_fields.dart#L161-L184)).
- `_fieldErrors[key]` is cleared as the user types in the corresponding
  autocomplete (`onGigNameTextChanged`, `onGigCityTextChanged`,
  `onLocationTextChanged` at [event_editor_drawer.dart#L2509-L2530](lib/features/events/widgets/event_editor_drawer.dart#L2509-L2530)
  and [event_editor_drawer.dart#L2414-L2416](lib/features/events/widgets/event_editor_drawer.dart#L2414-L2416)), so per-field errors
  auto-clear on edit — exactly what the report asks for.
- `EventFormData.validate()` ([event_form_data.dart#L437](lib/features/events/models/event_form_data.dart#L437))
  is the canonical list of required-field rules for gigs (gig name, city,
  potential-gig member selection, recurrence day selection). Rehearsal
  `location` is enforced inline in `_handleSave` at
  [event_editor_drawer.dart#L1836-L1839](lib/features/events/widgets/event_editor_drawer.dart#L1836-L1839).
  We are keeping both rule sources as-is; the fix does not touch validation
  rules, only reachability of the existing rules.
- The codebase has a precedent for the `*` required-marker convention in the
  same feature: the create-contact dialog uses `labelText: 'Name *'` at
  [gig_form_fields.dart#L211](lib/features/events/widgets/gig_form_fields.dart#L211).

## Proposed Solution

Minimal, two-part fix in the existing widgets — no new files, no new state
plumbing, no new validation code.

1. **Make Create reachable so the existing validation path runs.** In
   `_canSave`, drop the required-field-content check. Keep the disable guards
   for `_isEditingExpense`, `_isSaving`, `_isDeleting`, `viewOnly`, and the
   edit-mode `_isDirty` gate exactly as they are. Return `true` for all three
   event types in create mode; `_handleSave` (unchanged) already produces the
   right inline `_fieldErrors` and top-of-form banner when the user submits an
   invalid gig or rehearsal. This aligns gigs and rehearsals with the pattern
   block-outs already use.

2. **Add a proactive required marker to the three required labels** in
   create mode, matching the existing `Name *` precedent in the same feature.
   The `Text('Gig Venue / Festival / Name', …)` at
   [gig_form_fields.dart#L980-L983](lib/features/events/widgets/gig_form_fields.dart#L980-L983)
   becomes `'Gig Venue / Festival / Name *'`, `Text('City', …)` at
   [gig_form_fields.dart#L1032-L1035](lib/features/events/widgets/gig_form_fields.dart#L1032-L1035)
   becomes `'City *'`, and `Text('Location', …)` at
   [rehearsal_form_fields.dart#L173-L176](lib/features/events/widgets/rehearsal_form_fields.dart#L173-L176)
   becomes `'Location *'`. Plain string change, no styling tokens introduced.

Result: user opens the sheet, sees `*` on the required labels, taps Create
without filling them → Create is now enabled → `_handleSave` runs
`EventFormData.validate()` and (for rehearsal) the inline location check →
`forceErrorText` renders "Gig name is required" / "City is required" /
"Location is required" directly under each empty field, and the error banner
shows the first message → user types into a flagged field, its error clears
inline, banner text stays until the next Save attempt (existing behavior).

## Database Impact

n/a

## Flutter Architecture Changes

n/a — reuses existing `_fieldErrors` / `FAutocomplete.forceErrorText` /
`EventFormData.validate()` infrastructure. No new controllers, providers,
repositories, models, services, widgets, files, or dependencies.

## Files to Create

n/a

## Files to Modify

- [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) —
  `_canSave` getter only: drop the `switch (_eventType)` non-empty-text check
  for `gig` and `rehearsal`, return `true` in create mode across all three
  event types. All other guards (`_isEditingExpense`, `_isSaving`,
  `_isDeleting`, `widget.viewOnly`, and edit-mode `_isDirty`) stay untouched.
  No changes to `_handleSave`, `_fieldErrors` clearing, `_errorMessage`, or
  any other logic.
- [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) —
  string-only edits to two `Text(...)` labels: the `Gig Venue / Festival /
  Name` label inside `_buildGigNameAutocomplete` (around
  [line 982](lib/features/events/widgets/gig_form_fields.dart#L982)) becomes
  `'Gig Venue / Festival / Name *'`, and the `City` label inside
  `_buildGigCityAutocomplete` (around
  [line 1033](lib/features/events/widgets/gig_form_fields.dart#L1033)) becomes
  `'City *'`. No other edits.
- [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart) —
  string-only edit to one `Text(...)` label: the `Location` label inside
  `_buildLocationAutocomplete` (around
  [line 174](lib/features/events/widgets/rehearsal_form_fields.dart#L174))
  becomes `'Location *'`. No other edits.
- [test/features/events/widgets/event_dropdown_test.dart](test/features/events/widgets/event_dropdown_test.dart) —
  edits confined to `group('EventEditorDrawer setlist selector (rehearsal)',
  ...)` only (around
  [lines 337-451](test/features/events/widgets/event_dropdown_test.dart#L337-L451)).
  The existing test case `'create mode requires location and preserves
  enablement across setlist selection'` directly encodes the pre-gating
  behavior this fix removes — its three
  `expect(addButton().onPressed, isNull);` assertions (initial state, after
  tapping `Road Set`, after tapping `None`) assert that the Add Rehearsal
  button is disabled until location is filled. Update per Engineer Task
  Breakdown item 5: flip the two post-selection assertions to `isNotNull`,
  drop the initial `isNull` assertion (its intent is superseded by the new
  sibling test), rename the case description accordingly, and add one new
  sibling `testWidgets` case in the same group covering empty-location
  Add Rehearsal → inline error surfacing + no repository call. The other
  three test groups in this file (`'EventDropdown'`, `'AppDropdown Form
  integration'`, `'EventEditorDrawer layout'`) are off-limits — they cover
  unrelated concerns.

## Files Off-Limits

- [lib/features/events/models/event_form_data.dart](lib/features/events/models/event_form_data.dart) —
  do not touch `validate()`; the rule set is correct as-is, and changing
  wording would break the `errorMsg.contains('Gig name is required')` /
  `errorMsg.contains('City is required')` mapping in `_handleSave`.
- [lib/features/events/widgets/event_editor_actions.dart](lib/features/events/widgets/event_editor_actions.dart) —
  the `canSave` parameter and Cancel/Save render are correct as-is. Fix is
  upstream of it.
- [lib/features/events/widgets/event_form_fields.dart](lib/features/events/widgets/event_form_fields.dart) —
  shared date/time/duration/setlist fields are not the required-field surface;
  no edits.
- Any file under [lib/features/events/widgets/](lib/features/events/widgets/)
  or [lib/features/events/models/](lib/features/events/models/) beyond the
  three listed under Files to Modify.
- All Supabase migrations, RPC functions, edge functions, routing, auth, init
  order — untouched.
- `PR #314` (`bug/add-event-keyboard-overlap`) is unrelated prior art on the
  same sheet; do not rebase on it or coordinate with it. Fix off current
  `main` only.

## Change Budget

- `event_editor_drawer.dart`: net delta roughly `-4` lines (the four-line
  `switch (_eventType)` block inside `_canSave` collapses to a single `return
  true;`). Zero other lines touched.
- `gig_form_fields.dart`: net delta `0` lines (two `Text(...)` string literals
  updated).
- `rehearsal_form_fields.dart`: net delta `0` lines (one `Text(...)` string
  literal updated).
- `event_dropdown_test.dart`: net delta ~`+60` lines (Cycle 2 re-baseline
  from the amendment's initial ~`+22` estimate — QA-measured `+65`/`-5` =
  `+60` net; the initial estimate under-counted the size of task 5(b)'s
  plan-mandated verbatim setup boilerplate). All changes stay inside
  `group('EventEditorDrawer setlist selector (rehearsal)', ...)`.
  Amended existing case nets ~`-2` (drop the initial
  `expect(addButton().onPressed, isNull);` plus its adjacent blank line =
  `-2`; the two flipped `isNull` → `isNotNull` assertions and the
  description rename are same-length `0`-net edits). New sibling
  `testWidgets` case adds `+62` lines concentrated in setup: ~`49`
  boilerplate lines the plan mandates verbatim (`tester.view` resets,
  `Supabase.initialize` `try/catch`, `_CapturingEventsRepository?`
  declaration with the nullable-comment line because the location guard
  short-circuits before it is assigned, six `ProviderScope` overrides —
  `setlistsProvider`, `membersProvider`, `venuesProvider`,
  `contactsProvider`, `blockOutRepositoryProvider`, and the multi-line
  `eventsRepositoryProvider` lambda — and the `MaterialApp` /
  `AppTheme.darkTheme` / `Scaffold` / `EventEditorDrawer` tree with
  `pumpAndSettle`) plus ~`13` body lines (helper declaration, initial
  enablement assertion, tap + `pumpAndSettle`, two outcome assertions,
  with separating blanks). Duplication is intentionally not factored
  into a shared helper — task 5(b) requires the new case's setup to
  match the amended case verbatim, so extracting one would force
  reopening the amended case's inline setup as well and broaden a
  targeted bug fix into a test-file refactor with no safety benefit;
  each case's overrides stay locally visible for debuggability. Zero
  lines touched in the file's other three test groups.
- New files: `0` under the amendment (Task 4's
  [test/features/events/widgets/gig_form_fields_test.dart](test/features/events/widgets/gig_form_fields_test.dart)
  entry stands as originally scoped — new file only if none exists).
- New public classes / methods: `0`.
- New dependencies: `0`.
- Test files touched: `2` — [test/features/events/widgets/rehearsal_form_fields_test.dart](test/features/events/widgets/rehearsal_form_fields_test.dart)
  (extended in place per task 4) and
  [test/features/events/widgets/event_dropdown_test.dart](test/features/events/widgets/event_dropdown_test.dart)
  (edited in place per task 5). Task 4's
  [test/features/events/widgets/gig_form_fields_test.dart](test/features/events/widgets/gig_form_fields_test.dart)
  is created only if it does not already exist. No other test file may be
  touched.

## System Impact Map

- **Gigs** — affected. Create-mode Save button enablement and required-label
  affordance change. No data model, no repository, no controller changes.
- **Rehearsals** — affected. Same as gigs (location label + button
  enablement).
- **Setlists** — unaffected.
- **Members** — unaffected. Potential-gig member-selection validation
  ("Select at least one member for potential gig") stays surfaced via the
  existing top-of-form `_errorMessage` banner exactly as it is today.
- **Auth** — unaffected.
- **Routing** — unaffected.
- **Notifications** — unaffected.
- **Platforms** — iOS, Android, macOS, Web all get the same fix because the
  edited widgets are the shared implementation. No platform-conditional code.

## Regression Risk

**LOW.** Scope is a single boolean getter and three string literals. No auth,
session, routing, init-order, DB, RLS, migrations, RPCs, edge functions, or
persistence code touched. The edit-mode `_isDirty` gate is preserved
verbatim, so "Save is disabled until I actually edit something" behavior in
edit mode does not change. `_handleSave` already handles every current
validation rule, so widening button reachability cannot introduce a
validation-bypass path. Block-out create behavior is unchanged (`_canSave`
already returned `true` for it). The only user-visible behavior deltas are
(a) the three required labels now end in ` *`, and (b) tapping Create with
required gig / rehearsal fields empty now shows the same inline + banner
errors that the edit-mode invalid-save path already shows today.

## Engineer Task Breakdown

1. In [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart),
   replace the create-mode `switch (_eventType)` inside `_canSave` with a
   single `return true;`. Leave the guard block (`_isEditingExpense`,
   `_isSaving`, `_isDeleting`, `widget.viewOnly`) and the edit-mode `if
   (widget.mode == EventEditorMode.edit) return _isDirty;` line untouched.
2. In [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart),
   update the `Text('Gig Venue / Festival / Name', …)` literal in
   `_buildGigNameAutocomplete` to `'Gig Venue / Festival / Name *'`, and the
   `Text('City', …)` literal in `_buildGigCityAutocomplete` to `'City *'`.
   Style (`AppTextStyles.footnote`, `textSecondary`) unchanged.
3. In [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart),
   update the `Text('Location', …)` literal in `_buildLocationAutocomplete`
   to `'Location *'`. Style unchanged.
4. In [test/features/events/widgets/rehearsal_form_fields_test.dart](test/features/events/widgets/rehearsal_form_fields_test.dart),
   add one small test group that pumps the full `RehearsalFormFields` widget
   (following the existing `_PotentialSectionWrapper` pattern but rendering
   the widget's full `build` method), asserts `find.text('Location *')`
   matches, and pumps a second variant with `fieldErrors: {'location':
   'Location is required'}` that asserts `find.text('Location is required')`
   renders. Add an equivalent small test at
   [test/features/events/widgets/gig_form_fields_test.dart](test/features/events/widgets/gig_form_fields_test.dart)
   (new file only if none exists; keep to one `group` covering gig-name and
   city labels + one `fieldErrors`-driven case per field). Do not attempt
   to widget-test `_canSave` — the drawer is not isolatable at that grain;
   see Verification Plan.
5. In [test/features/events/widgets/event_dropdown_test.dart](test/features/events/widgets/event_dropdown_test.dart),
   make two edits, both confined to `group('EventEditorDrawer setlist
   selector (rehearsal)', ...)`:

   **a. Amend the existing test case** —
   `testWidgets('create mode requires location and preserves enablement
   across setlist selection', ...)`. Rename the description to
   `'create mode preserves button enablement across setlist selection'`.
   Delete the first `expect(addButton().onPressed, isNull);` assertion —
   the one that runs BEFORE any setlist interaction, right after the
   `addButton()` helper is declared. Its intent ("button is disabled at
   open because location is empty") is exactly the pre-gating behavior
   this fix removes; the new sibling test in step 5(b) covers what should
   happen instead. Change the two remaining `expect(addButton().onPressed,
   isNull);` assertions to `expect(addButton().onPressed, isNotNull);` —
   the one immediately after the `Road Set` tap + `pump()`, and the one
   immediately after the `None` tap + `pump()`. Leave every other line in
   this test case verbatim: the `tester.view.resetPhysicalSize()` /
   `resetDevicePixelRatio()` setup, the `try { await Supabase.initialize(...) }
   catch (_) {}` block, the `_CapturingEventsRepository repository`
   declaration, the `ProviderScope` overrides (`setlistsProvider`,
   `membersProvider`, `venuesProvider`, `contactsProvider`,
   `blockOutRepositoryProvider`, `eventsRepositoryProvider`), the
   `MaterialApp`/`Scaffold`/`EventEditorDrawer` tree, `find.text('Details')`
   and the `Road Set`-vs-`Notes (optional)` ordering check, the
   `AppButton addButton()` helper, the setlist-tap sequence, the
   `find.byType(FAutocomplete<String>)` location finder, the
   `FlutterError.onError` capture/restore block, the `'T'` and
   `'Test Studio'` typing sequence with its `findsNothing` assertions on
   `AppIcons.error` and `'Location is required'`, the final `Road Set`
   re-tap + `Add Rehearsal` tap + `capturedFormData.location` and
   `capturedFormData.setlistId` assertions, and the entire second `None`
   scenario at the end (setlist cleared → `Add Rehearsal` → captured form
   data with `setlistId` null) — all stay untouched.

   **b. Add one new sibling `testWidgets` case** immediately after the
   amended one in the same group, titled `'create mode with empty
   location surfaces inline error and does not call repository'`. Follow
   the identical setup boilerplate as the amended case in step 5(a) (same
   `tester.view` resets, same `try/catch` around `Supabase.initialize`,
   same `_CapturingEventsRepository repository` declaration, same six
   `ProviderScope` overrides — `setlistsProvider`, `membersProvider`,
   `venuesProvider`, `contactsProvider`, `blockOutRepositoryProvider`,
   `eventsRepositoryProvider` — same `MaterialApp` / `AppTheme.darkTheme` /
   `Scaffold` / `EventEditorDrawer(initialEventType: EventType.rehearsal,
   bandId: 'test-band-id')` tree, `await tester.pumpAndSettle();`). The
   body is exactly three steps:

   1. Declare `AppButton addButton() => tester.widget<AppButton>(find.widgetWithText(AppButton,
      'Add Rehearsal'));` (identical helper to the amended case), then
      `expect(addButton().onPressed, isNotNull);` — confirms the button is
      enabled from the moment the drawer opens, without any location text
      or setlist selection.
   2. `await tester.tap(find.text('Add Rehearsal'));` followed by
      `await tester.pumpAndSettle();`.
   3. `expect(find.text('Location is required'), findsAtLeastNWidgets(1));`
      — the fix's `_handleSave` populates both the inline
      `forceErrorText` under the location autocomplete AND the top-of-form
      `_errorMessage` banner with this string, so at least one match is
      guaranteed and either or both is acceptable; the test's intent is
      only "user sees which field is missing", not counting error surfaces.
      Then `expect(repository.capturedFormData, isNull);` — confirms
      `_handleSave` short-circuited on the rehearsal-location guard at
      [event_editor_drawer.dart#L1836-L1839](lib/features/events/widgets/event_editor_drawer.dart#L1836-L1839)
      before ever calling `EventsRepository.createRehearsal`.

   Do not tap the location autocomplete, do not select a setlist, do not
   type anything, and do not add any assertions beyond these two — the
   test is deliberately minimal and scoped to the empty-tap error path
   only.

   Do not modify `group('EventDropdown', ...)`, `group('AppDropdown Form
   integration', ...)`, or `group('EventEditorDrawer layout', ...)` in
   this file — those groups cover unrelated concerns (dropdown rendering,
   Form integration, layout-error smoke) and are off-limits for this fix.

## Verification Plan

**Tier 1 (pre-deploy, mechanically executable by QA in this pipeline):**

- `flutter analyze` on the three edited source files and any touched tests is
  clean — zero new warnings, zero new lints.
- `flutter test test/features/events/widgets/rehearsal_form_fields_test.dart`
  passes, including the new `'Location *'` label case and the
  `fieldErrors`-driven `'Location is required'` case.
- `flutter test test/features/events/widgets/gig_form_fields_test.dart`
  passes with the new gig-name and gig-city label + `fieldErrors` cases.
- `flutter test test/features/events/widgets/event_dropdown_test.dart`
  passes, including the amended
  `'create mode preserves button enablement across setlist selection'`
  case (three `isNull` assertions replaced per task 5(a)) and the new
  `'create mode with empty location surfaces inline error and does not
  call repository'` sibling case (task 5(b)). The other three groups in
  this file (`'EventDropdown'`, `'AppDropdown Form integration'`,
  `'EventEditorDrawer layout'`) must remain green with zero assertion
  changes — they were passing before and are structurally unaffected by
  this fix.
- `flutter test` full pass — no regression in the existing
  `rehearsal_form_fields_test.dart` potential-toggle tests or any other
  event-widget test.

QA never launches the app, boots a simulator, or drives a running instance.

**Tier 2 (owner-run by Tony at PR-test time — QA hands this list to Tony
verbatim, does not attempt it):**

1. On iOS build, open the Add Event sheet, select `Gig`. Expected: the gig
   name and city field labels read `Gig Venue / Festival / Name *` and
   `City *`; the Create button is enabled (not greyed out).
2. Tap Create without touching any field. Expected: `Gig name is required`
   appears in red directly under the gig name field via
   `forceErrorText`; `City is required` appears in red under the city
   field; the top-of-form error banner shows `Gig name is required` (first
   validation error).
3. Type any character into the gig name field. Expected: the inline
   `Gig name is required` under the gig name field disappears immediately;
   the city inline error stays; the banner stays.
4. Clear the gig name field again and tap Create. Expected: `Gig name is
   required` returns inline.
5. Fill gig name and city with real values, tap Create. Expected: gig
   creates successfully — the fix has not blocked the happy path.
6. Switch to `Rehearsal`. Expected: label reads `Location *`, Create button
   is enabled.
7. Tap Create without filling location. Expected: `Location is required`
   inline under the location field and in the banner.
8. Fill location, tap Create. Expected: rehearsal creates successfully.
9. Switch to `Block Out`. Expected: no `*` labels added (out of scope), Save
   still works exactly as it does today.
10. Open an existing gig in edit mode without modifying anything. Expected:
    Save button is disabled (edit-mode `_isDirty` gate still in effect).
    Change any field and re-check: Save becomes enabled.
11. Repeat step 2 on Android, macOS, and Web builds. Expected: identical
    behavior on all four platforms.

## QA Regression Areas

- Existing event-widget tests under `test/features/events/widgets/` still
  green.
- `flutter analyze` clean across the whole workspace (no lint drift
  introduced by the string edits or the `_canSave` shrink).
- Static review: confirm no file outside the three listed under Files to
  Modify (plus test files) is diffed. Confirm the diff to
  `event_editor_drawer.dart` is confined to the `_canSave` getter body.

## Rollout Strategy

Single PR to `main` off branch
`bug/gig-required-field-validation-feedback`. No feature flag, no
migration, no staged rollout — client-only UX change on a shared widget,
identical behavior across all four platforms.

## Out of Scope

- Any change to `EventFormData.validate()` or to the mapping strings
  (`'Gig name is required'`, `'City is required'`) — the mapping in
  `_handleSave` depends on those literals.
- Any change to the top-of-form error banner styling or placement.
- Adding `*` markers to any field outside the three required labels (e.g.,
  block-out date labels, notes, load-in time, member-selection, setlist
  picker, contact rows).
- On-blur validation for autocomplete fields — the report explicitly
  accepts "on attempted submit OR on blur" and the on-submit path is
  cheaper and consistent with what block-outs already do.
- Screen-reader `Semantics(required: true)` wrapping — accessibility
  hardening deserves its own feature, and `FAutocomplete.forceErrorText`
  already announces the validation error through the platform accessibility
  layer.
- Any change unrelated to required-field feedback (refactors, renames, new
  helpers, new dependencies).
- Coordination with or rebase on `PR #314`
  (`bug/add-event-keyboard-overlap`) — treated as unrelated prior art.

## Amendments

**Amendment 1 (mid-implementation).** During Engineer's implementation of
this plan, the full `flutter test` sweep surfaced a pre-existing failure in
[test/features/events/widgets/event_dropdown_test.dart](test/features/events/widgets/event_dropdown_test.dart)
— specifically the case `'create mode requires location and preserves
enablement across setlist selection'` inside `group('EventEditorDrawer
setlist selector (rehearsal)', ...)` (around
[lines 337-451](test/features/events/widgets/event_dropdown_test.dart#L337-L451)).
That case's three `expect(addButton().onPressed, isNull);` assertions
directly encode the pre-gating behavior this fix intentionally removes, so
under the corrected `_canSave` it fails deterministically. The file was not
in the original Files to Modify / Files Off-Limits / Change Budget scope.

Added [test/features/events/widgets/event_dropdown_test.dart](test/features/events/widgets/event_dropdown_test.dart)
to **Files to Modify** (edits confined to the one setlist-selector rehearsal
group only), bumped the **Change Budget** test-file count from `at most 1`
to `2` with a new `event_dropdown_test.dart` per-file delta entry, added
**Engineer Task Breakdown item 5** with precise 5(a) / 5(b) instructions,
and added a corresponding **Verification Plan Tier 1** entry. The other
three test groups in this file (`'EventDropdown'`, `'AppDropdown Form
integration'`, `'EventEditorDrawer layout'`) remain off-limits — they are
structurally unaffected by this fix.

The empty-location error-surfacing check is delivered as a new *sibling*
`testWidgets` case, not folded into the existing one, because the drawer's
top-of-form `_errorMessage` banner and its `AppIcons.error` icon persist
after typing (`onLocationTextChanged` at
[event_editor_drawer.dart#L2407-L2418](lib/features/events/widgets/event_editor_drawer.dart#L2407-L2418)
clears `_fieldErrors['location']` only, not `_errorMessage`). Firing the
empty-tap first inside the existing test would cause its later
`find.byIcon(AppIcons.error), findsNothing` and
`find.text('Location is required'), findsNothing` assertions (after typing
`'T'` / `'Test Studio'`) to fail spuriously. A separate sibling test with a
fresh drawer instance keeps state isolated and preserves the full setlist-
selection interplay coverage in the original case.

Scope of the fix (source diff to `event_editor_drawer.dart`,
`gig_form_fields.dart`, `rehearsal_form_fields.dart`) is otherwise
unchanged; Regression Risk stays **LOW**; Files Off-Limits, System Impact
Map, Rollout Strategy, and Out of Scope are unaffected.
