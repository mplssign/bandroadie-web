# ARCHITECT_PLAN — feature/event-card-background-colors

## Feature Slug

`feature/event-card-background-colors`

## Feature Title

Improve event card background colors

## Problem Summary

On the Home dashboard, the three horizontally-scrolling event card variants —
Potential (Gig and Rehearsal), Confirmed Gig, and Confirmed Rehearsal — render
their background fills at the same alpha level (`0x14`, ~7.8% opacity). The
Potential orange tint is too faint to communicate urgency, and the Confirmed
Gig (green) and Confirmed Rehearsal (sky-blue) tints feel over-transparent
against the dark surface. The requested change is a background-color tint
adjustment only — layout, borders, gradients, animation, typography, and
interaction behavior all stay as-is.

## Root Cause (Confidence: HIGH)

The four background tint values are hard-coded `Color(0x14...)` literals inside
the card widgets themselves — there is no shared token, so the four surfaces
were all set to the same low alpha at build time and have never been re-tuned:

- [lib/features/home/widgets/potential_gig_card.dart](lib/features/home/widgets/potential_gig_card.dart#L315) —
  `color: const Color(0x14F97316)` (orange-500 @ ~7.8% alpha) inside the
  `AppCard` inside `AnimatedBuilder`.
- [lib/features/home/widgets/rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart#L351) —
  same `Color(0x14F97316)` on the potential-rehearsal variant.
- [lib/features/home/widgets/rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart#L600) —
  `color: const Color(0x140EA5E9)` (sky-500 @ ~7.8% alpha) on the confirmed
  variant.
- [lib/features/home/widgets/confirmed_gig_card.dart](lib/features/home/widgets/confirmed_gig_card.dart#L58) —
  `color: const Color(0x1422C55E)` (green-500 @ ~7.8% alpha).

Confidence is HIGH: the literals are directly on the `AppCard.color` argument
in each build tree, not derived from theme or a provider, and grep against
`lib/**` confirms these are the only sites where each literal is used as a
card fill (the two other hits — `availability_prompt_modal.dart` and
`rehearsal_availability_prompt_modal.dart` — are modals, not event cards, and
are explicitly out of scope; a third hit in `app_card.dart` is a doc-comment
example).

## Existing System Analysis

- Home dashboard renders these four cards via
  [home_screen.dart](lib/features/home/home_screen.dart) and
  [home_tab_content.dart](lib/features/home/home_tab_content.dart). Neither
  file sets any card fill color — they only construct the widgets. No routing
  or state-management changes are needed.
- `AppCard`
  ([lib/components/ui/app_card.dart](lib/components/ui/app_card.dart)) accepts
  a nullable `color` and renders it as the container fill; the four card
  widgets pass in the tint literal directly. `AppCard` itself needs no change.
- The Confirmed Gig and Confirmed Rehearsal variants pair each `0x14` fill
  with a `0x33` (~20% alpha) same-hue border — the borders are already at a
  meaningfully higher opacity than the fills, so bumping the fill closer to
  the border alpha is internally consistent with the existing visual system.
- The Potential variants use an animated pulsing orange border (lerping
  `#F97316`↔`#FB923C`, alpha 0.35–0.80) and a static `0x14F97316` fill. The
  animation and border stay untouched.
- `AppColors` in [design_tokens.dart](lib/app/theme/design_tokens.dart) does
  not currently define event-card tint tokens; the literals live inline. See
  Out of Scope for why we are not promoting these to tokens in this change.

## Proposed Solution

Change each of the four card-fill hex literals to a higher-alpha variant of
the same hue, preserving the RGB triplet and only raising the alpha byte:

| Card | File / line | Current | Proposed | Rationale |
|---|---|---|---|---|
| Potential Gig | `potential_gig_card.dart:315` | `0x14F97316` (~7.8%) | `0x33F97316` (~20.0%) | "Brighter orange" — 2.55× alpha bump; matches the `0x33` border-alpha convention already used on Confirmed cards, so the fill reads clearly as orange instead of a faint wash. Same-hue (orange-500), no border/animation change. |
| Potential Rehearsal | `rehearsal_card.dart:351` | `0x14F97316` (~7.8%) | `0x33F97316` (~20.0%) | Kept identical to Potential Gig — the two variants share visual language today and must continue to. |
| Confirmed Gig | `confirmed_gig_card.dart:58` | `0x1422C55E` (~7.8%) | `0x1F22C55E` (~12.2%) | "A little more opaque" — subtle +55% relative alpha bump on green-500, well below the `0x33` border so fill and border stay visually distinct. |
| Confirmed Rehearsal | `rehearsal_card.dart:600` | `0x140EA5E9` (~7.8%) | `0x1F0EA5E9` (~12.2%) | Same subtle bump on sky-500, matched to Confirmed Gig so the two "confirmed" surfaces remain visually consistent. |

Update the inline `// ~8% alpha` / `// tint background` comments on those
lines to reflect the new alpha percentages.

No borders, gradients, box shadows, animation controllers, or child widgets
change. No new files, tokens, providers, or dependencies.

## Database Impact

Not applicable — pure Flutter presentational change. No migrations, RLS
policies, RPC functions, triggers, or edge functions are touched.

## Flutter Architecture Changes

Not applicable — no new controllers, providers, repositories, models,
services, screens, or routes. No initialization order changes. No
platform-conditional code paths touched.

## Files to Create

None.

## Files to Modify

1. [lib/features/home/widgets/potential_gig_card.dart](lib/features/home/widgets/potential_gig_card.dart) —
   line 315: change the `AppCard.color` argument from `const Color(0x14F97316)`
   to `const Color(0x33F97316)` and update the trailing `// orange-500 tint
   background` comment to note the new ~20% alpha.

2. [lib/features/home/widgets/rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart) —
   two edits:
   - line 351 (`_buildPotentialCard`): change `const Color(0x14F97316)` to
     `const Color(0x33F97316)` and update its `// orange-500 tint background`
     comment to note ~20% alpha.
   - line 600 (`_buildConfirmedCard`): change `const Color(0x140EA5E9)` to
     `const Color(0x1F0EA5E9)` and update its `// sky-500 @ ~8% alpha
     background tint` comment to `// sky-500 @ ~12% alpha background tint`.

3. [lib/features/home/widgets/confirmed_gig_card.dart](lib/features/home/widgets/confirmed_gig_card.dart) —
   line 58: change `const Color(0x1422C55E)` to `const Color(0x1F22C55E)` and
   update its `// green-500 @ ~8% alpha background tint` comment to `// green-500
   @ ~12% alpha background tint`.

## Files Off-Limits

- [lib/features/gigs/widgets/availability_prompt_modal.dart](lib/features/gigs/widgets/availability_prompt_modal.dart) —
  contains `Color(0x14F97316)` at line 176, but this is a modal surface, not an
  event card on the Home dashboard. Out of scope per the Feature Input
  ("event card background color treatment").
- [lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart](lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart) —
  same reasoning; modal, not a card.
- [lib/features/calendar/widgets/calendar_event_card.dart](lib/features/calendar/widgets/calendar_event_card.dart) —
  Calendar-view card uses accent-dot color coding, not the Home tint system.
  Not requested and would be an opportunistic UI change.
- [lib/components/ui/app_card.dart](lib/components/ui/app_card.dart) — contains
  `Color(0x140EA5E9)` in a doc-comment example only (line 43); do not touch
  the doc comment.
- [lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart) — no
  new tokens in this change (see Out of Scope). Do not add
  `AppColors.gigCardFill` / `AppColors.rehearsalCardFill` /
  `AppColors.potentialCardFill` here.
- Everything else in the repo.

## Change Budget

- Expected net line delta per modified file:
  - `potential_gig_card.dart`: 0 (one literal + inline comment swap on the
    same line).
  - `rehearsal_card.dart`: 0 (two literal + comment swaps on their existing
    lines).
  - `confirmed_gig_card.dart`: 0 (one literal + inline comment swap on the
    same line).
- Expected new files: 0.
- Expected new public classes/methods/tokens: 0.
- Expected new dependencies: 0.
- Expected new test files: 0.

QA measures the actual diff against these numbers; a net change greater than
±2 lines total across the three files, or any new file/token/dependency,
should be flagged.

## System Impact Map

- Home dashboard visual layer: **affected** (four card fills).
- Gigs feature (create/edit flow, response repository, modal UIs): **unaffected**.
- Rehearsals feature (create/edit flow, response repository, modal UIs): **unaffected**.
- Setlists: **unaffected**.
- Members: **unaffected**.
- Auth (PKCE, magic link, deep links, session): **unaffected**.
- Routing / navigation: **unaffected**.
- Notifications (Firebase Messaging, band-member notify triggers): **unaffected**.
- Calendar tab / event card there: **unaffected**.
- Supabase (schema, RLS, RPCs, edge functions, triggers): **unaffected**.
- Platforms — iOS / Android / macOS / Web: **all affected identically**; the
  `Color(0x...)` literal renders the same on every Flutter platform, and no
  platform-conditional code is touched. Firebase init and `DeepLinkService`
  remain native-only as today.
- Init order: **unaffected**.

## Regression Risk: LOW

- Change is confined to four `Color` literal values on `AppCard.color`.
- No auth, session, routing, init-order, or database code is touched.
- No new widgets, providers, or dependencies.
- Both Potential card variants continue to share identical fill (verified by
  proposing the same target value), so the Home visual grouping between them
  is preserved.
- Text contrast for white foreground on the two new backgrounds:
  - Potential fill `0x33F97316` over `#09090B`–`#18181B` background gradient
    produces an effective composite around `#3B2416`–`#463122`, still
    comfortably below the L* range where white body copy loses AA contrast;
    the chip label (dark text on cream) is unchanged.
  - Confirmed fills at `0x1F` alpha shift the composite by only a few L*
    steps versus current, well within the safe zone.

The only category of regression to watch is any golden-image tests keyed to
the exact pixel values of these cards; see Verification Plan.

## Engineer Task Breakdown

1. In `lib/features/home/widgets/potential_gig_card.dart`, on the
   `AppCard.color` argument (single line, currently
   `color: const Color(0x14F97316), // orange-500 tint background`), replace
   the color literal with `const Color(0x33F97316)` and update the trailing
   comment to `// orange-500 @ ~20% alpha background tint`.

2. In `lib/features/home/widgets/rehearsal_card.dart` inside
   `_buildPotentialCard`, on the analogous
   `color: const Color(0x14F97316), // orange-500 tint background` line,
   apply the same swap to `const Color(0x33F97316)` and update the trailing
   comment to `// orange-500 @ ~20% alpha background tint`.

3. In the same file, inside `_buildConfirmedCard`, change
   `color: const Color(0x140EA5E9), // sky-500 @ ~8% alpha background tint`
   to `color: const Color(0x1F0EA5E9), // sky-500 @ ~12% alpha background tint`.

4. In `lib/features/home/widgets/confirmed_gig_card.dart`, change
   `color: const Color(0x1422C55E), // green-500 @ ~8% alpha background tint`
   to `color: const Color(0x1F22C55E), // green-500 @ ~12% alpha background tint`.

5. Do not touch borders, box shadows, gradients, animation controllers,
   comments outside those four lines, or any other file.

## Verification Plan

### Tier 1 — pre-deploy, mechanical (QA-executable)

Every check below runs without a live app instance.

1. **Static analysis passes:** `flutter analyze` returns zero new warnings
   or errors versus `main`. The change is four hex literals plus four
   comments — analyzer output should be byte-identical to `main` aside from
   any pre-existing noise, which QA compares against the baseline.

2. **Existing widget-test suite still passes:** `flutter test` completes
   with the same pass count as `main`. In particular,
   `test/features/home/widgets/dashboard_no_setlist_badge_test.dart`
   constructs `PotentialGigCard`, `RehearsalCard` (both variants), and
   `ConfirmedGigCard` under real widget trees; any accidental structural
   regression to those cards would surface here.

3. **Grep verification of the four target sites** (run from repo root):
   ```
   rg -n 'Color\(0x14F97316\)|Color\(0x1422C55E\)|Color\(0x140EA5E9\)' lib/features/home/widgets/
   ```
   Expected result: **zero matches**. All four old fill literals must be
   gone from `lib/features/home/widgets/`.

4. **Grep verification that the four new literals are present exactly
   where expected:**
   ```
   rg -n 'Color\(0x33F97316\)|Color\(0x1F22C55E\)|Color\(0x1F0EA5E9\)' lib/features/home/widgets/
   ```
   Expected result: exactly three lines in `rehearsal_card.dart` and
   `potential_gig_card.dart` for `0x33F97316` (two hits total — one per
   file), one line in `confirmed_gig_card.dart` for `0x1F22C55E`, and one
   line in `rehearsal_card.dart` for `0x1F0EA5E9`.

5. **Grep verification that off-limits files are untouched:**
   ```
   rg -n 'Color\(0x14F97316\)' lib/features/gigs/widgets/availability_prompt_modal.dart lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart
   rg -n 'Color\(0x140EA5E9\)' lib/components/ui/app_card.dart
   ```
   Both must still match — the modal `0x14F97316` fills and the
   `app_card.dart` doc-comment example must remain unchanged.

6. **Diff size check** against Change Budget: `git diff --stat main...HEAD`
   should show only the three files in Files to Modify, with total
   `insertions + deletions ≤ 8` (four literal-swap lines, each counted as
   one delete + one insert in a git diff = 8 line-changes max). Any
   additional file in the diff, or a larger delta on the three named
   files, is a violation of the plan.

### Tier 2 — post-deploy

Not applicable — no server-side surface (RPC, edge function, migration)
changes.

### Owner-run visual check (Tony, at PR-test time — NOT a QA gate)

Because QA cannot launch a running app instance in this pipeline, the
visual outcome must be confirmed by Tony against a running build. Hand
this exact punch list to Tony verbatim:

1. Run `flutter run -d macos` (or `flutter run -d chrome`) on the
   `feature/event-card-background-colors` branch.
2. Sign in with an active band that has:
   - at least one **potential gig** on the Home dashboard, and
   - at least one **potential rehearsal** on the Home dashboard, and
   - at least one **confirmed (upcoming) gig** on the Home dashboard, and
   - at least one **confirmed (upcoming) rehearsal** on the Home dashboard.
3. On the Home tab, scroll to the horizontal event-card rail.
   **Expected:** the Potential Gig card and Potential Rehearsal card both
   show a visibly brighter, more saturated orange fill than on `main` —
   the orange should read as "clearly orange" rather than "hint of
   orange," while the animated border pulse and the cream chip label
   remain unchanged.
4. Still on the Home tab, look at the Confirmed Gig card.
   **Expected:** the green fill is slightly more present than on `main`
   — a subtle bump, not a dramatic one; text, border, and no-setlist
   chip remain unchanged.
5. Look at the Confirmed Rehearsal card.
   **Expected:** the sky-blue fill is slightly more present than on
   `main` — same subtle bump as the Confirmed Gig; setlist chip and
   border unchanged.
6. Confirm on at least one other platform (iOS simulator, Android
   emulator, or web build) that the colors render identically, since
   the change is a single hex literal per site with no
   platform-conditional path.

## QA Regression Areas

- `test/features/home/widgets/dashboard_no_setlist_badge_test.dart` —
  primary target; verifies the three card widgets still build and
  layout the "No Setlist" badge as before.
- `test/features/home/widgets/quick_actions_row_test.dart` — sibling
  Home test, should be unaffected but confirms the Home widgets
  compile cleanly together.
- Full `flutter test` suite as a smoke — any golden test elsewhere
  that transitively snapshots one of the three card widgets would
  need re-baselining; there are no such golden tests today per the
  test-directory search, but QA should re-run the full suite to
  confirm.

## Rollout Strategy

Standard PR → main flow. No feature flag, staged rollout, or migration
gate. Cache-busting is a non-issue — the change ships as part of the
Flutter binary/web bundle on the next release. No client-side or
server-side data has to be reconciled. Rollback is a single-commit
revert.

## Out of Scope

- **Promoting the four fill values to `AppColors` tokens
  (`AppColors.potentialCardFill` / `AppColors.confirmedGigCardFill` /
  `AppColors.confirmedRehearsalCardFill`).** This would be a genuine
  design-tokens improvement, but it is an opportunistic refactor,
  touches `design_tokens.dart` (used across the app), and adds public
  API. The Feature Input explicitly says "Preserve the existing event
  card design and change only the requested background color
  treatment." Deferred to a follow-up hygiene task.
- **Any color change to the availability-prompt modals**
  (`availability_prompt_modal.dart`,
  `rehearsal_availability_prompt_modal.dart`) — modals are not event
  cards.
- **Calendar-view event card** — accent-dot color coding is a
  separate visual system; not requested.
- **Border, gradient, box-shadow, or animation tuning** on any of the
  four cards.
- **Text-contrast retuning** — foreground colors remain white / cream
  as today; contrast stays within the AA range at the new alpha
  values (see Regression Risk).
- **Dark/light theming** — app is dark-mode-only; no light-mode
  variant is being introduced.
