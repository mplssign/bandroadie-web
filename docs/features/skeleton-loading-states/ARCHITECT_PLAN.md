# ARCHITECT PLAN

**Feature Slug:** `feature/skeleton-loading-states`
**Feature Title:** Add skeleton loaders for the app's highest-traffic first-load screens

---

## Problem Summary

`lib/features/members/widgets/member_card_skeleton.dart` is the only skeleton-loader
pattern in the codebase today (used from `members_tab_content.dart` and
`band_members_view.dart`). Everywhere else, initial data loads fall back to a bare
centered `CircularProgressIndicator`, which reads as a dead screen rather than
content that's about to appear. The two highest-traffic first-load screens where
this hurts most are:

- **Home dashboard** (`lib/features/home/home_tab_content.dart`, ~line 621 / 634):
  during gig/rehearsal load, the whole viewport shows `_buildLoadingState('Setting
  up the stage...')` — a centered pulsing circle with a caption.
- **Financials screen** (`lib/features/financials/financials_screen.dart`,
  ~line 170): during initial entry load, the list area shows
  `Center(child: CircularProgressIndicator(color: AppColors.primary))`.

Feature ask: swap those two spinners for shimmer-shaped skeleton placeholders in
the same style as `MemberCardSkeleton`, so the user sees a preview of the content
that's coming. Explicitly out of scope: every other `CircularProgressIndicator` in
the app (button/inline spinners in `AnimatedLoadingButton`, one-time auth/shell
gates in `auth_gate.dart` / `app_shell.dart` / `no_band_shell.dart`, in-modal
sub-section spinners, etc.).

---

## Root Cause

**Confidence: HIGH — confirmed in code.**

Not a bug. This is a UX gap: the codebase has an existing shimmer skeleton pattern
(`MemberCardSkeleton`) but only one screen uses it. The two highest-traffic
first-load screens still fall back to a plain centered spinner because no
skeleton widgets exist yet for their card shapes.

Concretely:

- `home_tab_content.dart` line 634 calls
  `_buildLoadingState('Setting up the stage...')` for the branch
  `gigState.isLoading || rehearsalState.isLoading || dataIsStale`.
- `financials_screen.dart` line 168-173 renders
  `Center(child: CircularProgressIndicator(color: AppColors.primary))` for
  `state.isLoading` inside the list column.

The fix: create three new atomic skeleton widgets that shimmer in the shape of
their target cards, and compose them into the loading branches of those two
screens.

---

## Existing System Analysis

**Reference pattern (`member_card_skeleton.dart`, ~170 lines):**

- Stateful widget owning a single `AnimationController` (1500 ms, `.repeat()`).
- Builds an `AnimatedBuilder` that renders `AppCard` filled with shimmer
  boxes/pills/rows using a moving `LinearGradient`
  (`context.colors.surface → surfaceOverlay → surface`).
- Consumed from `members_tab_content.dart._buildLoadingState()` as
  `ListView.builder` of 3 skeletons inside `Spacing.pagePadding`.

**Home dashboard loading states (`home_tab_content.dart` line 617–636):**

```dart
if (bandState.isLoading) {
  stateKey = 'loading-bands';
  stateWidget = _buildLoadingState('Setting up the stage...');   // keep as-is
} else if (bandState.error != null) { ... }
else if (!bandState.hasBands) { ... }
else if (gigState.isLoading || rehearsalState.isLoading || dataIsStale) {
  stateKey = 'loading-gigs';
  stateWidget = _buildLoadingState('Setting up the stage...');   // ← swap this
} else if (...) { ... }
```

Two branches call the same helper. **Only the `loading-gigs` branch is in
scope.** The `loading-bands` branch is a one-time auth/shell gate (per Feature
Input) and must be preserved verbatim.

Content-shape reference for the skeleton composition:

- Confirmed rehearsals: horizontal `ListView.separated` inside
  `SizedBox(height: Spacing.rehearsalCardHeight = 160)`; `RehearsalCard` is
  ~350×160 (`Spacing.rehearsalCardWidth`).
