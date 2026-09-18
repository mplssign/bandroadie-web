# ARCHITECT_PLAN.md

## Feature Slug
animation-interaction-consistency-pass

## Feature Title
Extend existing press-feedback and page-transition animations to remaining tap targets

## Problem Summary
`lib/app/theme/app_animations.dart` defines the app's motion system
(`AnimatedPressable`, `AnimatedCardPressable`, `fadeSlideRoute`,
`fadeSlideUpRoute`, `AppDurations`/`AppCurves`). It is applied consistently
across most of setlists, home, and contacts, but a smaller set of tappable
rows/cards still use a bare `GestureDetector`/`InkWell` with zero press
feedback, and a handful of `Navigator.push` calls use a raw
`MaterialPageRoute` instead of the shared route builders. This creates a
visibly abrupt interaction next to the rest of the app.

## Root Cause (Confidence: HIGH — confirmed in code)
Two independent gaps, both confirmed by direct code inspection (not just
grep hits):

1. **No press feedback at all.** Several widgets wrap their tappable content
   in a plain `GestureDetector`/`InkWell` with no visual response on
   press — confirmed in `notification_card.dart`, `member_card.dart`
   (contact row), the duplicated `_DetailRow` widget (4 files),
   `venue_detail_screen.dart` (`_buildFieldEntry`), `special_item_card.dart`
   (both variants), and `settings_screen.dart` (`_SettingsListItem`).
2. **Raw `MaterialPageRoute` pushes.** Several `Navigator.push` calls build
   a `MaterialPageRoute` directly instead of `fadeSlideRoute`, confirmed in
   `financials_screen.dart`, `settings_screen.dart` (x2),
   `home_tab_content.dart`, `print_options_bottom_sheet.dart`, and
   `app_shell.dart` (x4). `lyrics_view_screen.dart` doesn't use
   `MaterialPageRoute`, but hand-rolls a `PageRouteBuilder` that duplicates
   `fadeSlideUpRoute`'s exact fade+slide-up effect (same offset, same
   `AppDurations.medium`/`AppCurves.ease` tokens) instead of calling it.

**Important discrepancy vs. the ticket's starting-point grep list** (per
Architect process step 2 — trust the code): `calendar_event_card.dart`,
`confirmed_gig_card.dart`, `pending_invite_card.dart`, and
`reorderable_band_member_card.dart` were flagged as gaps, but on inspection
**each already has working press feedback** — a hand-rolled
`AnimationController` + `Transform.scale` (two of them also dim opacity),
predating the extraction of `AnimatedCardPressable`. This is the exact same
established pattern used by `song_card.dart`, `reorderable_song_card.dart`,
`setlist_card.dart`, `rehearsal_card.dart`, and `potential_gig_card.dart` —
i.e. it's a second, widespread, already-consistent convention for
list/reorderable cards, not a missing-feedback bug. Rewriting these to
literally call `AnimatedCardPressable` would be a pure style refactor of
already-correct, already-animated code with no user-facing difference (and
a minor regression for the two that currently also dim opacity, since
`AnimatedCardPressable` doesn't support that). Guardrails forbid
opportunistic refactors of working code, and the ticket only asks that
tap targets have *some* consistent press feedback, not that every card use
one specific class. These four files are therefore **out of scope** — see
Out of Scope section.

## Existing System Analysis
- `AnimatedPressable` (button-style, scale 0.96) and `AnimatedCardPressable`
  (card-style, scale 0.98) both live in `lib/app/theme/app_animations.dart`
  and take `onTap`/`enabled`, matching the existing call signatures of the
  bare `GestureDetector`/`InkWell` usages being replaced.
- `fadeSlideRoute`/`fadeSlideUpRoute` are already used correctly for the
  large majority of in-app navigation (setlists, invite flow, band
  switcher, role management, contact/gig/rehearsal detail pushes) — this is
  a conformance mop-up, not new design.
- A private `_DetailRow` widget (label + value row with optional chevron)
  is duplicated verbatim across `contact_detail_drawer.dart`,
  `band_member_detail_drawer.dart`, `view_gig_drawer.dart`, and
  `view_rehearsal_drawer.dart`. All four wrap the row in a plain `InkWell`
  when `onTap != null`. Only the first was in the ticket's starting list;
  the other three were found via the required broader audit and share the
  identical gap, so they're included for consistency.
- `settings_screen.dart`'s `_SettingsListItem` (used for every row in the
  Settings screen, including the two flagged route pushes) uses
  `Material` + `InkWell` with no scale feedback.

