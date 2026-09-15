# ARCHITECT_PLAN

## Feature Slug

`bug/setlist-detail-overlay-consistency`

## Feature Title

Align Setlist Detail with established overlay UI

## Problem Summary

Setlist Detail (`lib/features/setlists/setlist_detail_screen.dart`) presents with different navigation chrome and a different overlay structure than the established reference screens My Profile (`lib/features/profile/profile_screen.dart`) and Settings (`lib/features/settings/settings_screen.dart`). The back control is a `chevronLeft` + "Back" text label rendered inside a custom `GlassSurface`, rather than the shared `AppIconButton(AppIcons.arrowLeft)` slotted into the shared `AppAppBar`. The whole app bar is also rendered as a body child, not through `AppScaffold`'s `appBar` slot, so it bypasses the standard overlay component entirely.

## Root Cause

**Confidence: HIGH** — confirmed by reading source.

Two concrete divergences from the reference implementations:

1. **Wrong chrome component.** Setlist Detail uses `BackOnlyAppBar` (`lib/features/setlists/widgets/back_only_app_bar.dart`), a bespoke `GlassSurface`-backed widget with `GestureDetector` → `Row(Icon(AppIcons.back /* = LucideIcons.chevronLeft */, 18px, white), Text('Back', bold, white))`. The reference screens use `AppAppBar` (`lib/components/ui/app_app_bar.dart`, a Forui `FHeader.nested` wrapper) with `leading: AppIconButton(icon: AppIcons.arrowLeft, color: AppColors.primary, onPressed: pop)` (`lib/components/ui/app_icon_button.dart`, a Forui `FButton.icon` wrapper).

2. **Wrong overlay structure.** Reference screens pass their `AppAppBar` to `AppScaffold`'s `appBar:` slot (which Forui `FScaffold` renders as the `header:` in its standard chrome). Setlist Detail leaves `AppScaffold.appBar` unset and instead renders `BackOnlyAppBar` as the first child of a `Column` inside `body: SafeArea(child: Column(children: [_buildAppBar(state), Expanded(child: _buildBody(...))]))`. That means the header, safe-area handling, and background composition run through a different code path than every other reference screen.

Concrete evidence:

- `lib/features/setlists/setlist_detail_screen.dart` line 2159 (`AppScaffold` with no `appBar:` argument, body `Column` starts with `_buildAppBar(state)`), line 2187 (`_buildAppBar` returns `BackOnlyAppBar(...)`).
- `lib/features/setlists/widgets/back_only_app_bar.dart` lines 41–91 (custom `GlassSurface` chrome with scroll-driven blur, chevron+text back control).
- `lib/features/profile/profile_screen.dart` lines 106–140 (reference: `AppScaffold(appBar: AppAppBar(backgroundColor: appBarBg, title: Text('My Profile', style: AppTextStyles.title3), leading: AppIconButton(icon: AppIcons.arrowLeft, color: AppColors.primary, onPressed: pop), actions: [...]))`).
- `lib/features/settings/settings_screen.dart` lines 287–305 (same reference pattern, title `'Settings'`).
- `lib/app/theme/app_icons.dart` line 22 (`AppIcons.back = LucideIcons.chevronLeft`, distinct from line 24 `AppIcons.arrowLeft = LucideIcons.arrowLeft`).

## Existing System Analysis

- `AppScaffold` wraps Forui `FScaffold` and is the standard scaffold across the app; Setlist Detail already uses it, so the scaffold layer is not the problem — only the header wiring is.
- `AppAppBar` wraps Forui `FHeader` / `FHeader.nested`; it accepts `title`, `leading`, `actions`, `backgroundColor`, `centerTitle`. Per its own doc comment the `backgroundColor` prop is currently ignored by Forui in the preview cycle, but reference screens still pass `context.colors.appBarBg` for consistency once the wrapper honors it.
- `AppIconButton` wraps Forui `FButton.icon`; its `color` and `size` props are currently ignored (Forui preview limitation), but reference screens still pass `AppColors.primary` for the same forward-compat reason.
- `BackOnlyAppBar` is used in exactly two screens today: `setlist_detail_screen.dart` (in scope) and `new_setlist_screen.dart` (out of scope per Feature Input). No tests reference it.
- Every caller that pushes `SetlistDetailScreen` (`lib/features/setlists/setlists_screen.dart` line 452, `lib/features/setlists/setlists_tab_content.dart` line 125, `lib/features/gigs/widgets/view_gig_drawer.dart` line 602, `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart` line 420) uses `fadeSlideRoute(page: SetlistDetailScreen(setlistId, setlistName))` and calls `Navigator.of(context).pop()` to dismiss — none inspect the chrome; the swap is transparent to callers.
- The setlist name (`_currentName`) is already displayed prominently in the body as a `pageTitle`-styled header (line 2455) with Catalog star and inline rename affordance. That body header is unchanged by this fix — the app bar title carries a screen-type label, matching Profile ("My Profile") and Settings ("Settings"), while the entity's own name continues to render in the body header where the rename UI already lives.
- The `BackOnlyAppBar.showLoading` prop is set to `state.isDeleting || state.isReordering`. That maps naturally onto `AppAppBar.actions` as a small `AppProgressIndicator` rendered when either flag is true (mirroring the pattern in Profile where `actions` holds a per-state widget).

