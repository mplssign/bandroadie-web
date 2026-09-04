# ARCHITECT_PLAN.md

## Feature Slug
`potential-gig-toggle-match-rehearsal`

## Feature Title
Make the "Potential gig" toggle match the "Potential rehearsal" toggle (position + subtext behavior)

## Problem Summary
Tony wants the "Potential Gig" toggle (gig/event sheet) in visual + behavioral
parity with the "Potential Rehearsal" toggle, per two prior merged features:
1. `potential-toggle-left-of-label` — switch moved to LEFT of its label.
2. `potential-rehearsal-subtext-when-enabled` — descriptive subtext hidden
   until the toggle is switched ON.

**Discrepancy with the Feature Input, resolved by trusting the code:** the
Feature Input says the gig toggle "still uses the old layout: toggle on the
right and/or subtext always visible." Reading
[lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart)
`_buildPotentialGigContainer` (lines 1087–1163) shows the toggle-position half
is **already fixed** — `AppSwitch` is the first child of the header `Row`, then
a `SizedBox(width: Spacing.space12)`, then the `Expanded` label column
(shipped in `potential-toggle-left-of-label`; QA_REPORT.md for that feature
confirms both files were reordered).

The remaining, actual, outstanding delta is the subtext gating: on the gig
side, `SizedBox(height: 2)` + `Text('Toggle off once confirmed to make it
official.', …)` render unconditionally inside the label column (lines 1132–1139),
whereas on the rehearsal side the same two widgets are already wrapped in
`if (isPotential) …[ … ]` (see
[rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart)
lines 252–260).

This plan closes that one remaining gap. The
`potential-rehearsal-subtext-when-enabled` plan explicitly listed the gig side
as out of scope with the note *"Tony may choose to open a follow-up feature for
gig parity"* — this is that follow-up.

Applies to all platforms (iOS, Android, macOS, Web) — pure widget-tree change,
no platform-conditional code.

## Root Cause
**Confidence: HIGH** (confirmed in code).

In [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart)
inside `_buildPotentialGigContainer`, the header row's label `Column` emits the
title `Text('Potential Gig', …)`, an unconditional `SizedBox(height: 2)`, and
the unconditional subtext `Text('Toggle off once confirmed to make it official.',
…)`. There is no `if (isPotentialGig)` guard around the spacer + subtext, so
they render for every state of the toggle.

The immediately-following `AnimatedSize`-wrapped member-availability grid in the
same method is already correctly gated behind
`isPotentialGig ? … : const SizedBox.shrink()`, so the subtext is the only
piece of the toggle block that ignores `isPotentialGig`. The rehearsal-side
equivalent (`_buildPotentialToggle`) already has the correct `if (isPotential)`
gate around its `SizedBox` + subtext pair.