## Proposed Solution
Two independent, mechanical fixes applied only to confirmed genuine gaps:

**A. Wrap real tap targets that currently have zero press feedback:**
- Whole-card/row taps → `AnimatedCardPressable`.
- Inline text/field taps (phone, email, address, a settings row, a detail
  row) → `AnimatedPressable`.

**B. Replace raw route construction with the shared builders:**
- `MaterialPageRoute(...)` → `fadeSlideRoute(page: ...)` for standard pushes.
- The hand-rolled `PageRouteBuilder` in `lyrics_view_screen.dart` →
  `fadeSlideUpRoute(page: ...)` (verified identical curve/duration/offset,
  so this is a pure de-duplication, zero visual change).

No new curves, durations, scale values, or widgets are introduced. No
state/business logic changes.

## Database Impact
Not applicable — pure Flutter UI change, no Supabase interaction.

## Flutter Architecture Changes
None. No new providers/controllers/repositories. Each change either wraps
an existing `child` in an existing animation widget, or swaps one route
constructor call for another. Unidirectional data flow, disposal, and
async-lifecycle guardrails are unaffected since no new controllers/state
are introduced (`AnimatedPressable`/`AnimatedCardPressable` manage their
own internal state and disposal).

## Files to Create
None.

## Files to Modify

### A. Press-feedback wrapping
1. `lib/features/notifications/widgets/notification_card.dart` — wrap the
   `Container` (currently a bare `GestureDetector`) in `AnimatedCardPressable`;
   move the existing `onTap` logic (mark-as-read + callback) into its `onTap`.
2. `lib/features/members/widgets/member_card.dart` — wrap the
   `_buildContactRow` `GestureDetector` (phone/email row) in
   `AnimatedPressable`, preserving `HitTestBehavior.opaque` sizing via the
   existing `Expanded`.
3. `lib/features/contacts/widgets/contact_detail_drawer.dart` — replace the
   `_DetailRow`'s `InkWell` with `AnimatedPressable`.
