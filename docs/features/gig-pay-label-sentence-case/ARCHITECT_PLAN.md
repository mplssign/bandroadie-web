# ARCHITECT_PLAN

## Feature Slug
`gig-pay-label-sentence-case`

## Feature Title
Make the "Set Gig Pay" button label match the sentence-case style of the sibling add-value labels

## Problem Summary
The Add Event sheet's four sibling "add value" `EventAddValueButton` labels
were standardized to sentence case: `Set load-in time`, `Set soundcheck
time`, `Add contact`, `Add expense`. The Gig Pay empty-state CTA was
intentionally left as `Set Gig Pay` (Title Case) and now needs to match its
siblings.

## Root Cause (+confidence)
**Confidence: HIGH — confirmed in code.**

The Gig Pay empty-state CTA is a hard-coded string literal `'Set Gig Pay'`
passed as the `label` argument to `EventAddValueButton` in
[lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart#L738),
inside `GigFormFields.buildGigPayButton()`'s `if (!hasDetails)` branch. It
was simply not included in the earlier sentence-case standardization pass.

## Existing System Analysis
The Gig Pay button has two mutually-exclusive rendered states, both inside
`buildGigPayButton()`:

- **Empty state** (`gigPayDetails == null || amountCents == 0`) — renders
  `EventAddValueButton(label: 'Set Gig Pay', ...)` at
  [gig_form_fields.dart#L738](lib/features/events/widgets/gig_form_fields.dart#L738).
  This is the only label being changed.
- **Value-set state** — renders `AppButton(variant: AppButtonVariant.outlined,
  ...)` around
  [gig_form_fields.dart#L758](lib/features/events/widgets/gig_form_fields.dart#L758)
  with a dynamically computed `label` string
  (`${formattedAmount}${payerName != null ? ' · $payerName' : ''}`). No
  static "Set Gig Pay" literal exists here; this branch is unaffected.

The four sibling `EventAddValueButton` labels were verified in code and are
all already sentence case:

| Label                 | File / Line                                                                                                    | Case                 |
| --------------------- | -------------------------------------------------------------------------------------------------------------- | -------------------- |
| `Set load-in time`    | [gig_form_fields.dart#L1439](lib/features/events/widgets/gig_form_fields.dart#L1439)                           | sentence case ✓      |
| `Set soundcheck time` | [event_editor_drawer.dart#L3050](lib/features/events/widgets/event_editor_drawer.dart#L3050)                   | sentence case ✓      |
| `Add contact`         | [gig_form_fields.dart#L1568](lib/features/events/widgets/gig_form_fields.dart#L1568)                           | sentence case ✓      |
| `Add expense`         | [gig_form_fields.dart#L801](lib/features/events/widgets/gig_form_fields.dart#L801)                             | sentence case ✓      |

**No contradiction** with the intent note: the siblings are sentence case,
so the target `'Set gig pay'` genuinely matches them.

Shared widget (unchanged): `EventAddValueButton` in
[event_editor_helpers.dart#L139](lib/features/events/widgets/event_editor_helpers.dart#L139)
already renders `label` at `AppFontSizes.subhead` (14px) with the rose
outline; no styling change is needed.

## Proposed Solution
Change exactly one string literal, in place, from `'Set Gig Pay'` to
`'Set gig pay'`. No other edits.

## Database Impact
n/a

## Flutter Architecture Changes
n/a

## Files to Create
n/a

## Files to Modify
- [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart)
  — line 738: replace `label: 'Set Gig Pay',` with `label: 'Set gig pay',`.
  Nothing else in this file changes.

## Files Off-Limits
- **Same file, value-set `AppButton.outlined` branch (~L758 of
  `gig_form_fields.dart`)** — its label is dynamic (formatted amount +
  optional payer name); not the CTA being restyled.
- **The four sibling `EventAddValueButton` labels** listed in the Existing
  System Analysis table — they are already correct sentence case.
- **`gig_form_fields.dart` line 625** (`'+ Set Soundcheck Time
  (Optional)'`, inside `buildSoundcheckRow`'s `GestureDetector` container) —
  different widget on a separate rendering path; out of scope.
- **`gig_form_fields.dart` line 791** (`AppButton` variant `text`, label
  `'Add Expense'`) — this is the small "add another" affordance in the
  Expenses section header when the list is non-empty; not an
  `EventAddValueButton` and out of scope.
- **`event_editor_drawer.dart` line 2778**
  (`'Add Expense'` / `'Edit Expense'`) — sticky sheet titles, not button
  labels; out of scope.
- **`event_editor_helpers.dart` (the shared `EventAddValueButton`
  widget)** — no styling, sizing, or rendering change.
- All other files in the repo.

## Change Budget
- Expected net line delta per file:
  `lib/features/events/widgets/gig_form_fields.dart` = **0** (one literal
  swapped in place, same line count).
- Expected new files: **0**.
- Expected new public classes/methods: **0**.
- Expected new dependencies: **0**.

## System Impact Map
- Gigs: affected (label text only in Add/Edit Event sheet, gig branch).
- Rehearsals: unaffected (Gig Pay UI is gig-only).
- Setlists: unaffected.
- Members: unaffected.
- Auth: unaffected.
- Routing: unaffected.
- Notifications: unaffected.
- Platforms: iOS / Android / macOS / Web — all affected identically
  (shared Flutter UI string, no platform-conditional code).

## Regression Risk
**LOW.** Pure UI label text change. No behavior, no callbacks, no state, no
styling, no layout, no persistence, no auth/session/routing/init-order/DB
touched. The literal is a `label:` argument to a `StatelessWidget` that
renders it as plain `Text`.

## Engineer Task Breakdown
1. In
   [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart),
   inside `GigFormFields.buildGigPayButton()`'s `if (!hasDetails)` branch,
   change the `EventAddValueButton` `label` argument from `'Set Gig Pay'`
   to `'Set gig pay'` (line 738). No other edits in this file or any other
   file.

## Verification Plan

### Tier 1 (pre-deploy, static)
- `rg -n "'Set gig pay'" lib/features/events/widgets/gig_form_fields.dart`
  returns exactly one hit on the modified line.
- `rg -n "'Set Gig Pay'" lib` returns **zero** hits (the old literal is
  fully gone from the app source).
- The four sibling literals still each match exactly once with unchanged
  case:
  - `rg -n "'Set load-in time'" lib/features/events/widgets/gig_form_fields.dart`
  - `rg -n "'Set soundcheck time'" lib/features/events/widgets/event_editor_drawer.dart`
  - `rg -n "'Add contact'" lib/features/events/widgets/gig_form_fields.dart`
  - `rg -n "'Add expense'" lib/features/events/widgets/gig_form_fields.dart`
- `git diff --stat main...feature/gig-pay-label-sentence-case` shows a
  single file changed
  (`lib/features/events/widgets/gig_form_fields.dart`) with `1` insertion
  and `1` deletion.
- `flutter analyze` is clean (no new warnings or errors introduced).

### Tier 2 (post-deploy / visual)
- Open the Add Event sheet with type = Gig. In the empty state (no gig
  pay set), the CTA reads `Set gig pay` and visually matches the four
  sibling CTAs in the same sheet (`Set load-in time`, `Set soundcheck
  time`, `Add contact`, `Add expense`) — same rose outline, same
  height, same font size (14px).
- After setting a gig pay amount, the button switches to the value-set
  `AppButton.outlined` state and shows the amount (and optional payer
  name) — behavior unchanged.

Idempotency / ordering / data-integrity checks: n/a (no submission flow or
data mutation touched).

## QA Regression Areas
- Add Event sheet (gig type) — empty state of the Gig Pay CTA renders the
  new label and behaves identically (tap opens the same Gig Pay editor).
- Add Event sheet (gig type) — Gig Pay value-set state (after setting an
  amount) renders unchanged (still the `AppButton.outlined` with amount +
  optional payer, still tappable to edit).
- The four sibling add-value CTAs (`Set load-in time`, `Set soundcheck
  time`, `Add contact`, `Add expense`) render identically to before.
- Rehearsal event type (no Gig Pay section) — unaffected.

## Rollout Strategy
Ship on the next standard release. No feature flag, no migration, no
staged rollout, no data backfill. Rollback is a one-literal revert.

## Out of Scope
- Restyling `EventAddValueButton` (font size, color, border, height).
- Changing the four sibling labels (already sentence case).
- Changing the Gig Pay value-set state label (dynamic amount string).
- Changing any section header label (`Gig Pay (optional)`, `Expenses`,
  `Contacts`, `Load-in Time`, `Soundcheck`) — those are `Text` widgets
  above the CTAs, distinct from the CTA labels themselves.
- Any label in `event_editor_drawer.dart` other than the four siblings
  (which aren't being changed anyway).
- Copy tweaks in `snackbar_helper.dart`, error messages, or anywhere else.
