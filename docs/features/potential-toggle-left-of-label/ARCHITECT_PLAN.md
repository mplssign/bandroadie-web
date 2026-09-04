# ARCHITECT_PLAN.md

## Feature Slug
`potential-toggle-left-of-label`

## Feature Title
Move Potential Rehearsal/Gig toggle to the left of its label

## Problem Summary
The "Potential Rehearsal" / "Potential Gig" toggle switch currently sits on the
right side of its label row inside the add/edit event sheet(s). It should sit to
the LEFT of the "Potential Rehearsal" / "Potential Gig" text instead.

Applies identically to both the rehearsal and gig variants of the add/edit
sheet, on all platforms (iOS, Android, macOS, Web). Pure widget-tree layout
change — no platform-conditional code, no state, no data.

## Root Cause
**Confidence: HIGH** (confirmed in code).

There are exactly two call sites that render the "Potential" label + `AppSwitch`
pair. Both share an identical structural pattern:

```dart
Row(
  children: [
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Potential Rehearsal' | 'Potential Gig', ...),
          // optional subtext / SizedBox
        ],
      ),
    ),
    AppSwitch(value: ..., onChanged: ...),
  ],
),
```

The `AppSwitch` is the *last* child of the `Row`, so it renders to the right of
the `Expanded` label column. To place it on the left, it must become the *first*
child of the `Row`, with a horizontal gap between it and the `Expanded` label
column.

The two locations:

1. [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart)
   inside `_buildPotentialToggle` — Row at line 236, `AppSwitch` at lines
   259–262 (label at line 242).
2. [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart)
   inside `_buildPotentialGigContainer` — Row at line 1108, `AppSwitch` at lines
   1130–1134 (label at line 1115).

A workspace-wide search for the literal label strings `'Potential Rehearsal'`
and `'Potential Gig'` returns hits only in these two files (all other matches
are documentation, comments, or unrelated identifiers). No shared widget
abstracts this row today.

## Existing System Analysis
- Both call sites are wrapped in an `AnimatedContainer` (200 ms, `Curves.easeOut`)
  with a rose primary border applied when the toggle is ON. That container is
  outside the `Row`, so reordering the `Row`'s children does not affect the
  container animation.
- The rehearsal side gates its subtext behind `if (isPotential) ...[ ... ]`
  (added by the prior feature `potential-rehearsal-subtext-when-enabled`). The
  gig side renders its subtext unconditionally. Both patterns are inside the
  `Expanded(child: Column(...))`, so they are unaffected by moving the switch
  from the tail of the `Row` to the head.
- `Row.crossAxisAlignment` defaults to `CrossAxisAlignment.center` in both call
  sites (not explicitly set). With the switch centered vertically against a
  one-or-two-line label column, the visual balance is identical whether the
  switch is on the left or the right of the `Expanded`.
- `AppSwitch` ([lib/components/ui/app_switch.dart](lib/components/ui/app_switch.dart))
  wraps forui's `FSwitch` and supports a `leadingLabel: true` + `label: Widget`
  API. That API is **not** used here because the label column also contains an
  optional subtext and (via the container above) member-availability content;
  routing the label through `AppSwitch.label` would restructure the widget
  significantly. Rejected — see Proposed Solution.
- Both files consume `Spacing` design tokens from
  [lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart)
  (`Spacing.space12` is used for both container padding and the header-row
  spacing convention). `Spacing.space12` is the appropriate horizontal gap
  between the switch and the label column.
