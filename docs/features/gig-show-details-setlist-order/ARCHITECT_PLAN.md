# ARCHITECT_PLAN.md

## Feature Slug
`gig-show-details-setlist-order`

## Feature Title
Rename "Show Prep" to "Show Details" and move Setlists above Contact in the Add Event (Gig) drawer

## Problem Summary
In the Add Event drawer, when the event type is Gig, one of the section cards is titled "Show Prep" and contains a Contact field followed by a Setlists field. Two presentation changes are requested:

1. Rename the section title from "Show Prep" to "Show Details".
2. Reorder the two fields inside that section so **Setlists appears above Contact**.

No behavior, data, or platform-specific logic changes are involved — this is purely a title string swap and a two-child reordering inside a single `Column`.

## Root Cause (+confidence)
**Confidence: HIGH** — confirmed directly in code.

The Gig branch of `_buildEventBody` in [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) constructs a `_SectionCard` whose `title` is the literal string `'Show Prep'` and whose `child` is `_buildShowPrepSection(...)`. That helper builds a `Column` whose children are, in order, `gigFormFields.buildContactsSection(context)` and `eventFormFields.buildSetlistSelector(context, ref)` separated by a `SizedBox(height: Spacing.space16)`.

Concretely:

- [lib/features/events/widgets/event_editor_drawer.dart#L2916](lib/features/events/widgets/event_editor_drawer.dart#L2916) — `title: 'Show Prep'`
- [lib/features/events/widgets/event_editor_drawer.dart#L3089-L3102](lib/features/events/widgets/event_editor_drawer.dart#L3089) — `_buildShowPrepSection` returns a `Column` with `buildContactsSection` first, then `buildSetlistSelector`

Grep across `lib/` for `Show Prep|ShowPrep|show_prep` returns only the three matches in this one file (the title literal, the call site, and the method definition). Grep across `test/` for the same terms returns no matches. Grep for `buildContactsSection` and `buildSetlistSelector` confirms each helper has exactly one caller (this file) and one definition (`gig_form_fields.dart` and `event_form_fields.dart` respectively) — swapping their invocation order changes only visual placement, not internal wiring.

## Existing System Analysis
- `_SectionCard` is the standard section-card wrapper used for every group in the redesigned Add/Edit Event drawer (`The Gig`, `Schedule`, `Location`, `Show Prep`, `Money`, `Notes` for gigs). Its `title` parameter is a plain `String` rendered as the card header — no theming, i18n, or downstream consumer inspects the literal.
- `_buildShowPrepSection(...)` is a private helper called exactly once, from the Gig branch of `_buildEventBody`. It has no side effects and returns a plain `Column`.
- `GigFormFields.buildContactsSection(context)` and `EventFormFields.buildSetlistSelector(context, ref)` are self-contained widget builders — each owns its own state, controllers, and providers. Their relative order in the parent `Column` has no cross-dependency (no focus chain, no shared controller, no ordinal position stored anywhere).
- Rehearsal and Block-Out branches of `_buildEventBody` do **not** call `_buildShowPrepSection` and do not render a "Show Prep" card, so they are unaffected by either change.
- Historical docs under `docs/features/redesign-add-event-drawer/` and `docs/features/section-titles-title-case/` reference "Show Prep" as a description of the state at those PR moments. They are historical records and are explicitly off-limits.

## Proposed Solution
Two edits in one file, both mechanical:

1. Change the `_SectionCard`'s `title` argument from `'Show Prep'` to `'Show Details'`.
2. Inside `_buildShowPrepSection`, swap the two builder calls so `buildSetlistSelector` renders before `buildContactsSection`. The intervening `SizedBox(height: Spacing.space16)` stays exactly as it is.

The private helper method **retains the name `_buildShowPrepSection`**. Renaming it would be a cosmetic-only refactor with no user-visible effect, no callers outside this file, and no documentation reference. Per the "no opportunistic refactors" guardrail, we leave it alone.

## Database Impact
Not applicable. No schema, RLS policy, RPC, trigger, or migration changes.

## Flutter Architecture Changes
None. No new providers, controllers, repositories, models, or widgets. No changes to init order, routing, deep-link handling, auth flow, or platform-conditional code. Both native and web render this widget identically and will pick up both changes automatically.

## Files to Create
None.

## Files to Modify
- [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
  - Line 2916: change the string literal `'Show Prep'` to `'Show Details'`.
  - Inside `_buildShowPrepSection` (around lines 3096–3100): reorder the `Column` children so `eventFormFields.buildSetlistSelector(context, ref)` is the first child and `gigFormFields!.buildContactsSection(context)` is the third child (the `SizedBox` between them is unchanged).

## Files Off-Limits
- `lib/features/events/widgets/gig_form_fields.dart` — `buildContactsSection` is invoked as-is; its implementation is not part of this change.
- `lib/features/events/widgets/event_form_fields.dart` — `buildSetlistSelector` is invoked as-is; its implementation is not part of this change.
- Any file under `docs/features/redesign-add-event-drawer/` and `docs/features/section-titles-title-case/` — historical records of prior features.
- Any DB migration, RLS policy, or RPC function.
- Any auth, init, routing, deep-link, or platform config file.
- Any test file — no existing test references "Show Prep" and no new test is warranted (see Verification Plan).

## Change Budget
- Expected net line delta in `lib/features/events/widgets/event_editor_drawer.dart`: **0 lines** (one string literal renamed in place; two `Column` children swapped in place; the interstitial `SizedBox` stays).
- Expected new files: **0**.
- Expected new public classes/methods: **0**.
- Expected new dependencies: **0**.

## System Impact Map
- **Gigs** — affected (Add Event drawer Gig path, Edit Event drawer for a gig — same widget serves both).
- **Rehearsals** — unaffected (Rehearsal branch of `_buildEventBody` does not render this section).
- **Setlists** — unaffected internally (`buildSetlistSelector` is invoked with identical arguments; only its visual position moves).
- **Members** — unaffected.
- **Auth** — unaffected.
- **Routing** — unaffected.
- **Notifications** — unaffected.
- **Platforms** — iOS, Android, macOS, Web all affected identically (shared Flutter widget, no platform-conditional code touched).

## Regression Risk
**LOW.** The change is a string rename and a sibling swap inside a `Column`, both in a single widget's build method. No state, no controllers, no data flow, no init order, no auth, no DB, no routing are touched. Both moved widgets are self-contained and have no ordering dependency between them. The Rehearsal and Block-Out paths of the same drawer do not use this section at all.

## Engineer Task Breakdown
1. In [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart), on the line currently reading `title: 'Show Prep',` (approximately line 2916, inside the `_SectionCard` for the Show Prep group in the Gig branch of `_buildEventBody`), change the literal to `title: 'Show Details',`. Do not modify any surrounding lines.
2. In the same file, inside `_buildShowPrepSection(...)` (starting approximately line 3089), swap the first and third children of the returned `Column` so the resulting order is:
   ```dart
   children: [
     eventFormFields.buildSetlistSelector(context, ref),
     const SizedBox(height: Spacing.space16),
     gigFormFields!.buildContactsSection(context),
   ],
   ```
   Keep the `SizedBox` line identical. Do not rename the method, do not change its signature, and do not change any other line in the file.

## Verification Plan
### Tier 1 — Static (pre-deploy)
Run from the repo root; each must produce the stated result:

- `grep -RIn "'Show Prep'" lib/` → **no matches**.
- `grep -RIn "'Show Details'" lib/features/events/widgets/event_editor_drawer.dart` → exactly **one match**, on the `_SectionCard` `title:` line inside the Gig branch of `_buildEventBody`.
- `grep -n "buildSetlistSelector\|buildContactsSection" lib/features/events/widgets/event_editor_drawer.dart` → **two matches**, both inside `_buildShowPrepSection`, with `buildSetlistSelector` appearing on a **lower line number** than `buildContactsSection`.
- `flutter analyze` → no new warnings or errors introduced by the diff.

### Tier 2 — Runtime (post-merge, manual smoke)
Perform on at least macOS and Web (iOS and Android inherit the same widget tree; no platform-conditional code is affected):

1. Launch the app, tap "Add Event", select **Gig** as the event type.
2. Scroll to the section previously labeled "Show Prep". Confirm:
   - The section header reads exactly **"Show Details"**.
   - The **Setlists** field appears **above** the **Contact** field within that card.
3. Add a setlist selection and a contact selection; save. Reopen the same gig via Edit. Confirm the same header text and same field ordering, and confirm the previously-selected setlist and contact are still populated.
4. Open Add Event again and select **Rehearsal**. Confirm no "Show Details" or "Show Prep" card is rendered (this branch never had it and must not now).
5. Open Add Event again and select **Block Out**. Confirm unchanged.

No new automated test is warranted: no existing test covers this section's title or child ordering, and adding one for a two-line presentation swap would be disproportionate. If QA disagrees, they can add a single widget-test case to an existing group in `test/features/events/`.

## QA Regression Areas
- Add Event drawer, Gig path — header text and Setlist/Contact ordering (primary target of this change).
- Edit Event drawer for an existing gig — same widget serves both flows; must show the same header text and ordering.
- Add Event drawer, Rehearsal path — must be visually unchanged (no Show Details / Show Prep card).
- Add Event drawer, Block Out path — must be visually unchanged.
- Contact add/remove still works from its new position.
- Setlist selection still works from its new position, including opening the setlist picker and clearing a selection.
- No layout overflow at narrow widths (iPhone SE, small Android) — the two swapped widgets already coexisted in the same `Column`; swapping does not introduce new sizing constraints.

## Rollout Strategy
Standard PR → review → merge → auto-deploy. No feature flag required. No database migration to sequence. No cache to invalidate. No client-server contract change. If a regression is detected post-merge, revert the PR; the change is fully self-contained in one file.

## Out of Scope
- Renaming the private helper method `_buildShowPrepSection` to `_buildShowDetailsSection` — cosmetic refactor, deliberately deferred.
- Updating historical docs under `docs/features/redesign-add-event-drawer/` and `docs/features/section-titles-title-case/` that reference "Show Prep" — those are records of past state.
- Any reordering or renaming of other section cards (`The Gig`, `Schedule`, `Location`, `Money`, `Notes`).
- Any change to `buildContactsSection` or `buildSetlistSelector` internals.
- Any test infrastructure additions.
