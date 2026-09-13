# ARCHITECT_PLAN — Reorder Financials in Quick Actions

## Feature Slug

`feature/quick-actions-financials-order`

## Feature Title

Reorder Financials in Quick Actions

## Problem Summary

In the Home tab's "Quick Actions" section, `Financials` currently renders as the
third (rightmost) button. The requirement is that `Financials` renders as the
second button — immediately after `+ Add Event` — with `+ Create Setlist`
displaced to third.

Current visible order (all three shown): `+ Add Event`, `+ Create Setlist`,
`Financials`.

Required visible order (all three shown): `+ Add Event`, `Financials`,
`+ Create Setlist`.

## Root Cause

**Confidence: HIGH (confirmed in code).**

`QuickActionsRow.build()` in
[lib/features/home/widgets/quick_actions_row.dart](../../../lib/features/home/widgets/quick_actions_row.dart)
constructs its button list by appending in source-code order: the
`if (showAddEvent)` block runs first (lines 46–53), then the
`if (showCreateSetlist)` block (lines 55–63), then the `if (showFinancials)`
block (lines 65–73). No sorting/priority mechanism exists; the render order is
literally the source order of those three `if` blocks.

To make `Financials` the second visible button, swap the
`if (showFinancials)` block ahead of the `if (showCreateSetlist)` block.

## Existing System Analysis

`QuickActionsRow` is a pure `StatelessWidget`. It exposes three optional
callbacks (`onAddEvent`, `onCreateSetlist`, `onFinancials`) and three visibility
booleans (`showAddEvent`, `showCreateSetlist`, `showFinancials`). Visibility is
controlled entirely by the parent via RBAC gating.

Three call sites reference `QuickActionsRow`:

1. [lib/features/home/home_tab_content.dart](../../../lib/features/home/home_tab_content.dart)
   (around lines 977–998) — the only call site that wires `onFinancials` /
   `showFinancials`. This is the only place the Financials button can actually
   render, and therefore the only place the observed ordering exists.
2. [lib/features/home/home_screen.dart](../../../lib/features/home/home_screen.dart)
   (around lines 891–911) — does not pass `showFinancials` or `onFinancials`;
   uses the default `showFinancials = true` but with a null callback the button
   would render disabled. However, this widget is on an alternate/legacy path
   and is not the surface under discussion.
3. [lib/features/home/widgets/empty_home_state.dart](../../../lib/features/home/widgets/empty_home_state.dart)
   (around lines 158–178) — does not pass `showFinancials` or `onFinancials`
   either.

None of the three call sites encodes button ordering — each passes callbacks
plus booleans and lets the widget decide layout order. Reordering inside
`QuickActionsRow.build()` therefore correctly propagates to every consumer with
no call-site changes.

No test file exercises `QuickActionsRow` today (searched
`test/**/quick_actions*` — no matches). No reference doc under `docs/reference/`
describes Quick Actions ordering.

## Proposed Solution

In `QuickActionsRow.build()`, move the `if (showFinancials)` block so it runs
immediately after the `if (showAddEvent)` block and before the
`if (showCreateSetlist)` block. Each block already contains the
`if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));` separator
guard, so the 12px gap between buttons continues to render correctly regardless
of which two buttons are adjacent.

No API change. No new parameter. No new class/provider/repository. No call-site
change.

## Database Impact

n/a

## Flutter Architecture Changes

n/a — no state management, no new provider, no new controller. Change is
confined to the imperative body of one `build()` method inside a pure
`StatelessWidget`.

## Files to Create

- [test/features/home/widgets/quick_actions_row_test.dart](../../../test/features/home/widgets/quick_actions_row_test.dart)
  — one widget test verifying the visible label order is
  `+ Add Event`, `Financials`, `+ Create Setlist` when all three buttons are
  shown. Justified because no existing test file covers `QuickActionsRow` and
  the ordering is now behaviorally load-bearing.

## Files to Modify

- [lib/features/home/widgets/quick_actions_row.dart](../../../lib/features/home/widgets/quick_actions_row.dart)
  — move the `if (showFinancials) { ... }` block from its current position
  (after `if (showCreateSetlist)`) to sit immediately after the
  `if (showAddEvent)` block and before the `if (showCreateSetlist)` block. Keep
  each block's spacer guard intact. No other change to this file.

## Files Off-Limits

- [lib/features/home/home_tab_content.dart](../../../lib/features/home/home_tab_content.dart)
  — call site; passes callbacks + flags with no order coupling. Changing it is
  unnecessary and would broaden scope.
- [lib/features/home/home_screen.dart](../../../lib/features/home/home_screen.dart)
  — call site; same reasoning.
- [lib/features/home/widgets/empty_home_state.dart](../../../lib/features/home/widgets/empty_home_state.dart)
  — call site; same reasoning.
- Any file under `lib/features/financials/`, `lib/features/setlists/`,
  `lib/features/events/` — this is a UI ordering change; feature logic is
  untouched.
- The stale doc comment on lines 6–10 of `quick_actions_row.dart` (mentions
  labels `"+ Schedule Rehearsal"`, `"+ Create Setlist"`, `"+ Create Gig"` which
  no longer match the current button labels). Pre-existing staleness unrelated
  to this change; do not opportunistically refactor.

## Change Budget

- Net line delta in `lib/features/home/widgets/quick_actions_row.dart`: **0**
  (pure block reorder — same lines, moved).
- New files: **1** (the widget test).
- New public classes / methods in library code: **0**.
- New dependencies: **0**.

