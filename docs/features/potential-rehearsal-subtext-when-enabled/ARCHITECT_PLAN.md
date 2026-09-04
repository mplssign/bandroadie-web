# ARCHITECT_PLAN.md

## Feature Slug
`potential-rehearsal-subtext-when-enabled`

## Feature Title
Show "Potential Rehearsal" subtext only after the switch is turned on

## Problem Summary
On the rehearsal add/edit form, the "Potential Rehearsal" toggle row shows a
descriptive subtext (`Toggle off once confirmed to make it official.`) directly
beneath the label. That subtext currently renders unconditionally — visible even
when the toggle is OFF. It should only appear once the toggle is turned ON, and
disappear (not render) when the toggle is OFF.

Applies to all platforms (iOS, Android, macOS, Web) — this is a pure widget-tree
change with no platform-conditional code involved.

## Root Cause
**Confidence: HIGH** (confirmed in code).

In [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart)
inside `_buildPotentialToggle`, the row's left `Column` unconditionally emits
the title `Text('Potential Rehearsal', …)`, a 2px `SizedBox`, and then the
subtext `Text('Toggle off once confirmed to make it official.', …)`. There is
no `if (isPotential)` guard around the spacer + subtext, so they render for
every state of the toggle.

The immediately-following member-availability grid (in the same method) is
already correctly gated behind `if (isPotential) …[ … ]`, so the subtext is
the only piece of the toggle block that ignores `isPotential`.