## Existing System Analysis
- `GigFormFields` is used from
  [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
  in a single unified drawer handling both add and edit modes. The drawer
  instantiates `GigFormFields` at line 2479 with `isPotentialGig: _isPotentialGig`
  and `forcePotentialOnly: _forcePotentialOnly`. Fixing
  `_buildPotentialGigContainer` fixes both add and edit flows in one change.
- Toggle state is owned by the drawer as `_isPotentialGig`, mirroring how
  rehearsal state (`isPotential`) is threaded. `GigFormFields` is a
  `ConsumerWidget`, not stateful — no local state to touch.
- `_forcePotentialOnly` (drawer field, set alongside `_isPotentialGig = true` at
  event_editor_drawer.dart lines 383 and 2392) only disables user interaction
  (`onChanged: (isSaving || forcePotentialOnly) ? null : onPotentialGigToggled`).
  It never coexists with `isPotentialGig = false`, so `if (isPotentialGig)` is
  the correct gate in every case, including the RBAC-forced potential-only
  case: the subtext will render, which is the desired behavior (gig is
  effectively potential).
- The surrounding `AnimatedContainer` (200 ms / `Curves.easeOut`) already
  animates the rose primary border on `isPotentialGig` transitions, so the
  subtext appearing/disappearing on the same toggle transition feels visually
  consistent without adding an animation wrapper.
- The `AnimatedSize` around the member grid (`_buildPotentialGigContainer`
  lines 1143–1161) animates the grid's height when the toggle flips; it does
  not animate the header row's own height change from the label column
  growing/shrinking as the subtext appears/disappears — this exactly mirrors
  the rehearsal side's un-animated subtext gating (parity preserved).
- Default `Row.crossAxisAlignment` is `center`. The `AppSwitch` remains
  vertically centered against a one-line label (subtext hidden) or a two-line
  label (subtext visible). Same behavior as the rehearsal side today. No
  crossAxisAlignment change needed.
- The Feature Input specifies "hidden (not rendered)" behavior identical to
  the rehearsal side — the correct primitive is a collection-if, not
  `Visibility` / `Opacity` / `AnimatedSize`. This mirrors the already-shipped
  rehearsal implementation exactly.

## Proposed Solution
In [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart)
inside `_buildPotentialGigContainer`, wrap the existing `SizedBox(height: 2)`
and its following subtext `Text('Toggle off once confirmed to make it
official.', …)` (currently at lines 1132–1139) in an `if (isPotentialGig) …[ … ]`
collection-if so they are only added to the label `Column`'s children when the
toggle is ON. Preserve every existing style, spacing, and design token verbatim
— no refactor, no new animation wrapper, no shared-widget extraction.

The transform (before → after) inside the header `Row`'s `Expanded` `Column`:

```dart
// Before (current):
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('Potential Gig', style: …),
    const SizedBox(height: 2),
    Text('Toggle off once confirmed to make it official.', style: …),
  ],
),

// After:
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('Potential Gig', style: …),
    if (isPotentialGig) ...[
      const SizedBox(height: 2),
      Text('Toggle off once confirmed to make it official.', style: …),
    ],
  ],
),
```

The title `Text('Potential Gig', …)` is untouched. The `SizedBox(height: 2)` and
its subtext `Text` are moved verbatim inside the collection-if. Style, string,
and design-token usage are preserved exactly. This is a byte-for-byte mirror of
the already-shipped rehearsal-side pattern.

**Rejected alternatives:**
- **`Visibility(visible: isPotentialGig, child: …)`** — still occupies layout
  space by default (or requires extra config to not); "not rendered" is clearer
  and lighter with a collection-if. The rehearsal side uses collection-if;
  parity dictates the same primitive here. Rejected.
- **`AnimatedSize` / `AnimatedCrossFade` around the subtext** — adds motion the
  Feature Input does not request and the rehearsal side does not have.
  Rejected on parity + minimalism grounds.
- **Extract a shared `PotentialToggleRow` widget** — proposed and rejected in
  the prior `potential-toggle-left-of-label` plan on the same grounds: only two
  callers, and the two callers differ (rehearsal has no
  `forcePotentialOnly`; gig has an `AnimatedSize`-wrapped member grid below the
  row that rehearsal handles via a different `if (isPotential)` `Builder`
  block). Would be scope creep and would erase the deliberate divergence.
  Rejected.
- **Extract a `_buildPotentialSubtext(bool)` helper** — unnecessary abstraction
  for a two-widget conditional inside a single method. Not proportional to the
  change. Rejected.

## Database Impact
`n/a`.

## Flutter Architecture Changes
None. No new controllers, providers, repositories, models, routes, services, or
state. No changes to init order, config, `--dart-define`, or platform-conditional
code. No new dependencies. Widget-tree layout only.

## Files to Create
None.

**Rationale for skipping a new widget test file:** Adding a `gig_form_fields_test.dart`
scaffold parallel to the existing `rehearsal_form_fields_test.dart` would require
constructing a full `GigFormFields` with ~50 required constructor parameters
(gig contacts controllers, gig-name autocomplete, city autocomplete, address
controllers, load-in time state, soundcheck time state, gig pay, expenses,
per-date availability, etc.) plus stubbing at least two providers
(`membersProvider`, `contactsProvider`). That is ~150+ lines of test scaffolding
for a two-line conditional wrap — disproportionate to the change and exactly
the "AI-shaped bloat" pattern QA already flags. The rehearsal-side widget test
already exists and, unchanged, will verify that the shared pattern (collection-if
around `SizedBox` + subtext) still works after this change. Manual verification
on macOS + web is sufficient for a UI-only, structural change of this size.
This tradeoff follows the mode guidance: *"Verification tests are proportional
to risk — never a new test file where an existing group can take one more
case."* No existing group can take this case (there is no gig-side widget
test), and creating one just for this two-line change is disproportionate.