- Confirmed gigs: `SingleChildScrollView` of `Row(children: [ConfirmedGigCard,
  ...])`; `ConfirmedGigCard` is a fixed-width card (~271×126 per its Figma
  comment) sized by its own constraints.
- Potential events: horizontal `ListView.separated` inside `SizedBox(height:
  Spacing.potentialGigCardHeight = 240)`. Excluded from the skeleton because
  most bands have no potential events at any given moment and the section
  only renders when non-empty (`if (gigState.potentialGigs.isNotEmpty || ...)`).
  Skeletonizing an empty section would create false-positive UI.
- Section headers use `SectionHeader(title: ..., topSpacing: Spacing.space24)`.

**Financials loading state (`financials_screen.dart` line 165–173):**

```dart
Expanded(
  child: state.isLoading
      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
      : filtered.isEmpty
          ? const _EmptyState()
          : ListView.separated( /* filtered transaction cards */ ),
),
```

The loading state sits inside a `Column` that already renders the header
(`_ViewModeToggle`, `_SummaryHeader`). Swap the `Center(...)` for a
`ListView.separated` of `TransactionCardSkeleton` widgets using the same
padding and separator as the real list, so the chrome around the list doesn't
shift when data resolves.

**`_TransactionCard` shape (financials_screen.dart line 766):**
`Container` with `context.colors.surface`, `border`, `borderRadius:
Spacing.cardRadius`, padded `Spacing.space16`; three rows:

1. Title (bold callout) + amount (bold, right-aligned).
2. Category (footnote) + trailing chevron icon.
3. Date (footnote) + optional outlined badge (24×~18).

Row heights are stable regardless of badge presence (`Colors.transparent`
fallback). The skeleton mirrors this exactly so the transition is
seamless.

---

## Proposed Solution

Add three atomic skeleton widgets in the existing `widgets/` folders next to
their card counterparts, and compose them into the two target loading branches.

Widgets follow `MemberCardSkeleton`'s pattern exactly: `StatefulWidget` +
`SingleTickerProviderStateMixin` + one 1500 ms repeating
`AnimationController` driving a `LinearGradient(context.colors.surface →
surfaceOverlay → surface)`. Same private helpers (`_buildShimmerBox`, etc.).
No shared base class — deliberately choosing local duplication over a new
abstraction, matching the reference file's own decision.

The screen-level changes are two-line-ish:

1. `home_tab_content.dart`: add `_buildLoadingSkeleton()`; change the
   `'loading-gigs'` branch's `stateWidget` from
   `_buildLoadingState('Setting up the stage...')` to
   `_buildLoadingSkeleton()`. Leave the `'loading-bands'` branch and the
   `_buildLoadingState(String message)` method untouched.
2. `financials_screen.dart`: replace the inline
   `Center(child: CircularProgressIndicator(...))` with a `ListView.separated`
   of `TransactionCardSkeleton` widgets that mirrors the padding and separator
   of the real list two branches below it.

The `AnimatedSwitcher` already wrapping the home dashboard's `stateWidget`
continues to handle the skeleton → content transition; no changes to
animation infrastructure needed.

---

## Database Impact

Not applicable. Pure UI — no migrations, no RPCs, no RLS policies, no
schema changes.

---

## Flutter Architecture Changes

- Three new stateful widgets (each ~90 lines), each using one
  `AnimationController` for shimmer. No new providers, no new
  controllers, no new repositories, no new navigation routes, no new
  dependencies.
- No touch to init order, auth flow, Supabase client, or platform-
  conditional code. Skeletons are pure Flutter widgets and behave
  identically on iOS, Android, macOS, and web.
- The `_buildLoadingState(String message)` method in
  `home_tab_content.dart` is preserved verbatim — the `bandState.isLoading`
  branch (auth/shell gate scope) continues to use it.

---

## Files to Create