## System Impact Map

- Gigs: unaffected
- Rehearsals: unaffected
- Setlists: unaffected
- Members: unaffected
- Auth: unaffected
- Routing: unaffected
- Notifications: unaffected
- Platforms: All (iOS, Android, macOS, Web) affected identically —
  `QuickActionsRow` is platform-agnostic Flutter UI with no conditional code
  paths.

## Regression Risk

**LOW.** The change is confined to the order of three items appended to a local
`List<Widget>` inside a single `build()` method of a pure `StatelessWidget`. No
auth, session, routing, init-order, database, RLS, RPC, migration, or
platform-conditional code is touched. Every consumer call site already passes
callbacks and booleans without any dependency on render order.

## Engineer Task Breakdown

1. In
   [lib/features/home/widgets/quick_actions_row.dart](../../../lib/features/home/widgets/quick_actions_row.dart),
   inside `QuickActionsRow.build()`, relocate the entire `if (showFinancials) { ... }`
   block so it appears immediately after the `if (showAddEvent) { ... }` block
   and before the `if (showCreateSetlist) { ... }` block. Preserve each block's
   existing `if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));`
   spacer guard exactly as written. Do not modify any other line in the file
   (including the stale header comment on lines 6–10).
2. Create
   [test/features/home/widgets/quick_actions_row_test.dart](../../../test/features/home/widgets/quick_actions_row_test.dart)
   with a single widget test that:
   - Pumps `QuickActionsRow` inside a `MaterialApp` + `Scaffold` with
     `showAddEvent: true`, `showCreateSetlist: true`, `showFinancials: true`,
     and non-null no-op callbacks for all three.
   - Finds all rendered `OutlinedButton` widgets in tree order using
     `find.byType(OutlinedButton)` via `tester.widgetList<OutlinedButton>` and
     extracts each button's child `Text.data`.
   - Asserts the resulting list equals `['+ Add Event', 'Financials',
     '+ Create Setlist']`.
3. Do not touch any consumer of `QuickActionsRow`.

## Verification Plan

### Tier 1 — Pre-deploy (mechanical, QA-executable)

1. `flutter analyze` — must complete with no new warnings or errors.
2. `flutter test test/features/home/widgets/quick_actions_row_test.dart` — the
   new widget test passes, confirming labels appear in tree order
   `+ Add Event`, `Financials`, `+ Create Setlist`.
3. `flutter test` (full suite) — no pre-existing test regresses. All existing
   financials, home, and setlist tests continue to pass.

### Tier 2 — Post-deploy

n/a (no migration, no edge function, no data change, no server-side
component). This change ships as pure client-side UI in the next app release.

### Owner-run punch list (Tony, at PR-test / release time)

QA hands this to Tony verbatim; it is not a QA gate.

1. Launch the app on macOS: `./run.sh macos`. Sign in as an admin (or a member)
   of a band where you have permission to create events, create setlists, and
   view financials.
2. Navigate to the Home tab and scroll to the "Quick Actions" section.
   - Expected: three buttons appear left-to-right in this exact order:
     `+ Add Event`, `Financials`, `+ Create Setlist`.
3. Launch the app on iOS via `./run.sh ios` and repeat step 2.
   - Expected: identical order to step 2.
4. Launch the app on Android via `flutter run -d android` (emulator or connected
   device) and repeat step 2.
   - Expected: identical order to step 2.
5. Launch the app on Web via `flutter run -d chrome` and repeat step 2.
   - Expected: identical order to step 2.
6. On any platform, switch to a contributor account that lacks the
   "Can view financials" sub-permission but retains setlist and event
   permissions.
   - Expected: the Home tab's Quick Actions section shows exactly two buttons in
     order `+ Add Event`, `+ Create Setlist` (the `Financials` button is hidden;
     the remaining two collapse together with the standard 12px gap).

## QA Regression Areas

- The widget test added in step 2 of the task breakdown mechanically covers the
  "all three visible" ordering — this is the only ordering-behavior gate QA is
  positioned to enforce without a running app.
- `home_screen.dart` and `empty_home_state.dart` do not render the Financials
  button (they never wire `onFinancials`), so this change is visually a no-op
  for those code paths. No additional QA coverage required for them.
- No changes to financials data flow, permissions, RBAC gating logic, or
  navigation targets — existing financials/permissions/home tests remain
  authoritative for those behaviors and must continue to pass.

## Rollout Strategy

Standard PR → merge to `main` → next app release. No feature flag, no
migration, no phased rollout, no server-side component. This is a pure
client-side visual reorder that lands atomically with the client build it ships
in.

## Out of Scope

- Rewording the stale header comment on lines 6–10 of
  `lib/features/home/widgets/quick_actions_row.dart` (mentions labels
  `"+ Schedule Rehearsal", "+ Create Setlist", "+ Create Gig"` which do not
  match the current code — pre-existing drift, not this change's problem).
- Any change to consumer call sites in `home_tab_content.dart`,
  `home_screen.dart`, or `empty_home_state.dart`.
- Any change to financials feature code, RBAC gating, or the Financials button's
  destination screen.
- Adding golden or visual-regression coverage for Quick Actions — the widget
  test on label order is sufficient for the risk level.
- Expanding widget test coverage to the two-visible or one-visible permutations
  — the layout guard (`if (buttons.isNotEmpty) buttons.add(SizedBox(width: 12))`)
  is unchanged by this refactor and remains covered by the existing static
  analysis of the reordered code; adding cases here would be
  disproportionate to a block-swap.