## Files to Modify
- [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart)
  — inside `_buildPotentialGigContainer` (starts line 1087), in the label
  `Column` inside the header `Row`'s `Expanded` (currently lines 1120–1141):
  wrap the existing `SizedBox(height: 2)` (line 1132) and its immediately
  following subtext `Text('Toggle off once confirmed to make it official.', …)`
  (lines 1133–1139) in an `if (isPotentialGig) ...[ ... ]` collection-if.
  Preserve the title `Text('Potential Gig', …)` above them verbatim. Preserve
  the `AppSwitch`, the `SizedBox(width: Spacing.space12)` spacer, the outer
  `Row`, the surrounding `AnimatedContainer`, and the `AnimatedSize`-wrapped
  member grid below verbatim. No other edits to this file.

## Files Off-Limits
- [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart)
  — already correct (subtext gating and switch-left-of-label both shipped).
  Do not touch. Confirming the source-of-truth pattern is the whole point of
  this feature; changing the reference implementation would defeat parity.
- [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
  — parent drawer owns `_isPotentialGig` and `_forcePotentialOnly` state and
  wires them into `GigFormFields`. No prop shape or callback signature changes
  are needed. Do not add a new "show subtext" prop — the visibility rule is
  intrinsic to the widget (subtext visible iff `isPotentialGig == true`).
- [lib/components/ui/app_switch.dart](lib/components/ui/app_switch.dart)
  — shared cross-feature component. Do not modify.
- [test/features/events/widgets/rehearsal_form_fields_test.dart](test/features/events/widgets/rehearsal_form_fields_test.dart)
  — its existing three cases (subtext absent / subtext present / switch-left)
  must continue to pass unchanged. Do not modify.
- [lib/features/events/widgets/event_form_fields.dart](lib/features/events/widgets/event_form_fields.dart)
  — outer dispatch layer. Unaffected.
- Any other `lib/features/events/widgets/*.dart` file — no other file renders
  the "Potential Gig" label + switch pair (verified via workspace grep for the
  exact label string).
- `lib/features/events/models/**`, `lib/features/events/*_repository.dart`,
  `lib/features/events/*_controller.dart`, `lib/features/rehearsals/**`,
  `lib/features/gigs/**` — no data-shape, controller, or repository changes.
- Any DB migration under `supabase/migrations/`, any RPC or RLS policy, any
  edge function under `supabase/functions/` — not applicable.
- `pubspec.yaml`, `analysis_options.yaml`, `--dart-define` config files,
  native entitlement / manifest files — not touched.

## Change Budget
- Net line delta per file:
  - `lib/features/events/widgets/gig_form_fields.dart`: **+2 / −0**
    (one `if (isPotentialGig) ...[` opening line and one `],` closing line
    wrapping the existing `SizedBox` and `Text`; existing lines unchanged).
- Expected new files: **0**.
- Expected new public classes / methods: **0**.
- Expected new dependencies: **0**.

QA measures the actual diff against these numbers. A diff that adds a new
widget file, extracts a shared row helper, adds a new state field or prop, or
edits any file listed under Files Off-Limits is over-budget and must be
flagged.

## System Impact Map
- Rehearsals — unaffected (reference implementation is untouched).
- Gigs — **affected** (add/edit sheet potential-gig toggle row visual behavior
  only; no data shape, no state logic, no persistence changes, no callback
  signature changes).
- Setlists — unaffected.
- Members — unaffected. Member availability grid renders below the toggle row
  (inside its own `AnimatedSize`) and is untouched.
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

- Scope is a two-widget conditional inside one `Column` in one method of one
  widget file.
- No state, controller, provider, repository, model, callback signature, or
  persistence code changes.
- Auth, session, routing, init order, DB, RLS, RPC — none touched.
- The gated widgets are pure `Text` and `SizedBox` with no side effects; the
  only observable behavior change is the subtext being hidden when the toggle
  is off.
- The `forcePotentialOnly` (RBAC potential-only-contributor) case: setState
  always sets `_isPotentialGig = true` alongside `_forcePotentialOnly = true`
  (event_editor_drawer.dart lines 383, 2392), so `if (isPotentialGig)` renders
  the subtext correctly in that case — the disabled toggle still shows the
  descriptive text, which is the desired behavior (the gig is effectively
  potential).
- The `AnimatedContainer` border animation on `isPotentialGig` transitions is
  untouched.
- The `AnimatedSize` around the member-availability grid is untouched.
- The rehearsal side (which shares this pattern and already has it correct) is
  explicitly not touched; its existing widget tests continue to protect it.
- No new dependencies, no new imports required (`isPotentialGig` is already in
  scope as an instance field on `GigFormFields`).

## Engineer Task Breakdown
1. In [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart),
   inside `_buildPotentialGigContainer`, in the label `Column` inside the
   header `Row`'s `Expanded`: wrap the existing `SizedBox(height: 2)` and the
   immediately-following subtext `Text('Toggle off once confirmed to make it
   official.', style: AppTextStyles.footnote.copyWith(color:
   context.colors.textSecondary))` in an `if (isPotentialGig) ...[ ... ]`
   collection-if so both widgets are only added to the `Column`'s children
   when the toggle is ON. Preserve the existing `SizedBox` height (`2`),
   preserve the existing `Text` string, style, and design-token usage
   verbatim. Do not modify the title `Text('Potential Gig', …)` above them.
   Do not modify the surrounding `AnimatedContainer`, its padding, its border
   logic, the `AppSwitch`, the `SizedBox(width: Spacing.space12)` spacer,
   the outer `Row`, or the `AnimatedSize`-wrapped member grid below.
2. Run `flutter analyze` locally and confirm zero new warnings, errors, or
   infos introduced by the change.
3. Run `flutter test test/features/events/widgets/rehearsal_form_fields_test.dart`
   and confirm all three existing cases still pass (this test file is the
   canonical widget-level protection for the collection-if pattern; the gig
   side mirrors it structurally). This step protects against an inadvertent
   regression to the reference implementation.

## Verification Plan

### Tier 1 — pre-deploy (must pass before merge)

- **Static analysis:** `flutter analyze` — zero new warnings, errors, or infos
  introduced by the modified widget file.

- **Widget test (existing, unchanged):**
  `flutter test test/features/events/widgets/rehearsal_form_fields_test.dart`
  — all three existing cases must continue to pass. This confirms the
  reference implementation (rehearsal side) is untouched and the shared
  collection-if pattern still behaves as expected.
  - `subtext is absent when isPotential is false` — must pass unchanged.
  - `subtext is present when isPotential is true` — must pass unchanged.
  - `AppSwitch renders to the left of the Potential Rehearsal label` — must
    pass unchanged.

- **Visual verification — macOS:**
  1. `flutter run -d macos` (or `./run.sh macos`).
  2. Sign in and select an active band.
  3. Open the "Add Event" sheet from the events tab or home screen.
  4. Switch the event type to **Gig**. Scroll to the "Potential Gig" row.
     Confirm the switch is on the LEFT of the "Potential Gig" text (unchanged
     from `main` — protects against regression to the prior feature). Confirm
     the descriptive subtext *"Toggle off once confirmed to make it official."*
     is NOT visible while the toggle is OFF. Toggle it ON — confirm the rose
     primary border appears on the container, the subtext appears immediately
     beneath the title, and the member-availability grid animates in below.
     Toggle it OFF — confirm the subtext disappears and the member grid
     animates out.
  5. Switch the event type to **Rehearsal** and confirm the "Potential
     Rehearsal" row behaves identically (this is the reference; both should
     now look and behave the same).
  6. Open an existing gig for edit (one saved with `is_potential = false`) —
     confirm the subtext is hidden. Toggle ON, confirm it appears. Toggle
     OFF, confirm it disappears.
  7. Repeat step 6 with an existing gig that was saved with
     `is_potential = true` — confirm the subtext is visible when the drawer
     opens.