## Proposed Solution

Swap Setlist Detail's chrome from the bespoke `BackOnlyAppBar` in the body to the shared `AppAppBar` in `AppScaffold`'s `appBar:` slot, with the same leading control convention Profile and Settings use.

Concretely, in `lib/features/setlists/setlist_detail_screen.dart`:

1. Remove `import 'widgets/back_only_app_bar.dart';`.
2. Add imports for `package:bandroadie/components/ui/app_app_bar.dart` and (if not already present) reuse the existing `AppIconButton`, `AppProgressIndicator`, `AppScaffold`, `AppIcons`, `AppColors`, `AppTextStyles` imports the file already has.
3. Rewrite `build`'s scaffold assembly so the header goes through `AppScaffold`'s `appBar:` slot:
   - Pass `appBar: AppAppBar(backgroundColor: context.colors.appBarBg, title: Text('Setlist', style: AppTextStyles.title3), leading: AppIconButton(icon: AppIcons.arrowLeft, color: AppColors.primary, onPressed: () => Navigator.of(context).pop()), actions: (state.isDeleting || state.isReordering) ? [const AppProgressIndicator()] : const [])`.
   - `body:` is the existing `_buildBody(state, canEdit)` return, still wrapped in the same `Stack` that hosts the sticky Select-Mode bottom actions bar (Catalog only). The Select-Mode `Positioned` block is preserved verbatim.
   - Remove the intermediate `Column(children: [_buildAppBar(state), Expanded(child: _buildBody(...))])` and the `SafeArea` wrapper around it — `FScaffold` already handles safe-area insets on its `header:` slot the same way it does for Profile and Settings, so the manual `SafeArea` is redundant once the header moves into the correct slot.
4. Rewrite `_buildAppBar(state)` to return the `AppAppBar` above (or inline the construction into `build` and delete `_buildAppBar` — either is fine; keeping the helper is smaller diff).
5. Do **not** delete `lib/features/setlists/widgets/back_only_app_bar.dart` — `new_setlist_screen.dart` still imports and uses it, and that screen is out of scope for this fix.

Title text rationale (not a design pick — direct pattern match): Profile's title is the screen-type label `"My Profile"`, Settings' title is the screen-type label `"Settings"`. The analogous screen-type label for Setlist Detail is `"Setlist"`. The specific setlist's name continues to render in the body page-title header, unchanged, alongside the Catalog star and the existing inline rename affordance.

## Database Impact

n/a

## Flutter Architecture Changes

- Chrome for Setlist Detail moves from a body-child custom widget to the standard `AppScaffold(appBar: AppAppBar(...))` slot, aligning it with every other reference screen in the app.
- No new controllers, providers, repositories, services, or routes. No new dependencies. No changes to state management, band isolation, or the `setlistDetailProvider` contract.
- Init order (main.dart) unchanged. `--dart-define` config, Supabase init, Firebase init (native only), DeepLinkService init all untouched.

## Files to Create

None.

## Files to Modify

| File | Changes |
| --- | --- |
| `lib/features/setlists/setlist_detail_screen.dart` | Remove `import 'widgets/back_only_app_bar.dart';`. Add `import 'package:bandroadie/components/ui/app_app_bar.dart';`. In `build`, pass `AppAppBar` into `AppScaffold.appBar:` instead of rendering `BackOnlyAppBar` as a body child; remove the `SafeArea` + `Column(_buildAppBar, Expanded(_buildBody))` wrapper; keep the existing `Stack` for the Select-Mode `Positioned` bottom actions bar. In `_buildAppBar(state)`, return the `AppAppBar` described in Proposed Solution (or inline into `build` and delete the helper). Loading indicator (`state.isDeleting || state.isReordering`) surfaces via `AppAppBar.actions` as an `AppProgressIndicator`. |

## Files Off-Limits