- Ownership of the toggle *state* (`_isPotentialGig`) lives in
  [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
  and is passed down into both form-field widgets as `isPotential` /
  `isPotentialGig`. The drawer does not render any additional toggle UI of its
  own — it delegates to `_createRehearsalFormFields().buildPotentialSection(...)`
  (line 3029) and to `GigFormFields` (line 2479). No drawer changes are needed.

## Proposed Solution
In each of the two `Row` widgets, swap the child order so that `AppSwitch(...)`
becomes the first child and the `Expanded(child: Column(...))` label block
becomes the last child. Insert `const SizedBox(width: Spacing.space12)` between
them so the switch does not touch the label text.

Verbatim per-file transform:

```dart
Row(
  children: [
    // NEW: switch first
    AppSwitch(
      value: <isPotential | isPotentialGig>,
      onChanged: <same expression as before>,
    ),
    const SizedBox(width: Spacing.space12),
    // MOVED: existing Expanded label column, unchanged
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Potential Rehearsal' | 'Potential Gig', ...),
          // optional subtext (unchanged)
        ],
      ),
    ),
  ],
),
```

The `AppSwitch(...)` block is moved verbatim — same `value:`, same `onChanged:`
expression (rehearsal: `isSaving ? null : onPotentialToggled`, gig:
`(isSaving || forcePotentialOnly) ? null : onPotentialGigToggled`). The
`Expanded(child: Column(...))` block is moved verbatim — including the
conditional `if (isPotential) ...[ SizedBox(height: 2), Text('Toggle off ...') ]`
on the rehearsal side and the unconditional two-line title+subtext block on the
gig side.

`Row.crossAxisAlignment` is left at its default (`center`) — the switch
naturally centers against the one-or-two-line label column, matching current
visual behavior.

**Rejected alternatives:**

- **`AppSwitch(leadingLabel: true, label: <Column>)`** — this would restructure
  the row into a single `AppSwitch` widget with an internal label, but the
  label column here is not just text: it also participates in `Expanded` sizing
  and (on the gig side) has a subtext. Routing it through the `AppSwitch.label`
  slot changes layout constraints and how the label wraps under narrow widths,
  and it removes the `Expanded` layer that keeps the label taking remaining
  width. Not minimal; rejected.
- **Wrap the `Row` in `Directionality(textDirection: TextDirection.rtl)`** — a
  layout hack that would flip text direction of any localized string inside
  and would fight future RTL localization support. Rejected.
- **Extract a shared `PotentialToggleRow` widget** — only two callers, and the
  two callers differ in subtext gating and in the disabled-state expression
  (`forcePotentialOnly` on the gig side, absent on the rehearsal side). Not
  worth a new abstraction; would be opportunistic scope creep. Rejected.
- **Use `Row(children: [AppSwitch, Padding(padding: EdgeInsets.only(left: 12), child: Expanded(...))])`** —
  functionally equivalent to a `SizedBox(width: Spacing.space12)` spacer but
  less idiomatic for this codebase (existing rows in these two files already
  use `SizedBox(width: …)` for horizontal gaps). Rejected in favor of the
  `SizedBox` spacer.

## Database Impact
`not applicable`.

No schema change, no migration, no RLS policy, no RPC function, no trigger, no
edge function, no data access change.

## Flutter Architecture Changes
None. No new controllers, providers, repositories, models, services, routes, or
state. No changes to init order, config, `--dart-define`, or platform-conditional
code. No new dependencies. Widget-tree layout only.

## Files to Create
None.

The existing rehearsal widget test file
[test/features/events/widgets/rehearsal_form_fields_test.dart](test/features/events/widgets/rehearsal_form_fields_test.dart)
already has a `_pumpPotentialSection` scaffold that renders only the potential
toggle section — the new position-assertion test case is added inside its
existing `group(...)`.

## Files to Modify
- [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart)
  — inside `_buildPotentialToggle` (starts line 219), in the `Row` at line 236:
  move the `AppSwitch(...)` block (currently lines 259–262) so it becomes the
  first child of `Row.children`, and insert
  `const SizedBox(width: Spacing.space12),` between the switch and the existing
  `Expanded(...)` block (currently lines 237–258). Preserve every other line
  verbatim — same `value:`, same `onChanged:` expression, same `Expanded`,
  same `Column`, same `Text('Potential Rehearsal', ...)`, same conditional
  subtext block, same `AnimatedContainer`, same padding, same border logic.

- [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart)
  — inside `_buildPotentialGigContainer` (starts line 1088), in the `Row` at
  line 1108: move the `AppSwitch(...)` block (currently lines 1130–1134) so it
  becomes the first child of `Row.children`, and insert
  `const SizedBox(width: Spacing.space12),` between the switch and the existing
  `Expanded(...)` block (currently lines 1109–1129). Preserve every other line
  verbatim — including the `(isSaving || forcePotentialOnly)` disabled
  expression, the `AnimatedSize`-wrapped member grid below the row, and the
  container padding/border.

- [test/features/events/widgets/rehearsal_form_fields_test.dart](test/features/events/widgets/rehearsal_form_fields_test.dart)
  — add ONE new `testWidgets` case inside the existing
  `group('RehearsalFormFields potential toggle subtext', ...)` group (rename
  the group description if desired, but a rename is optional). The new case
  pumps the potential section with `isPotential: true` and asserts that
  `tester.getTopLeft(find.byType(AppSwitch)).dx <
  tester.getTopLeft(find.text('Potential Rehearsal')).dx`. Add the
  `import 'package:bandroadie/components/ui/app_switch.dart';` at the top of
  the test file. Do not touch the existing two subtext-gating cases.

## Files Off-Limits
- [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
  — parent drawer owns `_isPotentialGig` state and wires callbacks down into
  both form-field widgets. No prop shape or callback signature changes are
  needed. Do not add a new toggle-position prop; the layout order is intrinsic
  to the widgets themselves.
- [lib/components/ui/app_switch.dart](lib/components/ui/app_switch.dart)
  — `AppSwitch` is a shared, cross-feature component. Do not modify it. Do not
  switch these call sites to use its `leadingLabel: true` / `label:` API — that
  would change layout constraints for the label column (see Proposed Solution
  → Rejected alternatives).
- [lib/features/events/widgets/event_form_fields.dart](lib/features/events/widgets/event_form_fields.dart)
  — the outer form-fields dispatch layer. Unaffected.
- Any other `lib/features/events/widgets/*.dart` file — no other file renders a
  "Potential" label + switch pair (verified via workspace-wide grep for the
  exact label strings).
- Any `lib/features/events/models/**`, `lib/features/events/*_repository.dart`,
  `lib/features/events/*_controller.dart`, `lib/features/rehearsals/**`,
  `lib/features/gigs/**` — no data-shape, controller, or repository changes.
- Any DB migration under `supabase/migrations/`, any RPC or RLS policy, any
  edge function under `supabase/functions/` — not applicable.
- `pubspec.yaml`, `analysis_options.yaml`, `--dart-define` config files,
  native entitlement/manifest files — not touched.
- `test/features/events/widgets/event_dropdown_test.dart` — unrelated test.

## Change Budget
- Net line delta per file:
  - `lib/features/events/widgets/rehearsal_form_fields.dart`: **+1 / −0**
    (`AppSwitch(...)` block moved verbatim from Row tail to Row head; one new
    `const SizedBox(width: Spacing.space12),` line inserted between switch and
    `Expanded`). Net **+1** because the switch block is preserved verbatim and
    a single spacer line is added.
  - `lib/features/events/widgets/gig_form_fields.dart`: **+1 / −0**
    (identical shape — `AppSwitch(...)` block moved from Row tail to Row head,
    one new `const SizedBox(width: Spacing.space12),` spacer line inserted).
  - `test/features/events/widgets/rehearsal_form_fields_test.dart`: **+~14 / −0**
    (one new `testWidgets` case added inside the existing group + one new
    import line for `AppSwitch`).
- Expected new files: **0**.
- Expected new public classes / methods: **0**.
- Expected new dependencies: **0**.

QA measures the actual diff against these numbers. A diff that adds a new
widget file, extracts a shared row helper, adds a new state field, or edits any
file listed under Files Off-Limits is over-budget and must be flagged.

## System Impact Map
- Rehearsals — **affected** (add/edit sheet potential-toggle row visual order
  only; no data shape, no state logic, no persistence changes, no callback
  signature changes).
- Gigs — **affected** (identical scope: add/edit sheet potential-toggle row
  visual order only).
- Setlists — unaffected.
- Members — unaffected. Member availability grid renders below the toggle row
  and is untouched.
- Auth / session / PKCE — unaffected.
- Routing / deep links — unaffected.
- Notifications / edge functions — unaffected.
- Init order (`WidgetsFlutterBinding` → URL strategy → orientation lock →
  `AppVersionService.init` → `validateSupabaseConfig` → `Supabase.initialize`
  → `Firebase.initializeApp` [native only] → `DeepLinkService` → `runApp`) —
  unaffected.
- Platforms (iOS / Android / macOS / Web) — **all** affected identically; no
  platform-conditional code involved, no native code, no `kIsWeb` branch.

## Regression Risk
**LOW.**

- Scope is a two-child reorder + one spacer line inside a single `Row`, in each
  of two widget files.
- No state, controller, provider, repository, model, callback signature, or
  persistence code changes.
- Auth, session, routing, init order, DB, RLS, RPC — none touched.
- The `AppSwitch` widget itself is unchanged — same `value:`, same `onChanged:`
  expression. The disabled logic (`isSaving`, `forcePotentialOnly`) is
  preserved verbatim.
- The member-availability grid (`AnimatedSize`-wrapped, rendered under the
  header row) is untouched — it remains inside the same `Column` under the
  reordered `Row`.
- The `AnimatedContainer` border + padding animation on `isPotential` transition
  is untouched.
- No new dependencies, no new imports beyond `Spacing` (already imported at the
  top of both files via `design_tokens.dart`).

## Engineer Task Breakdown
1. In [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart),
   inside `_buildPotentialToggle`, edit the `Row` at line 236: cut the entire
   `AppSwitch(value: isPotential, onChanged: isSaving ? null : onPotentialToggled)`
   block (currently the last child of `Row.children`), paste it as the *first*
   child of `Row.children`, and insert `const SizedBox(width: Spacing.space12),`
   immediately after it (before the existing `Expanded(...)` block). Preserve
   the `AppSwitch` arguments verbatim and the `Expanded(...)` block verbatim
   (including its internal `if (isPotential) ...[ ... ]` subtext gating). Do
   not touch the surrounding `AnimatedContainer`, its padding, its border logic,
   or the member-availability block below the `Row`.

2. In [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart),
   inside `_buildPotentialGigContainer`, edit the `Row` at line 1108: cut the
   entire `AppSwitch(value: isPotentialGig, onChanged: (isSaving || forcePotentialOnly) ? null : onPotentialGigToggled)`
   block (currently the last child of `Row.children`), paste it as the *first*
   child of `Row.children`, and insert `const SizedBox(width: Spacing.space12),`
   immediately after it (before the existing `Expanded(...)` block). Preserve
   the `AppSwitch` arguments verbatim and the `Expanded(...)` block verbatim
   (including its unconditional title + subtext). Do not touch the surrounding
   `AnimatedContainer`, its padding, its border logic, or the
   `AnimatedSize`-wrapped member grid below the `Row`.

3. In [test/features/events/widgets/rehearsal_form_fields_test.dart](test/features/events/widgets/rehearsal_form_fields_test.dart):
   - Add `import 'package:bandroadie/components/ui/app_switch.dart';` to the
     imports at the top of the file (alphabetized among the existing
     `package:bandroadie/...` imports).
   - Inside the existing `group('RehearsalFormFields potential toggle subtext', ...)`
     group, add one new `testWidgets` case titled
     `'AppSwitch renders to the left of the Potential Rehearsal label'`. The
     case calls `await _pumpPotentialSection(tester, isPotential: true);`
     (using `isPotential: true` so the subtext is present and the label
     column is at its wider layout), then asserts:
     ```dart
     final switchX = tester.getTopLeft(find.byType(AppSwitch)).dx;
     final labelX = tester.getTopLeft(find.text('Potential Rehearsal')).dx;
     expect(switchX, lessThan(labelX));
     ```
   - Do not modify the existing two subtext-gating cases.

4. Run `flutter analyze` locally and confirm zero new warnings, errors, or
   infos introduced by the changes. (Engineer runs analyze; Architect does not.)

## Verification Plan

### Tier 1 — pre-deploy (must pass before merge)

- **Static analysis:** `flutter analyze` — zero new warnings, errors, or infos
  introduced by the two modified widget files or the test file.

- **Widget test (`test/features/events/widgets/rehearsal_form_fields_test.dart`):**
  - Existing case *"subtext is absent when isPotential is false"* — must
    continue to pass unchanged. This confirms the prior-feature subtext gating
    is not accidentally broken by the reorder.
  - Existing case *"subtext is present when isPotential is true"* — must
    continue to pass unchanged. Same reason as above.
  - NEW case *"AppSwitch renders to the left of the Potential Rehearsal label"* —
    must pass. Pumps `_pumpPotentialSection(tester, isPotential: true)` and
    asserts `tester.getTopLeft(find.byType(AppSwitch)).dx <
    tester.getTopLeft(find.text('Potential Rehearsal')).dx`. This is a
    structural layout assertion that will fail if the switch is moved back to
    the right or wrapped in a widget that changes its position.

  Run with `flutter test test/features/events/widgets/rehearsal_form_fields_test.dart`.

- **Visual verification — macOS:**
  1. `flutter run -d macos` (or `./run.sh macos`).
  2. Sign in and select an active band.
  3. Open the "Add Event" sheet from the events tab or home screen.
  4. Switch the event type to **Rehearsal**. Scroll to the "Potential
     Rehearsal" row. Confirm the toggle switch renders to the LEFT of the
     "Potential Rehearsal" text, with visible horizontal spacing between them.
     Toggle it ON. Confirm the rose primary border appears on the surrounding
     container and the subtext *"Toggle off once confirmed to make it
     official."* appears under the title, both correctly aligned with the label
     column (not with the switch).
  5. Switch the event type to **Gig**. Scroll to the "Potential Gig" row.
     Confirm the toggle switch renders to the LEFT of the "Potential Gig" text,
     with visible horizontal spacing between them. Toggle it ON. Confirm the
     rose primary border appears and the (always-visible) subtext *"Toggle off
     once confirmed to make it official."* is left-aligned with the label
     column.
  6. Open an existing rehearsal for edit, then an existing gig for edit — the
     same layout must apply in edit mode as in add mode (both call sites are
     rendered via `_createRehearsalFormFields().buildPotentialSection(...)` /
     `_createGigFormFields()`, which are shared between add and edit).

- **Visual verification — web:**
  1. `flutter run -d chrome` (or `./run.sh chrome`).
  2. Repeat steps 2–6 above.
  3. Also verify at a narrow viewport (resize the Chrome window to
     phone-portrait width) that the label column still wraps correctly to the
     right of the switch without overflowing.

### Tier 2 — post-deploy
`not applicable`. No DB, RPC, edge function, or migration is being deployed. No
production data path is exercised by this change.

## QA Regression Areas
- **Add-event sheet, Rehearsal type:** header row (name, times), location
  autocomplete, potential toggle row (this feature), member availability grid
  (renders below the row when potential is ON), recurring toggle + section
  (hidden when potential is ON), footer save/cancel buttons. Confirm every
  section other than the potential toggle row is visually identical to `main`.
- **Add-event sheet, Gig type:** name autocomplete, potential gig container
  (this feature), member availability grid (`AnimatedSize`-wrapped below the
  header row), load-in time, gig pay, contacts, venue, setlist selector,
  footer. Confirm every section other than the potential toggle row is
  visually identical to `main`.
- **Edit-event sheet, both types:** same as above, plus the per-date
  availability sections (multi-date potential gigs / rehearsals) render
  correctly under the reordered header row. RSVP responses save unchanged.
- **Toggle-on / toggle-off animation:** the 200 ms `AnimatedContainer` border
  animation still runs when the toggle is flipped; the switch itself animates
  identically to `main` (still an `FSwitch` under the hood via `AppSwitch`,
  same style tokens).
- **Toggle disabled states:** on rehearsal, the toggle is disabled when
  `isSaving` is true (grey/dim). On gig, the toggle is disabled when
  `(isSaving || forcePotentialOnly)` is true — the RBAC "contributor with
  potential-only permission" case must still lock the toggle in the ON
  position.
- **Screen-reader / semantics:** the `AppSwitch` widget's semantics label is
  unchanged; screen readers announcing the toggle should read identically on
  main and on this branch.

## Rollout Strategy
Standard PR flow. No feature flag, no migration, no phased rollout — this is a
pure client-side widget-tree reorder that ships with the next app release for
all users at once. Rollback is a straightforward revert of the two widget-file
edits.

## Out of Scope
- Any changes to the member availability grid rendered under the header row.
- Any changes to the `AnimatedContainer` border, padding, or animation.
- Any restyling of `AppSwitch` itself, or introduction of a shared
  `PotentialToggleRow` widget.
- Adding a gig-side widget test (no existing gig-form widget test scaffold; the
  gig form's provider surface is much larger and would require substantial new
  test scaffolding disproportionate to a two-line reorder). Gig-side layout is
  verified visually via the Verification Plan.
- Changing the subtext gating on the gig side to mirror the rehearsal side
  (the prior feature `potential-rehearsal-subtext-when-enabled` deliberately
  left the gig side alone). Out of scope for this branch — Tony may open a
  separate follow-up feature if desired.
- Any Row `crossAxisAlignment` change (current default of `center` is
  preserved).
- Any localization / RTL work.