## Existing System Analysis
- `RehearsalFormFields` is used from
  [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
  in a single unified drawer that handles both add and edit modes (`_isEditMode`
  getter at line 1496). The parent drawer calls
  `_createRehearsalFormFields().buildPotentialSection(context, ref)` at
  line 3029, which delegates directly to `_buildPotentialToggle`. Fixing the
  method fixes both add and edit flows in one change.
- Toggle state is owned by the drawer as `_isPotentialGig` and pushed down into
  `RehearsalFormFields` via the `isPotential` parameter (`RehearsalFormFields`
  is a `ConsumerWidget`, not a stateful holder — no local state to touch).
- The surrounding `AnimatedContainer` (200 ms / `Curves.easeOut`) already
  animates the primary border on `isPotential` transitions, so the subtext
  appearing/disappearing on the same toggle will feel visually consistent
  without any explicit animation wrapper.
- The Feature Input specifies the subtext should be "hidden (not rendered)" and
  "keep the change minimal … no refactors" — the correct primitive is a
  conditional widget list, not `Visibility`, `Opacity`, or `AnimatedSize`.

## Proposed Solution
Wrap the 2px `SizedBox` and the subtext `Text` (the two pieces immediately
following the `'Potential Rehearsal'` title `Text`) in an
`if (isPotential) …[ … ]` collection-if so that they are only added to the
`Column`'s children when the toggle is ON. Preserve all existing styles,
spacing, and design tokens verbatim — no refactor of surrounding structure,
no new animation wrapper, no style changes.

Rejected alternatives:
- Wrapping the subtext in `AnimatedSize` / `AnimatedCrossFade`: contradicts the
  Feature Input's "hidden (not rendered)" wording and "keep the change minimal
  — no refactors" instruction. Adds motion that wasn't requested.
- `Visibility(visible: isPotential)`: still occupies layout space (or requires
  extra config to not); "not rendered" is clearer with a collection-if.
- Extracting a `_buildPotentialSubtext()` helper: unnecessary abstraction for a
  two-widget conditional inside a single method.

## Database Impact
`not applicable` — no schema, RLS, RPC, trigger, migration, edge function, or
data-access change.

## Flutter Architecture Changes
None. No new controllers, providers, repositories, models, routes, services,
or state. No changes to init order, config, or platform-conditional code.
Widget behavior only.

## Files to Create
- `test/features/events/widgets/rehearsal_form_fields_test.dart` — new widget
  test file scoped to this behavior. There is no existing test group for
  `RehearsalFormFields` — the only file under
  `test/features/events/widgets/` is `event_dropdown_test.dart`, which is
  unrelated — so this is the smallest defensible location for the verification
  cases. Two `testWidgets` cases only (see Verification Plan).

## Files to Modify
- [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart)
  — inside `_buildPotentialToggle`, wrap the `SizedBox(height: 2)` and its
  following subtext `Text('Toggle off once confirmed to make it official.', …)`
  in an `if (isPotential) …[ … ]` collection-if so both render only when the
  toggle is ON. No other edits to this file; no reordering, no restyling, no
  refactor.

## Files Off-Limits
- [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart)
  — contains an identical unconditional subtext for the `Potential Gig`
  toggle (line ~1120). The Feature Input is explicitly scoped to rehearsals;
  touching the gig form would be opportunistic scope creep. Flagged here for
  transparency — Tony may choose to open a follow-up feature for gig parity,
  but it is out of scope for this branch.
- [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
  — parent drawer that hosts the toggle. State ownership and prop wiring
  (`_isPotentialGig` → `isPotential:` on `RehearsalFormFields`) are already
  correct; no caller changes needed.
- Any `lib/features/events/models/**`, `lib/features/events/events_repository.dart`,
  `lib/features/rehearsals/**` — no data-shape, controller, or repository
  changes; behavior is entirely local to one widget.
- Any DB migration, RPC, edge function, RLS policy — not applicable.
- `pubspec.yaml`, `analysis_options.yaml`, `--dart-define` config, native
  entitlement/manifest files — not touched.

## Change Budget
- Net line delta per file:
  - `lib/features/events/widgets/rehearsal_form_fields.dart`: **+2 / −0**
    (one `if (isPotential) ...[` opening line and one `],` closing line
    wrapping the existing `SizedBox` and `Text`; existing lines unchanged).
  - `test/features/events/widgets/rehearsal_form_fields_test.dart`: **+~90 / −0**
    (new file: imports + `main()` + `group()` + two `testWidgets` cases +
    a small helper to pump the widget with the minimum required parameters).
- Expected new files: **1** (the widget test file).
- Expected new public classes / methods: **0**.
- Expected new dependencies: **0**.

## System Impact Map
- Rehearsals — **affected** (add/edit form UI only; no data shape, no state
  logic, no persistence changes).
- Gigs — **unaffected** (out of scope; identical pattern deliberately left
  alone).
- Setlists — unaffected.
- Members — unaffected.
- Auth / session / PKCE — unaffected.
- Routing / deep links — unaffected.
- Notifications / edge functions — unaffected.
- Init order (`WidgetsFlutterBinding` → URL strategy → orientation lock →
  `AppVersionService.init` → `validateSupabaseConfig` → `Supabase.initialize`
  → `Firebase.initializeApp` [native only] → `DeepLinkService` → `runApp`) —
  unaffected.
- Platforms (iOS / Android / macOS / Web) — **all** affected identically; no
  platform-conditional code involved, no native, no `kIsWeb` branch.

## Regression Risk
**LOW.**

- Scope is a two-widget conditional inside one `Column` in one method of one
  widget file.
- No state, controller, provider, repository, model, or persistence code
  changes.
- Auth, session, routing, init order, DB, RLS, RPC — none touched.
- The gated widgets are pure `Text` and `SizedBox` with no side effects; the
  only observable behavior is visual layout of the toggle row.
- The already-gated member-availability grid below the subtext continues to
  work exactly as before; the fix mirrors its existing pattern one row above.

## Engineer Task Breakdown
1. In [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart),
   inside `_buildPotentialToggle`, wrap the existing `SizedBox(height: 2)` and
   the immediately-following subtext `Text('Toggle off once confirmed to make
   it official.', style: AppTextStyles.footnote.copyWith(color:
   context.colors.textSecondary))` in an `if (isPotential) ...[ ... ]`
   collection-if so both widgets are only added to the `Column`'s children
   list when the toggle is ON. Preserve the existing `SizedBox` height (2),
   preserve the existing `Text` string, style, and design-token usage verbatim.
   Do not modify the surrounding `AnimatedContainer`, the title `Text`, the
   `AppSwitch`, or the member-availability block.
2. Create a new widget test file at
   `test/features/events/widgets/rehearsal_form_fields_test.dart` with two
   `testWidgets` cases as described in the Verification Plan below. Use
   `ProviderScope` to satisfy Riverpod dependencies and pass a minimal
   `RehearsalFormFields` instance with the required constructor arguments;
   toggle-off case pumps with `isPotential: false`, toggle-on case pumps
   with `isPotential: true`. Both cases assert on the presence/absence of
   the exact string `'Toggle off once confirmed to make it official.'`.
3. Run `flutter analyze` and confirm zero new warnings, errors, or infos
   introduced by the changes.

## Verification Plan

### Tier 1 — pre-deploy (must pass before merge)
- `flutter analyze` — zero new warnings/errors introduced.
- New widget test file
  `test/features/events/widgets/rehearsal_form_fields_test.dart`:
  - **Case A — toggle OFF:** pump `RehearsalFormFields` inside a
    `ProviderScope` + `MaterialApp` + `Scaffold`, call
    `.buildPotentialSection(context, ref)` (or render via `build`), pass
    `isPotential: false` and stub out the other required parameters with
    inert values (empty maps/lists, no-op callbacks, a minimal
    `FAutocompleteController` / `FieldHintController`, dummy `Animation`s).
    Assert
    `expect(find.text('Toggle off once confirmed to make it official.'), findsNothing);`
    and `expect(find.text('Potential Rehearsal'), findsOneWidget);` (title
    still present).
  - **Case B — toggle ON:** same setup, but `isPotential: true`.
    Assert
    `expect(find.text('Toggle off once confirmed to make it official.'), findsOneWidget);`
    and `expect(find.text('Potential Rehearsal'), findsOneWidget);`.
  - If a stable pump of the full widget proves impractical due to member/
    availability provider dependencies, Engineer may exercise the toggle
    section by pumping the standalone `buildPotentialSection` return value
    or by mocking `membersProvider` via `overrides:` on `ProviderScope`.
    Test the observable rule (subtext visible iff `isPotential == true`) —
    do not test animation timing, styling, or unrelated widgets.

### Tier 2 — post-deploy
`n/a` — no DB, RPC, edge function, or server-side surface is being replaced;
there is nothing to validate post-deploy that Tier 1 does not already cover.

### Manual UI Verification (QA smoke)
- On macOS (fastest to iterate): open the app, navigate to add a rehearsal,
  and confirm the subtext `'Toggle off once confirmed to make it official.'`
  is NOT visible while the "Potential Rehearsal" toggle is OFF. Toggle it
  ON — confirm the subtext appears immediately beneath the label. Toggle it
  OFF again — confirm the subtext disappears.
- Repeat once in edit mode: open an existing rehearsal that has
  `is_potential = false`, open the editor, verify the subtext is hidden;
  toggle ON, verify subtext appears; toggle OFF, verify it disappears.
- Sanity check on one mobile platform (iOS simulator or Android emulator) to
  confirm identical behavior; no platform-conditional code is involved so a
  single mobile platform smoke is sufficient.

## QA Regression Areas
- Rehearsal add drawer — full open, all fields render correctly, no
  layout shift or overlap introduced by the conditional wrapper. The
  `AnimatedContainer` border transition on toggle continues to feel
  smooth (unchanged code path).
- Rehearsal edit drawer — same as above, in edit mode.
- Rehearsal recurring toggle & recurring section (also in this file) —
  confirm still hidden when `isPotential` is ON and visible/animated when
  `isPotential` is OFF; not touched by this change but sits in the same
  widget's `build` method.
- Multi-date potential rehearsal availability grid — confirm the
  per-member and per-date availability grids still appear when the toggle
  is ON in both add and edit modes; not touched by this change but sits
  immediately below the subtext.
- Gig editor (potential gig toggle) — confirm unchanged; the gig form
  file is deliberately not touched and its subtext should still render
  unconditionally as before. Any observed change there is a bug.

## Rollout Strategy
Standard PR flow. No feature flag, no phased rollout, no data migration, no
cache invalidation. Ship in a single commit on
`feature/potential-rehearsal-subtext-when-enabled`, open a PR against `main`,
merge when Tier 1 verification passes.

No app version bump required for the code change itself, but if the standard
project convention is to bump on any user-facing UI change, follow the
existing convention — Architect does not prescribe a version-bump policy.

## Out of Scope
- Applying the same visibility-gating to the "Potential Gig" subtext in
  [gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart).
  The same unconditional-subtext pattern exists there. Feature Input is
  explicitly scoped to rehearsals; a separate feature slug is the right
  vehicle if Tony wants gig parity.
- Any restyling, spacing, typography, or animation changes to the toggle row
  (label, subtext, switch, or the surrounding container).
- Any change to the member-availability grid, proposed-dates section,
  per-date availability section, or recurring section.
- Any refactor of `RehearsalFormFields` construction, prop threading, or the
  parent drawer's state ownership of `_isPotentialGig`.
- Any DB, RPC, RLS, edge function, or model change.
- Any test infrastructure changes (mock factories, shared test helpers)
  beyond the single new widget test file described above.