| File | Why |
| --- | --- |
| `lib/features/setlists/widgets/back_only_app_bar.dart` | Still consumed by out-of-scope `new_setlist_screen.dart`. Do not delete or modify. |
| `lib/features/setlists/new_setlist_screen.dart` | Uses `BackOnlyAppBar` but the Feature Input scopes this fix to Setlist Detail only. Separate ticket if consistency is desired there. |
| `lib/components/ui/app_app_bar.dart` | Shared chrome — do not modify to accommodate this screen. |
| `lib/components/ui/app_icon_button.dart` | Shared chrome — do not modify. |
| `lib/components/ui/app_scaffold.dart` | Shared chrome — do not modify. |
| All other files under `lib/features/setlists/` (controller, repository, widgets other than the app bar wiring) | Not part of the chrome. |
| Any callers of `SetlistDetailScreen` (`setlists_screen.dart`, `setlists_tab_content.dart`, `view_gig_drawer.dart`, `view_rehearsal_drawer.dart`) | Constructor signature is unchanged; callers do not touch the chrome. |
| `supabase/**`, `android/**`, `ios/**`, `macos/**`, `web/**` | No platform-conditional code, no schema, no config touched. |

## Change Budget

- Expected net line delta on `lib/features/setlists/setlist_detail_screen.dart`: **between −15 and +10 lines** (removing the custom app bar wiring + `SafeArea`/`Column` wrapper, adding `AppAppBar` construction).
- Expected new files: **0**.
- Expected new public classes/methods: **0**.
- Expected new dependencies: **0**.

If the diff exceeds this budget, Engineer has drifted beyond the scoped chrome swap.

## System Impact Map

| System | Status |
| --- | --- |
| Setlists (Setlist Detail) | Affected — chrome swap |
| Setlists (list, new setlist, create setlist, PDF preview, other widgets) | Unaffected |
| Gigs | Unaffected — pushes `SetlistDetailScreen` with unchanged constructor |
| Rehearsals | Unaffected — same |
| Members | Unaffected |
| Auth / session / routing | Unaffected |
| Notifications | Unaffected |
| Platforms (iOS / Android / macOS / Web) | Uniformly affected via one Flutter widget code path; no platform-conditional branches touched |
| Supabase (schema, RLS, RPC, edge functions) | Unaffected |
| Init order / `--dart-define` config | Unaffected |

## Regression Risk

**LOW.** Change is contained to one file's `build` method and its `_buildAppBar` helper. No behavior changes beyond the chrome component swap: back gesture still pops, loading indicator still surfaces during delete/reorder (via `actions`), Select-Mode bottom actions bar preserved verbatim, all body content and providers untouched. No auth, session, routing, init-order, or database code touched. All supported platforms exercise the same Flutter widget code path; no platform-conditional branch is introduced or altered.

## Engineer Task Breakdown

1. In `lib/features/setlists/setlist_detail_screen.dart`, remove `import 'widgets/back_only_app_bar.dart';` and add `import 'package:bandroadie/components/ui/app_app_bar.dart';`.
2. In the same file, rewrite the `build` method's scaffold assembly:
   - `AppScaffold(backgroundColor: context.colors.background, appBar: AppAppBar(backgroundColor: context.colors.appBarBg, title: Text('Setlist', style: AppTextStyles.title3), leading: AppIconButton(icon: AppIcons.arrowLeft, color: AppColors.primary, onPressed: () => Navigator.of(context).pop()), actions: (state.isDeleting || state.isReordering) ? const [AppProgressIndicator()] : const []), body: Stack(children: [_buildBody(state, canEdit), if (_isSelectMode && state.isCatalog) Positioned(left: 0, right: 0, bottom: 0, child: _buildSelectModeBottomActions())]))`.
   - Remove the surrounding `SafeArea` and the `Column(children: [_buildAppBar(state), Expanded(child: _buildBody(state, canEdit))])` wrapper.
3. Rewrite `_buildAppBar(SetlistDetailState state)` to return the `AppAppBar` described above, or inline the construction into `build` and delete `_buildAppBar` (whichever produces a smaller diff — inlining is preferred if it fits cleanly).
4. Do not touch `lib/features/setlists/widgets/back_only_app_bar.dart`, `new_setlist_screen.dart`, or any other file.
5. Run `flutter analyze` locally before opening the PR; the dead import removal and the `AppAppBar` addition must both resolve cleanly.

## Verification Plan

### Tier 1 — Pre-deploy, mechanically executable by QA

1. **`flutter analyze`** on the changed file must exit clean (no unused imports, no missing symbols, no analyzer warnings introduced).
2. **Static grep gate** (QA runs these against the working tree, not the app):
   - `grep -n "BackOnlyAppBar" lib/features/setlists/setlist_detail_screen.dart` → **0 matches** expected.
   - `grep -n "back_only_app_bar" lib/features/setlists/setlist_detail_screen.dart` → **0 matches** expected (import removed).
   - `grep -n "app_app_bar.dart" lib/features/setlists/setlist_detail_screen.dart` → **≥ 1 match** expected (import added).
   - `grep -c "BackOnlyAppBar" lib/features/setlists/widgets/back_only_app_bar.dart lib/features/setlists/new_setlist_screen.dart` → **still non-zero** (widget file and out-of-scope consumer both retained unchanged).
   - `grep -n "AppIcons.arrowLeft" lib/features/setlists/setlist_detail_screen.dart` → **≥ 1 match** expected (leading icon on the new chrome).