- **Visual verification — web:**
  1. `flutter run -d chrome` (or `./run.sh chrome`).
  2. Repeat steps 3–7 above.
  3. Also verify at a narrow viewport (resize the Chrome window to
     phone-portrait width) that the label column still wraps correctly to
     the right of the switch without overflowing, both with the subtext
     hidden (one-line label) and visible (two-line label).

- **RBAC edge case (macOS or web):** if a contributor account with
  `canCreatePotentialGigsOnly` permission is available, sign in as that
  account and open Add Event → Gig. Confirm `_isPotentialGig` is auto-set
  to true (existing behavior, event_editor_drawer.dart lines 383 / 2392),
  the toggle is disabled, AND the subtext IS visible (since the gig is
  effectively potential). If no such account is available, this is covered
  by code inspection: `_forcePotentialOnly = true` is only ever set in
  branches that also set `_isPotentialGig = true`, so
  `if (isPotentialGig)` renders the subtext in that case.

### Tier 2 — post-deploy
`n/a` — no DB, RPC, edge function, or migration is being deployed. No
production data path is exercised by this change.

## QA Regression Areas
- **Add-event sheet, Gig type — potential toggle row:** confirm subtext is
  hidden when toggle is OFF and visible when toggle is ON, in both add and
  edit modes. Confirm title `Potential Gig` is always visible regardless of
  toggle state. Confirm the container border animates on toggle transition
  (existing `AnimatedContainer` behavior). Confirm the member-availability
  grid still animates in/out via the existing `AnimatedSize` (untouched).
