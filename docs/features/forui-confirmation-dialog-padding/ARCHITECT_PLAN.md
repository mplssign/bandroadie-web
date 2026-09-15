# ARCHITECT_PLAN — forui-confirmation-dialog-padding

## Feature Slug

`forui-confirmation-dialog-padding` (branch `bug/forui-confirmation-dialog-padding`)

## Feature Title

Use Forui confirmation dialogs with proper content padding

## Problem Summary

The three confirmation dialogs called out in the bug report — **Cancel Invite?**
(pending band invitations), **Remove `<Name>`?** (band member removal), and
**Delete Venue?** — render their title, body, and action row hard against the
inner edge of the Forui dialog card. On iOS this produces the cramped,
edge-collision layout in the attached screenshots; on other platforms the same
widget tree paints the same way but the artifact is less obvious. Wording,
button semantics, and destructive styling are correct — the defect is purely
inner content padding of the shared alert dialog widget.

## Root Cause (Confidence: HIGH)

All three dialogs are opened via `showAppDialog(title:, message:, actions:)`
([lib/components/ui/app_dialog.dart](lib/components/ui/app_dialog.dart#L33-L60)),
which — when no custom `builder` is supplied — routes to `AppAlertDialog`
([lib/components/ui/app_dialog.dart](lib/components/ui/app_dialog.dart#L66-L114)):

```dart
FDialog(
  builder: (context, style) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: ...),
      const SizedBox(height: 16),
      Text(message),
      const SizedBox(height: 24),
      Row(children: actions.map(...)),
    ],
  ),
);
```

Forui's `FDialog` renders whatever the `builder` returns **directly inside its
`DecoratedBox`** with no built-in content padding
([~/.pub-cache/hosted/pub.dev/forui-0.26.0/lib/src/widgets/dialog.dart lines 421–441](../../../../.pub-cache/hosted/pub.dev/forui-0.26.0/lib/src/widgets/dialog.dart)):

```dart
Widget dialog = DecoratedBox(
  decoration: style.decoration,
  child: widget.clipBehavior == .none
      ? widget.builder(context, style)
      : ClipPath(..., child: widget.builder(context, style)),
);
```

Forui exposes only two `FDialog` constructors — `FDialog(builder:)` and
`FDialog.adaptive(horizontalBuilder:, verticalBuilder:)`. There is no
structured `title/body/actions` constructor that would supply default content
padding. `FDialogStyle.insetPadding` is the **outer** margin between the dialog
and the screen edge (`EdgeInsets.symmetric(horizontal: 40, vertical: 24)` by
default), not the space between content and the card border.

Because `AppAlertDialog` supplies its `Column` with **zero surrounding
padding**, the title, message, and action row sit flush against the FDialog
card border. That is exactly the "title/body/actions too close to the dialog
bounds" behavior in the bug report. HIGH confidence — the code path is
traceable end-to-end in source and the missing padding is directly visible.

## Existing System Analysis

**Shared alert-dialog helper** (`AppAlertDialog` in
[lib/components/ui/app_dialog.dart](lib/components/ui/app_dialog.dart)):
- One structural bug (missing outer content padding) causes the cramped layout
  everywhere it is used.
- Eight production call sites currently route through this widget via the
  `title/message/actions` overload of `showAppDialog`:
  1. [lib/features/contacts/widgets/invite_members_screen.dart](lib/features/contacts/widgets/invite_members_screen.dart#L293-L307) — *Cancel Invite?* (feature input)
  2. [lib/features/contacts/widgets/band_member_edit_drawer.dart](lib/features/contacts/widgets/band_member_edit_drawer.dart#L205-L222) — *Remove `<Name>`?* (feature input)
  3. [lib/features/contacts/widgets/venue_form_screen.dart](lib/features/contacts/widgets/venue_form_screen.dart#L244-L259) — *Delete Venue?* (feature input)
  4. [lib/features/contacts/widgets/contact_form_screen.dart](lib/features/contacts/widgets/contact_form_screen.dart#L153-L168) — *Delete Contact?*
  5. [lib/features/members/widgets/role_management_sheet.dart](lib/features/members/widgets/role_management_sheet.dart#L182-L199) — legacy *Remove `<Name>`?*
  6. [lib/features/profile/my_profile_screen.dart](lib/features/profile/my_profile_screen.dart#L558-L572) — *Delete Role*
  7. [lib/features/calendar/widgets/add_block_out_drawer.dart](lib/features/calendar/widgets/add_block_out_drawer.dart#L317-L339) — *Delete Block Out?* (choice, 3 actions)
  8. [lib/features/calendar/widgets/add_block_out_drawer.dart](lib/features/calendar/widgets/add_block_out_drawer.dart#L341-L358) — *Delete Block Out?* (simple, 2 actions)

  Fixing the shared component fixes call sites 1–3 (bug scope) and improves
  call sites 4–8 in the same visual direction (also cramped today, will now
  look consistent). That is desired behavior, not a regression.

**Custom-builder call sites (unaffected — different code path):**
- `bands/band_form_screen.dart:825` (Restore Band Data),
  `events/widgets/gig_form_fields.dart:172` (Add-contact prompt),
  `gigs/widgets/availability_prompt_modal.dart:48`,
  `rehearsals/widgets/rehearsal_availability_prompt_modal.dart:48`,
  `profile/my_profile_screen.dart:429` (Add custom role),
  `notifications/widgets/notification_settings_modal.dart:25`,
  `settings/settings_screen.dart:113` (Delete Account) — each of these passes
  a `builder:` to `showAppDialog` and supplies its own padding wrapper. They do
  not go through `AppAlertDialog` and are out of scope.

**Distinct helper (not this path):**
- [lib/components/ui/confirm_action_dialog.dart](lib/components/ui/confirm_action_dialog.dart) — `showConfirmActionDialog`
  uses Material `AlertDialog` with explicit `contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 24)`. Not affected.

**Design token reference** ([lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart#L9-L34)):
- `Spacing.space24 = 24.0` is the canonical dialog content inset the repo already
  uses in `confirm_action_dialog.dart`, matching Forui's Shadcn-derived
  `p-6 = 24px` card padding convention. This is the correct token to apply.

**Existing tests** ([test/components/ui/app_dialog_test.dart](test/components/ui/app_dialog_test.dart)):
- Five widget tests cover `showAppDialog` display, `AppAlertDialog` rendering,
  destructive/outline variant selection, custom-builder passthrough, and
  argument-validation error. None currently assert content padding.

## Proposed Solution

Wrap the `Column` returned by `AppAlertDialog.build()`'s `FDialog.builder` in
a single `Padding(padding: EdgeInsets.all(Spacing.space24), ...)`. This
supplies the missing card-inner content padding for every dialog that uses the
shared helper, restoring proper offset from the FDialog decoration border on
all four sides. Wording, action labels, `isDestructive` styling, `FButton`
variants, inter-element `SizedBox` spacing, and the `Row` alignment of the
action buttons are all preserved verbatim. No API surface change to
`showAppDialog` / `DialogAction` / `AppAlertDialog` constructor.

Rationale for `Spacing.space24`:
- Matches the existing `confirm_action_dialog.dart` content-padding value in
  the same folder — keeps the two confirmation surfaces visually consistent.
- Aligns with Forui's Shadcn-derived `p-6` (24px) card padding, which its own
  dialog snippets use.
- Preserves clear touch targets: the `FButton` action row keeps ≥ 24px from
  the card edge on the right and bottom.

Why not add a new `FDialog.title/body/actions` structured constructor? Forui
0.26 does not expose one; that would be an upstream feature request. The
single-Padding wrapper is the smallest correct change.

## Database Impact

n/a — no migrations, no RLS policies, no RPC functions, no triggers, no edge
functions, no schema changes.

## Flutter Architecture Changes

None. No new provider, controller, repository, service, or route. No
`Notifier` or `NotifierProvider` added. This is a leaf-widget padding fix
inside an existing shared component.

## Files to Create

None.

## Files to Modify

| File | Change |
|---|---|
| [lib/components/ui/app_dialog.dart](lib/components/ui/app_dialog.dart) | Add `import 'package:bandroadie/app/theme/design_tokens.dart';` at the top with the existing imports. Inside `AppAlertDialog.build()`, wrap the existing `Column(...)` (currently the direct return of `FDialog.builder`) in `Padding(padding: const EdgeInsets.all(Spacing.space24), child: <that same Column verbatim>)`. Do not change any text, spacing constant, action mapping, `FButtonVariant` selection, or the `builder`/`title/message/actions` overload logic in `showAppDialog`. |
| [test/components/ui/app_dialog_test.dart](test/components/ui/app_dialog_test.dart) | Add one new `testWidgets` case inside the existing `group('AppDialog', ...)` block, named `'AppAlertDialog wraps content in Spacing.space24 padding'`. Mount `AppAlertDialog` with any title/message/one action (mirror the setup of the existing `'AppAlertDialog renders correctly'` test at lines 47–91). Assert that the `Padding` widget with `padding == const EdgeInsets.all(24.0)` exists as an ancestor of the title `Text`. Import `package:bandroadie/app/theme/design_tokens.dart` if referencing `Spacing.space24` symbolically; otherwise the literal `24.0` matches. |

## Files Off-Limits

| File / Path | Why |
|---|---|
| `lib/features/contacts/widgets/invite_members_screen.dart` | Call site — wording, action labels, and behavior preserved; the fix belongs in the shared component. |
| `lib/features/contacts/widgets/band_member_edit_drawer.dart` | Same as above. |
| `lib/features/contacts/widgets/venue_form_screen.dart` | Same as above. |
| `lib/features/contacts/widgets/contact_form_screen.dart`, `lib/features/members/widgets/role_management_sheet.dart`, `lib/features/profile/my_profile_screen.dart`, `lib/features/calendar/widgets/add_block_out_drawer.dart`, `lib/features/settings/settings_screen.dart` | Not in Feature Input scope. They will inherit the shared-component padding fix as a byproduct; do not modify these files. |
| `lib/components/ui/confirm_action_dialog.dart` | Different code path (Material `AlertDialog` with its own `contentPadding`). Not affected by this bug. |
| `lib/features/bands/band_form_screen.dart`, `lib/features/events/widgets/gig_form_fields.dart`, `lib/features/gigs/widgets/availability_prompt_modal.dart`, `lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart`, `lib/features/notifications/widgets/notification_settings_modal.dart` | All use the custom-`builder:` path of `showAppDialog` and manage their own padding. Not in scope. |
| `docs/features/band-form-overlay-redesign/` | Belongs to separate untracked planning work per Feature Input — do not touch. |
| `pubspec.yaml`, `pubspec.lock` | No dependency change required. |
| `supabase/migrations/**`, `supabase/functions/**`, any RLS or RPC | No server change required. |
| `lib/main.dart`, any code path executed before `runApp` | Init order is untouched. |

## Change Budget

| Metric | Expected |
|---|---|
| Net line delta — `lib/components/ui/app_dialog.dart` | **+4** (1 import + `Padding(...)` open + `child:` line + closing `)`; 0 lines removed) |
| Net line delta — `test/components/ui/app_dialog_test.dart` | **+35** (single `testWidgets` block asserting Padding ancestor) |
| New files | 0 |
| New public classes | 0 |
| New public methods | 0 |
| New dependencies (`pubspec.yaml`) | 0 |
| New migrations | 0 |
| New RPC functions | 0 |
| New edge functions | 0 |

QA measures the actual diff against these numbers.

## System Impact Map

| System | Status |
|---|---|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists | unaffected |
| Members | **affected (visual only)** — Remove-member, Cancel-invite, legacy Remove-member (role_management_sheet), Delete-custom-role dialogs regain proper padding |
| Contacts & Venues | **affected (visual only)** — Delete Venue, Delete Contact dialogs regain proper padding |
| Auth | unaffected |
| Routing / Deep links | unaffected |
| Notifications | unaffected |
| iOS | **primary target** — where the cramped layout is reported |
| Android | unaffected behaviorally; identical padding improvement applies (same widget tree) |
| macOS | unaffected behaviorally; identical padding improvement applies |
| Web | unaffected behaviorally; identical padding improvement applies |
| Init order | untouched |
| Config (`--dart-define`) | untouched |
| RLS / RPC / migrations / edge functions | untouched |

## Regression Risk

**LOW.**

- Change is a single `Padding` wrapper around an existing `Column` in one leaf
  widget. No API surface change; no behavior change.
- No auth/session/routing/init-order/DB code touched.
- No new dependencies; no version pin change.
- Existing widget tests in `test/components/ui/app_dialog_test.dart` continue
  to pass because they assert on `Text` findability and `FButton` variant —
  none of which move.
- Dialog width is unchanged: `FDialog.constraints` still defaults to
  `BoxConstraints(minWidth: 280, maxWidth: 560)`. The 24px inset applies
  inside the card, so a `280 − 48 = 232px` minimum content width remains
  comfortably above the title-line requirements of the current copy
  ("Cancel Invite?", "Delete Venue?", "Remove `<longest realistic name>`?").
- Only observable change: dialogs that route through `AppAlertDialog` gain
  24px of breathing room on all four sides. This is the desired outcome for
  the three bug-report dialogs, and a consistency improvement for the five
  others that share the code path.

## Engineer Task Breakdown

Two atomic tasks, in order:

1. **Add outer content padding to `AppAlertDialog`.** Edit
   [lib/components/ui/app_dialog.dart](lib/components/ui/app_dialog.dart):
   - Add `import 'package:bandroadie/app/theme/design_tokens.dart';` alongside
     the existing `package:flutter/material.dart` and `package:forui/forui.dart`
     imports.
   - In `AppAlertDialog.build()` at [lib/components/ui/app_dialog.dart](lib/components/ui/app_dialog.dart#L84-L112),
     wrap the entire existing `Column(...)` (currently the direct return of
     the `FDialog.builder`) in `Padding(padding: const EdgeInsets.all(Spacing.space24), child: <the same Column verbatim>)`.
   - Do not change any child of the Column: preserve the title `Text` and its
     `TextStyle(fontSize: 18, fontWeight: FontWeight.bold)`, the
     `SizedBox(height: 16)`, the message `Text`, the `SizedBox(height: 24)`,
     the action `Row(mainAxisAlignment: MainAxisAlignment.end, ...)`, and the
     per-action `Padding(padding: const EdgeInsets.only(left: 8), child: FButton(...))`
     including `variant: action.isDestructive ? FButtonVariant.destructive : FButtonVariant.outline`.
   - Do not touch `showAppDialog`, `DialogAction`, or the `builder`-vs-title
     branching logic.

2. **Assert padding in the widget test suite.** Edit
   [test/components/ui/app_dialog_test.dart](test/components/ui/app_dialog_test.dart):
   - Inside the existing `group('AppDialog', ...)`, add exactly one new
     `testWidgets('AppAlertDialog wraps content in Spacing.space24 padding', (tester) async { ... })`
     block immediately after the existing `'AppAlertDialog renders correctly'`
     case (line ~91). Mirror that case's `MaterialApp` + `FTheme` +
     `Scaffold` setup verbatim so the theming pipeline is identical.
   - In the test body, mount `AppAlertDialog(title: 'Alert', message: 'Body', actions: [DialogAction(label: 'OK', onPressed: () {})])`
     and assert:
     - `find.text('Alert')` is `findsOneWidget` (parity with existing tests).
     - The first `Padding` ancestor of the title `Text` widget has
       `padding == const EdgeInsets.all(24.0)`. Use
       `find.ancestor(of: find.text('Alert'), matching: find.byWidgetPredicate((w) => w is Padding && w.padding == const EdgeInsets.all(24.0)))`
       and expect `findsOneWidget`. This asserts the shared component supplies
       the 24px inset and locks the fix in against future regressions.
   - Do not modify or delete any existing test in the file.

No third task. Any additional refactor (e.g. extracting a `_kDialogContentPadding`
constant, migrating other `FDialog` callers, moving to `FDialog.adaptive`,
adjusting inter-element `SizedBox` heights) is out of scope.

## Verification Plan

### Tier 1 — QA gate (mechanically executable, no running app)

QA runs these checks and returns pass/fail. All are required for APPROVED.

1. **Static analysis:** `flutter analyze` — must exit 0, no new warnings or
   errors introduced. `AppAlertDialog` is the only Flutter code modified.
2. **Existing dialog tests:** `flutter test test/components/ui/app_dialog_test.dart`
   — all five pre-existing tests must still pass. They assert on `find.text`,
   `find.byType(FDialog)`, `find.byType(AppAlertDialog)`, `find.byType(FButton)`,
   and `FButton.variant`. None of these are moved by wrapping the Column in a
   Padding, so all should remain green.
3. **New padding test:** the newly added `'AppAlertDialog wraps content in Spacing.space24 padding'`
   case must pass, proving the fix is in place.
4. **Full test suite (dialog blast radius):** `flutter test` — any test that
   exercises a screen using `showAppDialog(title:, message:, actions:)` must
   still pass. QA should specifically confirm none of the following tests
   regress (if they exist in the current repo — check with a spot-run):
   - anything under `test/features/contacts/`
   - anything under `test/features/members/`
   - anything under `test/features/profile/`
   - anything under `test/features/calendar/`

   These tests currently pass with the unpadded Column; they should also pass
   with the padded Column because none of them assert on layout coordinates or
   Padding widgets.
5. **Diff-vs-budget check:** QA reads the actual diff and verifies:
   - `lib/components/ui/app_dialog.dart` net delta is ≤ **+6 lines** (budgeted
     +4; small allowance for trailing-comma formatting differences).
   - `test/components/ui/app_dialog_test.dart` net delta is ≤ **+50 lines**
     (budgeted +35; allowance for setup boilerplate parity with the existing
     test).
   - No file outside the two listed under "Files to Modify" is touched
     (in particular, no `pubspec.yaml`, no migrations, no
     `confirm_action_dialog.dart`, no direct call site, and nothing under
     `docs/features/band-form-overlay-redesign/`).
   - Exceeding either budget by > 25% is a Warning; > 50% is a Critical
     finding.
6. **SQL / migration review:** n/a — no SQL, migration, RPC, RLS, or edge
   function change in the diff.

### Tier 2 — owner-run punch list (Tony, at PR-test time on iOS)

QA cannot launch the app, so the visual verification is delegated to Tony as
an exact, ordered punch list. QA should hand this section verbatim.

**Setup:** install the PR build on a real iPhone (device where the original
screenshots were captured). Sign in and switch into a band where you are an
admin. Have at least one pending invite, one non-admin test member, and one
disposable test venue.

1. From the band context, open **Invite Members** and locate the pending
   invitation row.
   *Expected:* Row has a Cancel-invite affordance (X or trailing button).
2. Tap **Cancel invite** on that row.
   *Expected:* A dialog appears titled **"Cancel Invite?"** with body
   **"Cancel invite for `<email>`?"** and two actions **Cancel** and
   **Cancel Invite**.
3. Visually confirm on that dialog:
   - The **title text** starts at least ~20 px in from the top and left of
     the dialog card (no longer flush against the border).
   - The **body text** is inset ~20 px from both left and right dialog edges.
   - The **Cancel Invite** action button has clear space (~24 px) between it
     and the bottom-right corner of the dialog card.
   - No text is clipped; the dialog no longer looks cramped compared to the
     bug-report screenshot.
4. Tap **Cancel** — dialog dismisses with no side effect. Tap the row's
   Cancel-invite affordance again, this time tap **Cancel Invite** — invitation
   is removed and the pending-invite list refreshes as before.
5. Open **Member management**, open a non-admin test member's edit drawer,
   tap **Remove from band**.
   *Expected:* Dialog titled **"Remove `<Name>`?"** with body
   *"Are you sure you want to remove this member from the band? This cannot
   be undone."* and actions **Cancel** and **Remove** (red / destructive).
6. Repeat the visual inspection from step 3 on this dialog. In particular
   confirm the destructive **Remove** button retains its red styling *and*
   sits inset from the dialog edge.
7. Tap **Cancel** — no removal. Tap **Remove** on the disposable test member
   — confirm the removal succeeds and the drawer/list update as before.
8. Open **Venue management**, open a saved disposable test venue, tap
   **Delete Venue**.
   *Expected:* Dialog titled **"Delete Venue?"** with body *"This action
   cannot be undone."* and actions **Cancel** and **Delete** (red /
   destructive).
9. Repeat the visual inspection from step 3. Confirm the destructive
   **Delete** button remains red and inset.
10. Tap **Cancel** — no deletion. Tap **Delete** on the disposable test venue
    — confirm the venue is deleted.
11. Regression spot-check (same padding treatment now inherited): open
    **Delete Contact** from a contact form, **Delete Custom Role** in My
    Profile, and **Delete Block Out** from a block-out drawer. Confirm each
    dialog now has the same comfortable padding — none should look worse
    than before the fix; all should look consistent with steps 3, 6, and 9.
12. Cross-platform sanity: launch the same build on macOS (or Chrome) and
    open any one of the above dialogs. Confirm the padding fix applies
    equally there and no layout is clipped at any reasonable dialog width
    within `FDialog`'s default 280–560 px constraint.

Any deviation from the expected result in steps 3, 6, or 9 is a blocker.

## QA Regression Areas

QA should specifically confirm the following are **not** broken:

- **Dialog dismissal behavior:** `barrierDismissible` still respected;
  Cancel actions still pop with `false`, destructive actions still pop with
  `true` — no change to `DialogAction.onPressed` wiring.
- **Destructive vs. outline button variant:** existing test
  `'destructive action uses destructive variant'` continues to pass; the
  `variant: action.isDestructive ? FButtonVariant.destructive : FButtonVariant.outline`
  logic is untouched.
- **Custom-builder path:** existing test
  `'custom builder is used when provided'` continues to pass; the
  `builder != null` branch in `showAppDialog` bypasses `AppAlertDialog`
  entirely, so the seven custom-builder dialogs (Restore Band, gig contact
  prompt, availability prompts, add-custom-role, notification-permission,
  Delete-Account) render exactly as they do today.
- **`ArgumentError` guard:** existing test
  `'throws ArgumentError when builder is null and args incomplete'`
  continues to pass — the null-check branch in `showAppDialog` is untouched.
- **Dialog inset padding (outer):** Forui's `FDialogStyle.insetPadding` is
  untouched, so the dialog still sits `40px` from screen sides and `24px`
  from top/bottom on iOS. The fix only adds *inner* padding.
- **No unintended re-styling of the seven custom-builder dialogs** — they
  do not go through `AppAlertDialog`, so their appearance must be identical
  to today. Spot-verify with the Restore Band Data dialog if convenient.

## Rollout Strategy

Standard: merge PR to `main` → normal release cadence. No feature flag, no
migration ordering, no coordinated deployment. Fix is fully forward- and
backward-compatible with any Supabase state (no server change). Rollback is
`git revert` of the merged commit.

## Out of Scope

- The seven custom-`builder:` `showAppDialog` call sites — they manage their
  own padding.
- The Material-based `ConfirmActionDialog` in
  `lib/components/ui/confirm_action_dialog.dart` — already properly padded.
- Any wording changes to any dialog title, body, or action label.
- Any adjustment to the intra-Column `SizedBox` spacing (`16` between title
  and body, `24` between body and actions) inside `AppAlertDialog` — the
  reported issue is edge padding, not inter-element spacing.
- Introducing a new `FDialog`-based structured `title/body/actions`
  constructor or migrating to `FDialog.adaptive`.
- Golden-image tests for dialogs (repo has minimal golden coverage; a
  structural Padding assertion is sufficient).
- Anything under `docs/features/band-form-overlay-redesign/` — reserved
  for separate planning work per Feature Input.
- `pubspec.yaml` / `forui` version bump.
- iOS / Android / macOS / Web platform-conditional code; the fix is
  platform-agnostic Flutter widget code.