| File | Purpose |
|------|---------|
| `lib/features/home/widgets/gig_card_skeleton.dart` | Shimmer skeleton matching `ConfirmedGigCard` shape (~271×126, `Spacing.buttonRadius`). |
| `lib/features/home/widgets/rehearsal_card_skeleton.dart` | Shimmer skeleton matching confirmed-variant `RehearsalCard` shape (~`rehearsalCardWidth` × `rehearsalCardHeight`). |
| `lib/features/financials/widgets/transaction_card_skeleton.dart` | Shimmer skeleton matching `_TransactionCard` shape (3 rows, `cardRadius`). |
| `test/features/home/widgets/home_dashboard_skeletons_test.dart` | Smoke tests for `GigCardSkeleton` + `RehearsalCardSkeleton`. |
| `test/features/financials/widgets/transaction_card_skeleton_test.dart` | Smoke test for `TransactionCardSkeleton`. |

New public classes: `GigCardSkeleton`, `RehearsalCardSkeleton`,
`TransactionCardSkeleton` (each a `StatefulWidget` with a `const` constructor
taking only `super.key`).

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/features/home/home_tab_content.dart` | Add `_buildLoadingSkeleton()` method (returns a `CustomScrollView` with an app-bar-height spacer, "Upcoming Rehearsals" `SectionHeader` + horizontal list of 2 `RehearsalCardSkeleton`, "Upcoming Gigs" `SectionHeader` + `GigCardSkeleton`). Change the single `stateWidget = _buildLoadingState(...)` on the `'loading-gigs'` branch (~line 634) to `stateWidget = _buildLoadingSkeleton()`. Add imports for the two new skeleton widgets. **Leave line 621 (`'loading-bands'` branch) and the `_buildLoadingState(String message)` method (~line 710) untouched.** |
| `lib/features/financials/financials_screen.dart` | Replace the `Center(child: CircularProgressIndicator(color: AppColors.primary))` at ~line 170 with a `ListView.separated` of ~5 `TransactionCardSkeleton` widgets using the same `padding` and `separatorBuilder` (`SizedBox(height: Spacing.space12)`) as the real entries list at line 176. Add import for `TransactionCardSkeleton`. |

---

## Files Off-Limits

Every file below is explicitly out of scope for this branch. Any change
outside the modify list is a scope violation.

- `lib/features/auth/auth_gate.dart` — one-time auth gate spinner (Feature Input).
- `lib/features/shell/app_shell.dart`, `no_band_shell.dart` — one-time shell gate
  spinners (Feature Input).
- `lib/components/ui/app_button.dart`, `AnimatedLoadingButton` — inline button
  spinners (Feature Input).
- `lib/features/bands/band_form_screen.dart`,
  `lib/features/feedback/bug_report_screen.dart`,
  `lib/features/events/widgets/event_editor_actions.dart`,
  `event_editor_helpers.dart`, `potential_event_availability_section.dart`,
  `lib/features/songs/widgets/enrichment_progress_overlay.dart` —
  form-submission / progress spinners inside modals or editors, not first-
  load list spinners.
- `lib/features/home/home_screen.dart` — a near-duplicate of
  `home_tab_content.dart` reachable only via `setlists_screen.dart`, not the
  bottom-nav Home tab. Flagged as follow-up (see Out of Scope), NOT changed
  here.
- `lib/features/home/widgets/potential_gig_card.dart`,
  `rehearsal_card.dart` — those are IN-CARD save spinners (line 742 / 926),
  not first-load spinners.
- `lib/features/members/widgets/member_card_skeleton.dart` and all consumers —
  the reference pattern; do not refactor.
- All Supabase migrations, edge functions, RPCs, `pubspec.yaml`, platform
  configs (`macos/`, `ios/`, `android/`, `web/`). No dependency changes; no
  animation package (e.g. `shimmer`) — reuse the reference pattern's pure-
  Flutter gradient.
- `lib/app/theme/design_tokens.dart` — reuse existing tokens; do not add new
  ones.

---

## Change Budget

- Net line delta per file (expected):
  - `lib/features/home/widgets/gig_card_skeleton.dart`: **+90 new file**
  - `lib/features/home/widgets/rehearsal_card_skeleton.dart`: **+90 new file**
  - `lib/features/financials/widgets/transaction_card_skeleton.dart`: **+90 new file**
  - `lib/features/home/home_tab_content.dart`: **+42 net** (+2 imports,
    +~38 lines new `_buildLoadingSkeleton()` method, 1 line edited, 0 removed)
  - `lib/features/financials/financials_screen.dart`: **+20 net** (+1 import,
    +~22 lines new inline skeleton list, ~3 lines removed for the old
    `Center(...)`)
  - `test/features/home/widgets/home_dashboard_skeletons_test.dart`:
    **+60 new file**
  - `test/features/financials/widgets/transaction_card_skeleton_test.dart`:
    **+35 new file**
- New files: **5** (3 widgets + 2 test files).
- New public classes/methods: **3 public widget classes**
  (`GigCardSkeleton`, `RehearsalCardSkeleton`, `TransactionCardSkeleton`) +
  **1 private method** (`_buildLoadingSkeleton` on `_HomeTabContentState`).
- New dependencies: **0**.

---

## System Impact Map

| System | Status |
|--------|--------|
| Home dashboard (`gigState.isLoading` / `rehearsalState.isLoading` / stale-band branch) | **Affected — visual only** |
| Home dashboard (`bandState.isLoading` / error / no-band / empty / content / potential events) | Unaffected — unchanged |
| Financials (entry-list `isLoading` branch) | **Affected — visual only** |
| Financials (error / empty / populated content / summary / savings / PDF) | Unaffected — unchanged |
| Gigs | Unaffected (no data-flow or model changes) |
| Rehearsals | Unaffected |
| Setlists | Unaffected |
| Members | Unaffected — reference skeleton untouched |
| Auth / Session / PKCE / Magic-link | Unaffected |
| Routing / Deep links | Unaffected |
| Notifications | Unaffected |
| Init order | Unaffected |
| Database / RLS / RPCs / migrations | Unaffected |
| Platforms (iOS, Android, macOS, web) | All identical — pure Flutter widgets |

---

## Regression Risk

**LOW.**

- UI-only change scoped to two loading branches.
- No auth, session, routing, init order, or DB touched.
- New widgets are stateful only in the shimmer-animation sense (one
  `AnimationController` disposed on `dispose()`).
- `AnimatedSwitcher` continues to handle the skeleton → content transition
  the same way it currently handles the spinner → content transition.
- The `_buildLoadingState(String message)` helper is preserved verbatim so the
  auth-gated `'loading-bands'` branch is byte-identical after the change.

Highest realistic risk: skeleton animation running while the parent widget is
disposed (memory leak). Mitigated by mirroring `MemberCardSkeleton`'s dispose
pattern exactly. Verification includes a widget test that pumps the skeleton
and confirms no unhandled exception on tear-down.

---

## Engineer Task Breakdown

Ordered, atomic. Implement literally — do not merge steps or add subtasks.

1. Create `lib/features/home/widgets/rehearsal_card_skeleton.dart`. Copy the
   structural pattern (stateful widget + `SingleTickerProviderStateMixin` +
   1500 ms repeating `AnimationController` + `AnimatedBuilder` with the same
   `LinearGradient(context.colors.surface → surfaceOverlay → surface)` moving
   with `_shimmerController.value`) from `member_card_skeleton.dart`. Shape
   it as an `AppCard` sized `SizedBox(width: Spacing.rehearsalCardWidth,
   height: Spacing.rehearsalCardHeight)` containing shimmer boxes matching
   `RehearsalCard`'s confirmed layout (a small chip pill top-left, a title
   line ~180 wide, two info lines, and a small trailing element). Do not
   reference `Rehearsal` or any provider — the skeleton is a pure visual
   placeholder.
2. Create `lib/features/home/widgets/gig_card_skeleton.dart`. Same pattern,
   sized to `ConfirmedGigCard`'s `minWidth: 200, maxWidth: 400` with the
   card's `Spacing.buttonRadius` border and green-tinted background
   (matches `ConfirmedGigCard`'s `Color(0x1F22C55E)` and
   `Border.all(color: Color(0x3322C55E), width: 1.5)` — reuse the same
   literal color values from `confirmed_gig_card.dart`). Shimmer boxes:
   title line (~160×20), thin location line (~120×14), a date line
   (~90×17), a time line (~80×14).
3. Create `lib/features/financials/widgets/transaction_card_skeleton.dart`.
   Same pattern. Outer container mirrors `_TransactionCard`'s
   `Container(decoration: BoxDecoration(color: context.colors.surface,
   border: Border.all(color: context.colors.border), borderRadius:
   Spacing.cardRadius), padding: EdgeInsets.all(Spacing.space16))`. Three
   shimmer rows matching the three real rows: row 1 title box (~140×16)
   left + amount box (~70×16) right; row 2 category box (~100×12) left +
   chevron-sized (20×20) box right; row 3 date box (~90×12) left + badge-
   sized (70×18, radius 4) box right. Preserve the fixed row heights so the
   card height is identical to the real card.
4. Edit `lib/features/home/home_tab_content.dart`:
   1. Add two imports below the existing `widgets/rehearsal_card.dart`
      import: `import 'widgets/gig_card_skeleton.dart';` and
      `import 'widgets/rehearsal_card_skeleton.dart';`.
   2. Add a new private method `Widget _buildLoadingSkeleton()` alongside
      `_buildLoadingState(String message)` (do not modify or delete
      `_buildLoadingState`). It returns a
      `ColoredBox(color: context.colors.background, child: CustomScrollView(
      physics: AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [ ... ]))` with these slivers, in order:
      1. A `SliverToBoxAdapter` with a `SizedBox(height: Spacing.appBarHeight
         + MediaQuery.of(context).padding.top)` (matches the content
         state's top spacer).
      2. A `SliverPadding(padding: EdgeInsets.symmetric(horizontal:
         Spacing.pagePadding), sliver: SliverToBoxAdapter(child: Column(
         crossAxisAlignment: CrossAxisAlignment.start, children: [ ...
         ])))` containing:
         - `SizedBox(height: Spacing.space24)`,
         - `SectionHeader(title: 'Upcoming Rehearsals', topSpacing:
           Spacing.space24)`,
         - `SizedBox(height: Spacing.space12)`,
         - `SizedBox(height: Spacing.rehearsalCardHeight, child:
           ListView.separated(scrollDirection: Axis.horizontal, itemCount:
           2, separatorBuilder: (_,__) => SizedBox(width: 16), itemBuilder:
           (_,__) => RehearsalCardSkeleton()))`,
         - `SectionHeader(title: 'Upcoming Gigs', topSpacing: Spacing.space24)`,
         - `SizedBox(height: Spacing.space12)`,
         - `GigCardSkeleton()`,
         - `SizedBox(height: Spacing.space48 + Spacing.bottomNavHeight +
           MediaQuery.of(context).padding.bottom + 32)` (matches the
           content state's bottom nav clearance).
   3. On the single line reading `stateWidget = _buildLoadingState('Setting
      up the stage...');` inside the `else if (gigState.isLoading ||
      rehearsalState.isLoading || dataIsStale)` block (the `stateKey =
      'loading-gigs'` branch — currently ~line 634), replace with
      `stateWidget = _buildLoadingSkeleton();`. **Do not touch the
      identical line ~13 lines above it inside the `bandState.isLoading`
      block (`stateKey = 'loading-bands'`).**
5. Edit `lib/features/financials/financials_screen.dart`:
   1. Add `import 'widgets/transaction_card_skeleton.dart';` alongside the
      other `widgets/` imports at the top.
   2. Replace the ~3-line `Center(child: CircularProgressIndicator(color:
      AppColors.primary))` at ~line 170 with a `ListView.separated` that
      mirrors the real list's shape: same `padding: EdgeInsets.only(left:
      Spacing.pagePadding, right: Spacing.pagePadding, bottom:
      MediaQuery.of(context).padding.bottom + Spacing.space16)`,
      `separatorBuilder: (_,__) => SizedBox(height: Spacing.space12)`,
      `physics: NeverScrollableScrollPhysics()` (loading list should not
      scroll), `itemCount: 5`, `itemBuilder: (_,__) =>
      TransactionCardSkeleton()`. Do not modify the surrounding `Column`,
      `_SummaryHeader`, `_ViewModeToggle`, empty state, or error state.
6. Create `test/features/home/widgets/home_dashboard_skeletons_test.dart`:
   two smoke tests, one per skeleton. Each: pump the widget inside a
   `MaterialApp(home: Scaffold(body: Center(child:
   <SkeletonWidget>())))`, call `await tester.pump(Duration(milliseconds:
   200))` (do NOT `pumpAndSettle` — the shimmer animation never settles),
   assert `find.byType(<SkeletonWidget>)` matches one, then dispose.
7. Create `test/features/financials/widgets/transaction_card_skeleton_test.dart`:
   analogous smoke test for `TransactionCardSkeleton`.

---

## Verification Plan

### Tier 1 — Pre-deploy (mechanical, no running app, no live Supabase)

QA runs these. All must pass before APPROVED.

1. `flutter analyze` — zero new warnings and zero new errors. Baseline is
   the current `main` warning count.
2. `flutter test test/features/home/widgets/home_dashboard_skeletons_test.dart
   test/features/financials/widgets/transaction_card_skeleton_test.dart` —
   all three widgets pump without exception, `AnimationController`
   disposes cleanly on tear-down (no "AnimationController.dispose called
   more than once" or leaked-timer errors in the test log).
3. Static diff review — confirm `_buildLoadingState(String message)` in
   `home_tab_content.dart` is unchanged (byte-identical to `main`), and
   the `bandState.isLoading` branch (`stateKey = 'loading-bands'`) still
   calls it. This is the regression guard for the "auth/shell gate
   spinners are out of scope" invariant.
4. Static diff review — confirm no changes to
   `member_card_skeleton.dart`, `members_tab_content.dart`,
   `band_members_view.dart`, `home_screen.dart`, `auth_gate.dart`,
   `app_shell.dart`, `no_band_shell.dart`, `app_button.dart`, or any file
   in the Off-Limits list.
5. Change-budget audit — confirm the actual diff line counts fall within
   ±30% of the Change Budget above. A large overrun is a red flag that
   scope crept.

### Tier 2 — Owner punch list (Tony, at PR-test / apply time)

QA hands these to Tony verbatim; QA does not attempt them (structural
limitation of the pipeline). Numbered steps with expected results per step.

1. **Home dashboard cold-load, iOS simulator.** Fresh install → sign in →
   land on Home tab. **Expected:** while gig/rehearsal data loads, the
   viewport shows the "Upcoming Rehearsals" section header + two
   shimmering rehearsal-shaped card placeholders in a horizontal row,
   then "Upcoming Gigs" section header + one shimmering gig-shaped card
   placeholder — NOT a centered pulsing circle with "Setting up the
   stage..." caption. When data resolves, the skeleton fades out via
   `AnimatedSwitcher` into the real content with no jarring pop.
2. **Home dashboard, initial band load.** Kill the app between step 1
   and this step. Relaunch and observe the very first frame. **Expected:**
   during the `bandState.isLoading` phase (before any band is resolved),
   the "Setting up the stage..." centered spinner still appears
   momentarily — this is the auth/shell gate scope that stays as-is.
   Skeleton only appears after bands load and gig/rehearsal load begins.
3. **Home dashboard, band switch.** From Home tab, open band switcher →
   switch to a second band. **Expected:** while data reloads for the
   new band (`dataIsStale` phase), the shimmer skeleton appears again
   (same as step 1), not the centered spinner.
4. **Financials cold-load, iOS simulator.** From Home → tap Financials
   quick action. **Expected:** the Income/Expenses toggle and summary
   header render immediately, then the list area shows ~5 shimmering
   transaction-card-shaped placeholders (three-row shape, same size as
   real cards) — NOT a centered spinner. When entries resolve,
   skeletons swap to real cards with no chrome shift.
5. **Financials with zero entries.** In a band with zero financial
   entries, cold-load the screen. **Expected:** brief skeleton flash,
   then the existing `_EmptyState` — no regression to empty-state
   behavior.
6. **Repeat steps 1 and 4 on macOS and web (Chrome).** **Expected:**
   identical behavior on all three platforms. Shimmer animation runs
   smoothly (60fps target; no visible jank on macOS Retina or web
   canvas rendering). Skeleton dimensions match real card dimensions
   within a couple of pixels.
7. **Reference (regression) sanity check.** Open the Members tab.
   **Expected:** `MemberCardSkeleton` behavior is unchanged from main
   (still shimmers, still 3 cards, still swaps to real member cards).
   This confirms the reference file was not touched.

---

## QA Regression Areas

Even though this is UI-only, QA (or Tony's punch-list run) should sanity-
check the following areas that share render trees with the affected
screens:

- **Home dashboard `AnimatedSwitcher` transitions** — every state key
  (`loading-bands`, `error-bands`, `no-band`, `loading-gigs`, `empty`,
  `error-gigs`, `content`) still cross-fades smoothly. The new
  `loading-gigs` skeleton must animate in/out via the same
  `SlideTransition + FadeTransition` as the other keys.
- **Home dashboard content state** — unchanged. Section headers,
  spacings, horizontal scroll behavior, refresh indicator all still
  work.
- **Financials list layout** — the padding, separator, and scroll
  behavior of the real list must be visually indistinguishable from the
  skeleton layout so the transition is imperceptible.
- **Financials sub-features** — Combined Report, PDF preview, Savings
  sheet, add-entry sheet all still open and function. None share a
  loading branch with the change.
- **Members tab** — the reference `MemberCardSkeleton` still renders
  correctly (regression guard for accidentally touching shared
  helpers).
- **App shell / bottom nav** — `bandState.isLoading` still shows the
  "Setting up the stage..." spinner (structural guard against
  accidentally converting the auth-gate branch).

---

## Rollout Strategy

Standard PR from `feature/skeleton-loading-states` → `main`. No
feature flag. No migration. No config change. Immediately safe to ship
on merge — the change only affects the visual of two loading branches
and does not alter data flow, permissions, or any user-visible
successful state.

Post-merge, on the next TestFlight / web deploy cycle, Tony's punch-list
above serves as the acceptance smoke.

---

## Out of Scope

The following are explicitly NOT in this branch. They are flagged for
possible follow-up but must not be added here:

- **`lib/features/home/home_screen.dart` line 548** — a near-duplicate
  of `home_tab_content.dart` reachable only via `setlists_screen.dart`,
  not the bottom-nav Home tab. Same `_buildLoadingState` pattern.
  Follow-up candidate if usage warrants, but not high-traffic per the
  Feature Input.
- **`lib/features/events/widgets/potential_event_availability_section.dart`
  line 137** — a sub-section spinner inside an event editor modal,
  not a first-load screen. Low-traffic surface. Follow-up candidate
  at best.
- **All other `CircularProgressIndicator` usages** enumerated in the
  Feature Input (auth_gate, band_form, event_editor_actions,
  bug_report, enrichment_progress_overlay, app_shell, no_band_shell)
  — correctly scoped as-is per the Feature Input; **do not convert**.
- **Extracting a shared `ShimmerBox` helper** or `AppSkeleton` base
  class across the three new widgets + `MemberCardSkeleton`. The
  reference deliberately duplicates the shimmer helpers inline; this
  branch matches that decision. Any DRY refactor is a separate
  discussion for its own plan.
- **Adding the `shimmer` package** (or any other new dependency).
- **Applying the skeleton animation to `_TransactionCard` real
  content** or reshaping any real card. Skeletons are placeholders,
  not restyles.
- **Adding `HomeAppBar` to the skeleton state.** Current
  `_buildLoadingState` does not render the app bar during the
  `loading-gigs` branch; the skeleton matches that existing behavior
  exactly. Adding the app bar during skeleton is a UX decision worth
  its own plan.