- **Add-event sheet, Rehearsal type — potential toggle row:** confirm no
  visual or behavioral change (the reference implementation is not touched;
  it should look and behave identically to `main`). This is the parity
  reference — the two toggles should now look and behave the same.
- **Gig `forcePotentialOnly` RBAC case:** confirm the potential-only forced
  case still shows the subtext (since `_isPotentialGig = true` is set
  alongside `_forcePotentialOnly = true`). Toggle is disabled but subtext is
  visible.
- **Multi-date potential gig:** confirm per-date availability sections still
  appear when the toggle is ON in edit mode; not touched by this change but
  sits inside the same container's `AnimatedSize`.
- **Gig editor layout at narrow widths (web only):** confirm label column
  still lays out correctly beside the switch when the subtext appears
  (row-height increases as the label column becomes two lines).
- **Rehearsal editor:** confirm zero visual change on `main` vs. this branch.
  This file is not touched.

## Rollout Strategy
Standard PR flow. No feature flag, no phased rollout, no data migration, no
cache invalidation. Ship in a single commit on
`feature/potential-gig-toggle-match-rehearsal`, open a PR against `main`, merge
when Tier 1 verification passes.

No app version bump required for the code change itself, but if the standard
project convention is to bump on any user-facing UI change, follow the
existing convention — Architect does not prescribe a version-bump policy.

## Out of Scope
- **Any change to the toggle-position / switch-left-of-label layout.** That
  half of the Feature Input's ask is already shipped for both rehearsal and
  gig sides via `potential-toggle-left-of-label`. Re-doing it would be
  redundant.
- **Any restyling, spacing, typography, or animation changes to the toggle
  row** (label, subtext, switch, or the surrounding container).
- **Any change to the member-availability grid, `AnimatedSize` wrapper,
  proposed-dates section, or per-date availability section.**
- **Any refactor of `GigFormFields` construction, prop threading, or the
  parent drawer's state ownership** of `_isPotentialGig` / `_forcePotentialOnly`.
- **Any extraction of a shared `PotentialToggleRow` widget** across
  `gig_form_fields.dart` and `rehearsal_form_fields.dart`. The two call sites
  differ in disabled-state expression (`forcePotentialOnly` on gig only), in
  the below-row layout (`AnimatedSize` on gig, `if (isPotential) …[ Builder
  … ]` on rehearsal), and in per-date availability handling. Extraction
  would be opportunistic refactor and would erase the deliberate divergence
  — explicitly rejected in the prior `potential-toggle-left-of-label` plan
  on the same grounds.
- **Any DB, RPC, RLS, edge function, or model change.**
- **Any test infrastructure changes** (new mock factories, shared test
  helpers) or new widget test file. See Files to Create for rationale.