4. `lib/features/contacts/widgets/band_member_detail_drawer.dart` — same
   `_DetailRow` fix (found via audit, identical duplicate of #3).
5. `lib/features/gigs/widgets/view_gig_drawer.dart` — same `_DetailRow` fix
   only (its two existing `fadeSlideRoute` pushes already conform, do not
   touch).
6. `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart` — same
   `_DetailRow` fix only (its existing `fadeSlideRoute` push already
   conforms, do not touch).
7. `lib/features/contacts/widgets/venue_detail_screen.dart` —
   `_buildFieldEntry`'s `GestureDetector` → `AnimatedPressable`.
8. `lib/features/setlists/widgets/special_item_card.dart` — both
   `_buildSetBreakCard` and `_buildPauseCard` `GestureDetector`s →
   `AnimatedCardPressable`.
9. `lib/features/settings/settings_screen.dart` — `_SettingsListItem`'s
   `Material`/`InkWell` → `AnimatedPressable` (drop the now-unnecessary
   `Material` wrapper).

### B. Route builder conformance
9. `lib/features/settings/settings_screen.dart` — `_openNotifications` and
   `_openOneCalendar`: `MaterialPageRoute` → `fadeSlideRoute`. (Same file as
   above; one edit pass.)
10. `lib/features/financials/financials_screen.dart` — `_openCombinedReport`:
    `MaterialPageRoute` → `fadeSlideRoute`.
11. `lib/features/home/home_tab_content.dart` — `_handleOpenFinancials`
    (found via audit, not in original list): `MaterialPageRoute` →
    `fadeSlideRoute`.
12. `lib/features/setlists/widgets/print_options_bottom_sheet.dart` —
    `_handlePreview` (found via audit — same class of PDF-preview push as
    the financials one): `MaterialPageRoute` → `fadeSlideRoute`.
13. `lib/features/shell/app_shell.dart` — the 4 side-drawer pushes
    (`MyProfileScreen`, `SettingsScreen`, `TipsAndTricksScreen`,
    `BugReportScreen`, found via audit): `MaterialPageRoute` →
    `fadeSlideRoute`.
14. `lib/features/lyrics/widgets/lyrics_view_screen.dart` — replace the
    hand-rolled `PageRouteBuilder` with `fadeSlideUpRoute(page: ...)`.

Files needing a new `import 'package:bandroadie/app/theme/app_animations.dart';`
(not already imported): `notification_card.dart`, `member_card.dart`,
`contact_detail_drawer.dart`, `band_member_detail_drawer.dart`,
`special_item_card.dart`, `settings_screen.dart`, `financials_screen.dart`,
`print_options_bottom_sheet.dart`. Already imported (no new import needed):
`view_gig_drawer.dart`, `view_rehearsal_drawer.dart`,
`venue_detail_screen.dart`, `home_tab_content.dart`, `app_shell.dart`.
`lyrics_view_screen.dart` needs the import added; its existing
`design_tokens.dart` import stays (other tokens are still used elsewhere in
the file) even though `AppDurations`/`AppCurves` become unused in the
replaced block — check for and remove only truly-dead imports, not
tokens still used elsewhere in the same file.

## Files Off-Limits
- `lib/features/calendar/widgets/calendar_event_card.dart`,
  `lib/features/home/widgets/confirmed_gig_card.dart`,
  `lib/features/members/widgets/pending_invite_card.dart`,
  `lib/features/contacts/widgets/reorderable_band_member_card.dart` — already
  have working hand-rolled press feedback (see Root Cause discrepancy
  above); not a gap, do not touch.
- `lib/features/setlists/widgets/song_card.dart`,
  `lib/features/setlists/widgets/reorderable_song_card.dart`,
  `lib/features/setlists/widgets/setlist_card.dart`,
  `lib/features/home/widgets/rehearsal_card.dart`,
  `lib/features/home/widgets/potential_gig_card.dart`,
  `lib/features/home/widgets/load_more_rehearsals_card.dart` — same
  established hand-rolled press-feedback convention; out of scope, not
  flagged, and far higher blast radius than this ticket calls for.
- `lib/features/auth/auth_confirm_screen.dart`,
  `lib/features/auth/invite_screen.dart` — use
  `Navigator.pushAndRemoveUntil(..., MaterialPageRoute(...), (route) => false)`
  to reset the entire nav stack after auth (into `AuthGate`/`InviteScreen`).
  This is a full-stack replacement at a security-sensitive boundary, not a
  standard push with a "previous screen" to slide from — platform-default
  is the deliberate, correct choice here. Do not touch.
- Every other `GestureDetector`/`InkWell` found in the broader audit
  (form fields, app bars, segmented toggles/pickers, drag handles,
  bottom-sheet option chips, currency/duration inputs, the A–Z index/search
  columns, `AppCard`'s own internal `onTap` passthrough, etc.) — these are
  structural, form-control, or already-appropriately-animated (e.g. label
  color/position transitions) and are not primary card/row/icon tap
  targets. Not modified, per the "No AI-Generated Bloat" guardrail
  (`GUARDRAILS.md` §7a) — wrapping these would add motion to things this
  ticket isn't about.
- No migrations, edge functions, or new dependencies.

## Change Budget
- Expected new files: 0
- Expected new public classes/methods: 0
- Expected new dependencies: 0
- Net line delta per file (approximate, mostly wrapper add/swap, some
  negative from deleted boilerplate):
  - `notification_card.dart`: +5
  - `member_card.dart`: +4
  - `contact_detail_drawer.dart`: +3
  - `band_member_detail_drawer.dart`: +3
  - `view_gig_drawer.dart`: +2
  - `view_rehearsal_drawer.dart`: +2
  - `venue_detail_screen.dart`: +3
  - `special_item_card.dart`: +6
  - `settings_screen.dart`: +6 (InkWell→AnimatedPressable swap + 2 route fixes)
  - `financials_screen.dart`: +1
  - `home_tab_content.dart`: +1
  - `print_options_bottom_sheet.dart`: +1
  - `app_shell.dart`: -4 (four `fadeSlideRoute(page: ...)` one-liners replace
    four multi-line `MaterialPageRoute` blocks)
  - `lyrics_view_screen.dart`: -14 (custom `PageRouteBuilder` collapses to a
    single `fadeSlideUpRoute` call)

## System Impact Map
- Gigs: affected (financials PDF preview, view gig drawer detail row) — visual only
- Rehearsals: affected (view rehearsal drawer detail row) — visual only
- Setlists: affected (special item card, print preview push) — visual only
- Members: affected (member card, band member detail drawer) — visual only
- Contacts: affected (contact detail drawer, venue detail screen) — visual only
- Auth: unaffected (explicitly left alone, see Files Off-Limits)
- Routing: affected, but only transition animation, not navigation logic/order
- Notifications: affected (notification card) — visual only
- Platforms: all (iOS/Android/macOS/Web) — no platform-conditional code touched

## Regression Risk: LOW
Every change is either (a) wrapping existing `child`/`onTap` in an existing,
already-battle-tested animation widget with the same callback signature, or
(b) swapping one route-builder call for another with an equivalent
signature (`page:` vs `builder:`). No state, provider, repository, RLS, or
initialization-order changes. No existing test exercises `InkWell`/
`GestureDetector`/`MaterialPageRoute` by type on any of the touched widgets
(confirmed via search of `test/`), so no test breakage is expected from the
widget-tree changes.

## Engineer Task Breakdown
1. `notification_card.dart`: wrap in `AnimatedCardPressable`.
2. `member_card.dart`: wrap `_buildContactRow`'s `GestureDetector` in
   `AnimatedPressable`.
3. `contact_detail_drawer.dart`: `_DetailRow`'s `InkWell` →
   `AnimatedPressable`.
4. `band_member_detail_drawer.dart`: same `_DetailRow` fix.
5. `view_gig_drawer.dart`: same `_DetailRow` fix.
6. `view_rehearsal_drawer.dart`: same `_DetailRow` fix.
7. `venue_detail_screen.dart`: `_buildFieldEntry`'s `GestureDetector` →
   `AnimatedPressable`.
8. `special_item_card.dart`: both card builders' `GestureDetector` →
   `AnimatedCardPressable`.
9. `settings_screen.dart`: `_SettingsListItem`'s `Material`/`InkWell` →
   `AnimatedPressable`; `_openNotifications`/`_openOneCalendar` →
   `fadeSlideRoute`.
10. `financials_screen.dart`: `_openCombinedReport` → `fadeSlideRoute`.
11. `home_tab_content.dart`: `_handleOpenFinancials` → `fadeSlideRoute`.
12. `print_options_bottom_sheet.dart`: `_handlePreview` → `fadeSlideRoute`.
13. `app_shell.dart`: 4 side-drawer pushes → `fadeSlideRoute`.
14. `lyrics_view_screen.dart`: hand-rolled `PageRouteBuilder` →
    `fadeSlideUpRoute`.

Tasks are independent and can be implemented/verified in any order; listed
roughly in file-group order for review convenience.

## Verification Plan
**Tier 1 (pre-deploy, static/headless — QA's actual gate):**
- `flutter analyze` on all 14 changed files — 0 new errors/warnings
  (specifically: no unused-import/unused-field warnings left behind after
  removing `Material`/hand-rolled `AnimationController` code where
  applicable).
- `flutter test` — full existing suite passes unchanged. In particular,
  re-run `test/features/financials/widgets/financials_screen_scroll_test.dart`,
  `summary_header_test.dart`, and `transaction_card_test.dart` since they
  pump `FinancialsScreen` directly; confirm no widget-tree assumptions
  break.
- Manual diff read: confirm every touched `GestureDetector`/`InkWell`/
  `MaterialPageRoute` was swapped 1:1 for the matching animation widget/
  route builder with no callback signature drift, and no import lingers
  unused.

**Tier 2 (owner-run, requires a running app — Tony's punch list at PR-test time):**
1. Open the notifications feed → tap an unread notification → expect a
   scale-down/up press animation and the item marking as read.
2. Open a member's contact info → tap a phone or email row → expect a
   scale-down/up press animation before the dialer/mail app opens.
3. Open a contact or band member detail drawer → tap a detail row with a
   chevron (e.g. Setlist, Notes) → expect a scale animation before the
   destination opens with a fade+slide transition.
4. Open a venue detail screen → tap the address field → expect a scale
   animation before the maps app opens.
5. Open a setlist with a Set Break and a Pause item → tap each → expect a
   scale animation before the editor opens.
6. Open Settings → tap any row → expect a scale animation; specifically tap
   Notification Settings and One Calendar Settings → expect a fade+slide
   page transition (not an instant/platform-default cut).
7. Open Financials → generate the combined PDF report → expect a
   fade+slide transition into the preview screen.
8. From the home screen Quick Actions, open Financials → expect a
   fade+slide transition.
9. From a setlist, open Print Options → Preview → expect a fade+slide
   transition into the PDF preview.
10. From the side drawer, open My Profile, Settings, Tips & Tricks, and
    Report a Bug → each should fade+slide in, not appear instantly.
11. Open a song's lyrics view → expect the same fade+slide-up transition as
    before (this should look identical to pre-change behavior, since the
    tokens are unchanged — it's confirming the de-duplication didn't alter
    the visual).

## QA Regression Areas
- Financials screen (PDF preview push + existing scroll/summary/transaction
  widget tests).
- Settings screen (list item rendering + the two sub-screen pushes).
- Side drawer navigation (4 pushes in `app_shell.dart`).
- Contact/band-member/gig/rehearsal detail drawers (shared `_DetailRow`
  pattern, 4 files).
- Lyrics viewer page transition (visual parity check only, no functional
  change expected).

## Rollout Strategy
Standard PR merge via the pipeline. No feature flag, no migration, no
staged rollout — this is a client-only visual conformance change shipped in
the next app build.

## Out of Scope
- Converting `calendar_event_card.dart`, `confirmed_gig_card.dart`,
  `pending_invite_card.dart`, `reorderable_band_member_card.dart`,
  `song_card.dart`, `reorderable_song_card.dart`, `setlist_card.dart`,
  `rehearsal_card.dart`, `potential_gig_card.dart`, or
  `load_more_rehearsals_card.dart` to literally call `AnimatedCardPressable`/
  `AnimatedPressable` — they already have equivalent working press feedback
  via an established hand-rolled pattern; this would be a pure style
  refactor with no user-facing benefit and added regression risk.
- Changing the auth-flow full-stack-reset navigation
  (`auth_confirm_screen.dart`, `invite_screen.dart`) to use
  `fadeSlideRoute`/`fadeSlideUpRoute` — deliberately platform-default.
- Any new animation curve, duration, or scale value — this task reuses the
  existing `AppDurations`/`AppCurves`/`AnimScales` tokens exclusively.
- Wrapping form fields, app bars, pickers, toggles, or other structural
  `GestureDetector`/`InkWell` usages found during the audit that aren't
  primary user-facing tap targets.