3. **`flutter test`** on the existing harness must remain green. Do **not** add a widget test for `SetlistDetailScreen` in this PR — the screen has heavy Riverpod/Supabase dependencies and standing up a mock for a chrome-only assertion is disproportionate to the risk (LOW) and the guardrail on test proliferation. If test infra for this screen is added later as its own feature, the chrome assertion belongs there.

### Tier 2 — Post-deploy

n/a. No RPC changes, no migrations, no edge functions, no schema changes. Nothing to verify against a live database.

### Owner-run PR-test checklist (Tony, at PR-test time — not a QA gate)

For each of iOS, Android, macOS, Web:

1. Open BandRoadie and select an active band. **Expected:** app launches and the active band is selected as usual.
2. Navigate to Setlists. **Expected:** the setlists list renders as before.
3. Tap any non-Catalog setlist. **Expected:** Setlist Detail opens; the header shows the shared `AppAppBar` chrome — leading is a rose-primary left-arrow (`AppIcons.arrowLeft`), title reads `Setlist`, no "Back" text label, no custom glass-blur strip. It should look visually identical in shape to My Profile's and Settings' chrome.
4. Tap the leading arrow. **Expected:** returns to the setlists list (pop works).
5. Reopen the same setlist, reorder a song by dragging the grip. **Expected:** during the persist window, a small `AppProgressIndicator` appears in the app bar's `actions` slot (top-right), then disappears on completion.
6. Reopen the same setlist and delete a song via the confirm dialog. **Expected:** same indicator behavior in `actions` during the delete.
7. Open the Catalog setlist. Enter Select Mode. **Expected:** the sticky bottom actions bar still appears at the bottom of the screen (Catalog only).
8. Rename the setlist via the inline edit icon in the body page-title header. **Expected:** the body header updates to the new name; the app bar title still reads `Setlist` (unchanged — this is intentional; the entity name lives in the body header, matching Profile/Settings convention).
9. Open Setlist Detail from a Gig drawer and from a Rehearsal drawer. **Expected:** same chrome in both cases; back returns to the drawer/host.
10. Compare side-by-side with My Profile and Settings. **Expected:** leading icon, title placement, actions area, background handling all match.

## QA Regression Areas

- Setlist Detail chrome on all four platforms (iOS, Android, macOS, Web) — visual parity with Profile/Settings.
- Loading indicator (`state.isDeleting`, `state.isReordering`) surfaces correctly in the new `actions` slot.
- Select-Mode bottom actions bar (Catalog only) still renders in the correct position after the `SafeArea`/`Column` wrapper is removed.
- Body page-title header (`_currentName`, Catalog star, inline rename edit icon) still renders and remains functional — this is not the app bar and must be untouched.
- Callers of `SetlistDetailScreen` (setlists list, setlists tab content, gig drawer, rehearsal drawer) still push and pop correctly.
- Nested navigation from Setlist Detail (song lookup overlay, add-to-setlist overlay, print options bottom sheet, PDF preview, lyrics view, enrichment overlays) still opens and pops back correctly.
- `new_setlist_screen.dart` is unchanged and still uses `BackOnlyAppBar` — that inconsistency is intentionally out of scope for this ticket.

## Rollout Strategy

Standard PR to `main`. No feature flag, no staged rollout, no migration timing. Ship with the next mobile build and next web deploy. No user comms needed — this is a chrome-consistency fix with no behavior change.

## Out of Scope

- `lib/features/setlists/new_setlist_screen.dart` continues to use `BackOnlyAppBar`. If Manager wants that aligned too, file a separate feature ticket — Feature Input scoped this fix to Setlist Detail.
- Deletion of `lib/features/setlists/widgets/back_only_app_bar.dart`. Cannot delete while `new_setlist_screen.dart` still consumes it.
- Any change to the body content of Setlist Detail — page-title header, action buttons row (`+ Add`, `Search`, `Sort`, `Enrich`), song cards, drag/reorder behavior, inline edit affordances, Select Mode bottom bar. All untouched.
- Any change to `AppScaffold`, `AppAppBar`, `AppIconButton`, or their Forui wrappers.
- Any change to Profile or Settings.
- Adding widget-test infrastructure for `SetlistDetailScreen` (belongs in its own feature).
