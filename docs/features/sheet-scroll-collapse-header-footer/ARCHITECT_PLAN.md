# ARCHITECT_PLAN — sheet-scroll-collapse-header-footer

## Feature Slug

`sheet-scroll-collapse-header-footer`

## Feature Title

Collapse sheet header on scroll-down and hide footer during scroll for maximum vertical space

## Problem Summary

Bottom sheets and drawers with scrollable content have a fixed drag-handle/title header and a sticky `SheetFooter` that permanently consume vertical real estate. On small screens (iPhone SE, older Android, macOS narrow windows) this can leave very little room for the actual content the user is reading or editing. The UX best practice — used by iOS Mail, Gmail, and the App Store — is to collapse the chrome (header up, footer down) while the user is actively scrolling to give the content maximum room, then bring the chrome back the moment the user pauses or reverses direction so primary actions (Save, Update, Add) stay reachable.

## Root Cause

Every qualifying sheet independently owns its own scaffold shape (drag handle → optional fixed header → scrolling body → sticky `SheetFooter`) and there is no shared mechanism to observe primary-body scroll events and react. Each sheet also uses one of two structurally different variants of that shape:

- **Pattern A** — the title/header lives _inside_ the scroll body (`Column(dragHandle, Flexible(SingleChildScrollView(Column(title, ...))), SheetFooter)`).
- **Pattern B** — the title/header is fixed _above_ the scroll body (`Column(dragHandle, header, Flexible(SingleChildScrollView(body)), SheetFooter)`).

Because the reaction to scroll direction is orthogonal to per-sheet content, and because the two patterns need different handling (Pattern A: only the footer collapses; Pattern B: both header and footer collapse), the fix is a single shared scaffold widget that both patterns adopt.

**Confidence: HIGH.** Verified by reading the `build()` of every one of the 20 qualifying files listed below.

## Existing System Analysis

The prior standardization work (PR #241) shipped `lib/components/ui/sheet_footer.dart` and adopted it across 27 sheet/drawer files. That inventory sorts as follows for this feature:

- **20 targets** for the collapsing scaffold — 10 Pattern A + 10 Pattern B (listed under _Files to Modify_).
- **3 deferred**: `key_picker_bottom_sheet.dart`, `tuning_picker_bottom_sheet.dart`, `print_options_bottom_sheet.dart` — all use `DraggableScrollableSheet`, which has its own draggable-height behavior orthogonal to this collapsing model. Revisit as a follow-up.
- **1 excluded (dialog, not a sheet)**: `calendar_subscription_dialog.dart`.
- **3 not-applicable (per prior inventory)**: `set_break_creator.dart`, `custom_tuning_modal.dart`, `role_management_sheet.dart`.

Shared building blocks the scaffold will use as-is:

- `SheetFooter` (public API frozen — Off-Limits) already owns its own top border, drop shadow, `SafeArea` bottom padding, and destructive-row layout.
- `showAppBottomSheet()` in `lib/components/ui/app_bottom_sheet.dart` — presentation harness, unaffected.

## Proposed Solution

Add one new widget, `CollapsingSheetScaffold`, at `lib/components/ui/collapsing_sheet_scaffold.dart`. Every qualifying sheet swaps its top-level `Column(dragHandle, [header,] body, footer)` shape for this scaffold. No new providers, no new controllers outside the scaffold's private `AnimationController`, no new dependencies, no changes to `SheetFooter`.

### Scaffold public API

```dart
class CollapsingSheetScaffold extends StatefulWidget {
  const CollapsingSheetScaffold({
    super.key,
    this.dragHandle,   // optional; defaults to the standard 40x4 pill
    this.header,       // optional; null on Pattern A sheets
    required this.body,
    this.footer,       // typically SheetFooter; null allowed
  });

  final Widget? dragHandle;
  final Widget? header;
  final Widget body;
  final Widget? footer;
}
```

### Slots

- **`dragHandle`** — always visible; not part of the collapse animation.
- **`header`** — when non-null, wrapped in a `SizeTransition(axisAlignment: 1.0, ...)` so it collapses upward off-screen. When null (Pattern A), no header slot is rendered.
- **`body`** — required. The scaffold renders the body inside an `Expanded`. If the caller's body is not already a scrollable, the scaffold wraps it in a `SingleChildScrollView` so a primary scroll surface always exists to attach the listener to.
- **`footer`** — when non-null, wrapped in a `SizeTransition(axisAlignment: -1.0, ...)` so it collapses downward off-screen. `SheetFooter` continues owning its own safe-area padding; the scaffold does not add or strip padding around it.

### Scroll detection

The scaffold wraps the body region in a single `NotificationListener<ScrollNotification>`. It only reacts when `notification.depth == 0` (primary body scrollable) so a nested horizontal list or inner scroller in a sheet cannot trigger collapse.

- `ScrollMetricsNotification` and the first `ScrollUpdateNotification` set `_hasOverflow = metrics.maxScrollExtent > 0`. When `_hasOverflow` is false, chrome is forced visible and every other event is a no-op.
- `UserScrollNotification` with `direction == ScrollDirection.reverse` (finger dragging content up, i.e. scrolling further into the content) → **collapse**.
- `UserScrollNotification` with `direction == ScrollDirection.forward` → **immediate reveal**.
- `ScrollEndNotification` → **immediate reveal** so the Save/Update button is back the moment the user pauses.
- `ScrollUpdateNotification` deltas are only considered after an accumulated absolute delta of **6 logical pixels** since the last direction change (anti-flicker threshold). This is small enough to feel responsive to real scrolling and large enough to filter finger tremor and one-frame overscroll bounces. Rapid direction flips inside a **50 ms debounce window** are ignored to keep the chrome from oscillating on jitter.

### Animation

- Single private `AnimationController` with `duration: Duration(milliseconds: 220)`.
- Collapse uses `Curves.easeIn`, reveal uses `Curves.easeOut` — the standard iOS/Material easing pattern for "content-preserving" chrome collapse.
- Both `SizeTransition`s share the same controller so header and footer collapse/reveal together, and the freed space is reclaimed by the body's `Expanded` — no dead gap.

### UX best-practice guards (applied on every rebuild)

- **Keyboard suppression** — `MediaQuery.viewInsetsOf(context).bottom > 0` ⇒ force controller to `value: 1.0` and short-circuit scroll listener so nothing collapses while a text field is focused. The user's primary Save action must stay in view during active text entry.
- **Reduced motion (`MediaQuery.disableAnimationsOf(context)`)** — chrome is always visible (controller pinned at `1.0`) and collapse is disabled entirely. Rationale: on accessibility "reduce motion", a snapping/instant transition would still create a discrete layout jump that is more disruptive to VoiceOver focus and low-vision users than the persistent-chrome baseline. Disabling collapse is the safer UX call.
- **No-overflow no-op** — detected from `ScrollMetricsNotification`. If body fits, chrome never collapses.
- **Nested-scroll safety** — depth==0 filter.
- **Safe area** — the scaffold does not modify safe-area padding around the footer; `SheetFooter` continues owning its own bottom safe-area.

### Pattern-A vs Pattern-B usage

- **Pattern A** (title inline in scroll body, 10 sheets): call site passes `header: null`. Only the footer collapses; the inline title scrolls off naturally with the body.
- **Pattern B** (fixed title above scroll body, 10 sheets): call site extracts the previously-fixed header widget into the scaffold's `header` slot. Both collapse.

## Database Impact

n/a

## Flutter Architecture Changes

- One new widget file (`collapsing_sheet_scaffold.dart`) + its widget test.
- No new providers, repositories, controllers, services, or models.
- No new dependencies.
- `SheetFooter` public API unchanged.
- No changes to init order, PKCE flow, `--dart-define` config, deep links, or Supabase.

## Files to Create

1. `lib/components/ui/collapsing_sheet_scaffold.dart`
2. `test/components/ui/collapsing_sheet_scaffold_test.dart`

## Files to Modify

### Pattern A — footer collapse only (`header: null`), 10 files

Wrap the existing top-level `Column(dragHandle, Flexible(SingleChildScrollView(...)), SheetFooter(...))` in `CollapsingSheetScaffold`, passing the current SingleChildScrollView's child as `body` and the existing `SheetFooter` as `footer`. Preserve every existing wrapper (PopScope, `AnimatedBuilder` entrance animation, `Padding(bottom: viewInsets.bottom)`) outside the scaffold — do not move them into it.

1. `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` — the sheet Tony named. Existing footer includes conditional destructive-delete row; preserve. Existing outer `Padding(bottom: keyboardHeight)` stays outside the scaffold.
2. `lib/features/financials/widgets/gig_pay_bottom_sheet.dart` — "Gig Pay Details" title lives inside the scroll body; no header refactor.
3. `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` — body currently has no scrollable; the scaffold wraps its content in a `SingleChildScrollView` internally, so the sheet no longer overflows on small screens. No-overflow guard means chrome does not collapse when content fits.
4. `lib/features/calendar/widgets/view_block_out_drawer.dart`
5. `lib/features/gigs/widgets/view_gig_drawer.dart`
6. `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`
7. `lib/features/contacts/widgets/band_member_detail_drawer.dart`
8. `lib/features/contacts/widgets/contact_detail_drawer.dart`
9. `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`
10. `lib/features/setlists/widgets/pause_creator.dart` — preserve the entrance-animation `AnimatedBuilder` wrapper _outside_ the scaffold.

### Pattern B — full behavior: header AND footer collapse, 10 files

Extract the previously-fixed header widget (drag handle → title Padding block → Divider) so the drag handle becomes the scaffold's `dragHandle` slot, the title/subtitle block becomes the `header` slot, and the previously-scrollable body becomes `body`. `SheetFooter` moves into `footer`. Preserve PopScope, entrance animations, and keyboard-padding wrappers outside the scaffold.

11. `lib/features/calendar/widgets/day_detail_bottom_sheet.dart` — date + close-button block becomes the `header`; events `ListView` becomes `body`.
12. `lib/features/gigs/widgets/gig_notes_sheet.dart` — gig name becomes the `header`; notes text becomes `body`.
13. `lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart` — "Rehearsal Notes" label becomes the `header`.
14. `lib/features/setlists/widgets/song_notes_drawer.dart` — "Notes" label becomes the `header`. Preserve PopScope and existing `viewInsets.bottom` padding wrapper outside the scaffold.
15. `lib/features/setlists/widgets/song_details_bottom_sheet.dart` — `_buildHeader()` (title + close + subtitle) becomes the `header`. Preserve PopScope, entrance `AnimatedBuilder`, and viewInsets padding outside.
16. `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` — `_buildHeader()` ("Review Song" + close) becomes the `header`. Preserve PopScope + entrance animation outside.
17. `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` — `_buildHeader()` ("Add To Setlist" + Move/Copy toggle) becomes the `header`. The `SheetFooter` in this sheet is _conditional_ — it only appears inside the create-new form. In list mode (no footer), pass `footer: null`; the scaffold must handle this without crashing or leaving a dead gap. Header still collapses when the list scrolls.
18. `lib/features/calendar/widgets/add_block_out_drawer.dart` — drawer title Padding block becomes the `header`.
19. `lib/features/contacts/widgets/band_member_edit_drawer.dart` — "Edit" label + member name + current role block becomes the `header`.
20. `lib/features/events/widgets/event_editor_drawer.dart` — replace `_buildStickyHeader(context)` and `_buildStickyFooter(context)` call sites with the scaffold's `header` / `footer` slots. `_buildScrollableBody(context)` moves into `body`.

## Files Off-Limits (do not touch, with reasons)

- `lib/components/ui/sheet_footer.dart` — public API frozen; scaffold consumes SheetFooter as-is, does not fork or extend it.
- `lib/components/ui/app_bottom_sheet.dart` — presentation harness (`showAppBottomSheet`); no changes needed and no changes wanted.
- `lib/features/setlists/widgets/key_picker_bottom_sheet.dart` — DraggableScrollableSheet, deferred.
- `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart` — DraggableScrollableSheet, deferred.
- `lib/features/setlists/widgets/print_options_bottom_sheet.dart` — DraggableScrollableSheet, deferred.
- `lib/features/calendar/widgets/calendar_subscription_dialog.dart` — dialog, not a sheet.
- `lib/features/setlists/widgets/set_break_creator.dart` — not applicable per prior inventory.
- `lib/features/setlists/widgets/custom_tuning_modal.dart` — not applicable per prior inventory.
- `lib/features/members/widgets/role_management_sheet.dart` — not applicable per prior inventory.
- `lib/main.dart` — init order unaffected.
- `supabase/` — no DB / RLS / Edge Function changes.
- `pubspec.yaml` — no new dependencies.

## Change Budget

- **New files:** 2 (`collapsing_sheet_scaffold.dart`, `collapsing_sheet_scaffold_test.dart`).
- **New public classes:** 1 (`CollapsingSheetScaffold`).
- **New public methods:** 0 (widget constructor only).
- **New dependencies:** 0.
- **Per-file net line delta:**
  - `collapsing_sheet_scaffold.dart` — +250 to +320 lines.
  - `collapsing_sheet_scaffold_test.dart` — +180 to +260 lines.
  - Each Pattern A sheet — roughly −5 to +25 lines (wrap existing body in scaffold, move existing SheetFooter into footer slot).
  - Each Pattern B sheet — roughly −10 to +30 lines (extract header widget out of the top-level `Column` into the scaffold's `header` slot).
  - `event_editor_drawer.dart` may skew higher because its `_buildStickyHeader`/`_buildStickyFooter` are already extracted methods, so the diff is mostly a two-line call-site swap.

## System Impact Map

- **Gigs** — affected: `view_gig_drawer`, `gig_notes_sheet`, `gig_pay_bottom_sheet`, `event_editor_drawer`. Unaffected: gig response UI, `availability_prompt_modal`.
- **Rehearsals** — affected: `view_rehearsal_drawer`, `rehearsal_notes_sheet`. Unaffected: `rehearsal_availability_prompt_modal`.
- **Setlists** — affected: `song_notes_drawer`, `song_details_bottom_sheet`, `song_enrichment_review_sheet`, `setlist_picker_bottom_sheet`, `pause_creator`, `enrichment_selector_bottom_sheet`. Unaffected/deferred: `key_picker`, `tuning_picker`, `print_options`, `set_break_creator`, `custom_tuning_modal`.
- **Members** — affected: `band_member_detail_drawer`, `band_member_edit_drawer`, `contact_detail_drawer`. Unaffected: `role_management_sheet`.
- **Calendar** — affected: `day_detail_bottom_sheet`, `add_block_out_drawer`, `view_block_out_drawer`. Unaffected: `calendar_subscription_dialog`.
- **Financials** — affected: `add_financial_entry`, `financial_entry_details`, `gig_pay`. Unaffected: `financials_screen` DraggableScrollableSheet (that is a screen affordance, not one of the target sheets).
- **Auth / Session / PKCE** — unaffected.
- **Routing / Deep links** — unaffected.
- **Notifications** — unaffected.
- **Platforms** — iOS, Android, macOS, Web all affected identically. The scaffold is platform-agnostic; no `Platform.isX` branches.

## Regression Risk

**MEDIUM.**

Why not LOW:

- Wide surface (20 files) — many places for local layout to break during adoption.
- Sheets with animated entrances (`song_details_bottom_sheet`, `song_enrichment_review_sheet`, `setlist_picker_bottom_sheet`, `pause_creator`) wrap content in `AnimatedBuilder`. The scaffold must sit inside those wrappers, not swallow them, or the entrance animation dies.
- Sheets with `PopScope` unsaved-changes handling (`song_notes_drawer`, `song_details_bottom_sheet`, `song_enrichment_review_sheet`) must keep that behavior — the scaffold does not own PopScope.
- Sheets with keyboard-aware padding (`add_financial_entry`, `song_notes_drawer`, `song_details_bottom_sheet`, `pause_creator`, `event_editor_drawer`, `add_block_out_drawer`, `enrichment_selector_bottom_sheet`, `setlist_picker_bottom_sheet` create-new form) each use `viewInsets.bottom` in their own way. The scaffold reads `viewInsets` only to suppress collapse; it does not re-position the sheet. Each of those existing wrappers must remain in place.
- `setlist_picker_bottom_sheet.dart` has a _conditional_ footer — passing `footer: null` in list mode must not crash the scaffold or leave a dead gap.

Why not HIGH:

- No auth, no session, no routing, no init order, no config, no DB, no RLS, no RPC, no Edge Function changes.
- Graceful degradation — worst-case failure of the collapse logic is chrome staying fully visible, which is the current baseline.

## Engineer Task Breakdown

### Batch 1 — shared mechanism

1. Create `lib/components/ui/collapsing_sheet_scaffold.dart` with the public API and slot/scroll/animation/guard logic described under _Proposed Solution_.
2. Create `test/components/ui/collapsing_sheet_scaffold_test.dart` with the cases listed in _Verification Plan → Tier 1_.
3. Run `flutter analyze` — expect 0 errors.
4. Run `flutter test test/components/ui/collapsing_sheet_scaffold_test.dart` — all pass.

### Batch 2 — Pattern A adoption (10 files, footer collapse only)

Adopt in this order; each is a self-contained edit with no cross-file dependency. Preserve every existing outer wrapper (PopScope, entrance `AnimatedBuilder`, `Padding(bottom: viewInsets.bottom)`, outer `Container` decoration, `Material`).

5. `add_financial_entry_bottom_sheet.dart` (the sheet Tony named).
6. `gig_pay_bottom_sheet.dart`.
7. `financial_entry_details_bottom_sheet.dart`.
8. `view_block_out_drawer.dart`.
9. `view_gig_drawer.dart`.
10. `view_rehearsal_drawer.dart`.
11. `band_member_detail_drawer.dart`.
12. `contact_detail_drawer.dart`.
13. `enrichment_selector_bottom_sheet.dart`.
14. `pause_creator.dart`.

### Batch 3 — Pattern B adoption (10 files, header + footer collapse)

Extract the previously-fixed header widget block (title Padding + optional Divider) into the scaffold's `header` slot. The scaffold provides its own default drag handle unless the sheet needs a custom one — in which case pass it via `dragHandle`.

15. `day_detail_bottom_sheet.dart`.
16. `gig_notes_sheet.dart`.
17. `rehearsal_notes_sheet.dart`.
18. `song_notes_drawer.dart`.
19. `song_details_bottom_sheet.dart`.
20. `song_enrichment_review_sheet.dart`.
21. `setlist_picker_bottom_sheet.dart` (pass `footer: null` in list mode).
22. `add_block_out_drawer.dart`.
23. `band_member_edit_drawer.dart`.
24. `event_editor_drawer.dart`.

### Batch 4 — verification gate

25. Run `flutter analyze` — expect 0 errors across all modified files.
26. Run `flutter test` — full suite green (existing tests + new scaffold test).
27. macOS + iOS simulator visual smoke per _Verification Plan → Tier 2_.

## Verification Plan

### Tier 1 — pre-deploy widget tests (in `test/components/ui/collapsing_sheet_scaffold_test.dart`)

Every case pumps a `MaterialApp(home: Scaffold(body: CollapsingSheetScaffold(...)))` and dispatches synthetic notifications; no case invokes the scaffold via a real showModalBottomSheet flow.

- `collapses footer on reverse scroll` — pump scaffold with a tall `ListView` body (maxScrollExtent > 0). Dispatch `UserScrollNotification(direction: ScrollDirection.reverse, depth: 0)`. After `pumpAndSettle`, assert the footer's `SizeTransition` factor is 0.
- `reveals footer on forward scroll` — after collapse, dispatch `UserScrollNotification(direction: ScrollDirection.forward, depth: 0)`. Assert factor returns to 1.
- `reveals footer on scroll-end (idle)` — after collapse, dispatch `ScrollEndNotification`. Assert factor returns to 1 (this is the primary UX safeguard).
- `collapses header only when header slot is present` — same reverse-scroll dispatch, once with `header: someWidget`, once with `header: null`. In the first case both header and footer collapse; in the second case only the footer collapses and no header widget is rendered.
- `respects the 6-pixel anti-flicker threshold` — dispatch two `ScrollUpdateNotification(scrollDelta: 3, depth: 0)`; assert factor stays 1. Dispatch one `ScrollUpdateNotification(scrollDelta: 7, depth: 0)`; assert collapse begins.
- `ignores nested scroll notifications (depth != 0)` — dispatch a reverse `UserScrollNotification` with `depth: 1`. Assert factor stays 1.
- `is a no-op when body has no overflow` — dispatch `ScrollMetricsNotification` with `maxScrollExtent: 0`. Dispatch a reverse `UserScrollNotification`. Assert factor stays 1.
- `suppresses collapse when keyboard is open` — wrap scaffold in `MediaQuery` whose `viewInsets.bottom > 0`. Dispatch a reverse `UserScrollNotification`. Assert factor stays 1.
- `disables collapse under reduced motion` — wrap scaffold in `MediaQuery(data: mediaQueryData.copyWith(disableAnimations: true))`. Dispatch a reverse `UserScrollNotification`. Assert factor stays 1.
- `footer child is the untouched SheetFooter (safe-area preserved)` — pass a `SheetFooter` as `footer`, assert `find.byType(SheetFooter)` finds exactly one and its subtree is not re-wrapped in `SafeArea` by the scaffold.

Every widget test uses `tester.pumpAndSettle` after dispatching notifications and asserts against `AnimationController.value` (via the `SizeTransition`'s `sizeFactor.value`) — no time-based flakiness.

### Tier 2 — per-sheet visual smoke (macOS + iOS simulator, Engineer runs after Batch 3)

For each of the 20 modified sheets:

- Open the sheet with content that overflows the sheet's max height.
- Scroll down — verify the header (Pattern B only) collapses smoothly upward, the footer collapses smoothly downward, no dead gap, body fills freed space.
- Stop scrolling — verify the footer immediately reveals (Save/Update/Add button reachable).
- Scroll up — verify header and footer immediately reveal.
- Open the sheet with content that fits — verify no chrome ever collapses.
- Sheets with text fields (`add_financial_entry`, `event_editor`, `add_block_out`, `song_notes`, `song_details`, `song_enrichment_review`, `pause_creator`, `setlist_picker` create-new form, `enrichment_selector`, `band_member_edit`) — focus a text field, verify chrome stays fully visible while typing.
- Sheets with PopScope (`song_notes_drawer`, `song_details`, `song_enrichment_review`) — back-gesture / hardware back still shows the unsaved-changes dialog.
- Sheets with entrance animations (`song_details`, `song_enrichment_review`, `setlist_picker`, `pause_creator`) — entrance still plays smoothly.
- Enable Settings → Accessibility → Reduce Motion. Reopen a Pattern B sheet, scroll — verify chrome stays visible.

### Tier 2 — analyzer & test suite

- `flutter analyze` — 0 errors.
- `flutter test` — full suite green.

## QA Regression Areas

- All 20 modified sheets: open, scroll, dismiss, save, cancel.
- Keyboard interaction on every sheet with text input (10 of the 20) — chrome must not disappear during typing.
- Entrance animations on `song_details_bottom_sheet`, `song_enrichment_review_sheet`, `setlist_picker_bottom_sheet`, `pause_creator`.
- PopScope-guarded unsaved-changes flows on `song_notes_drawer`, `song_details_bottom_sheet`, `song_enrichment_review_sheet`.
- Destructive footer button in `add_financial_entry_bottom_sheet` — reveals with footer, disables/re-enables with the scaffold's chrome.
- Conditional footer in `setlist_picker_bottom_sheet` list mode — no crash, no dead gap.
- Reduce Motion accessibility setting — chrome stays visible on every Pattern B sheet.
- Safe area on notched devices (iPhone 14 Pro simulator) — footer's own bottom safe-area padding still applied.
- The 3 deferred DraggableScrollableSheet pickers (key/tuning/print-options), the dialog, and the 3 not-applicable sheets — smoke test they still open, still dismiss, still save (they must be visibly unchanged).

## Rollout Strategy

- Single PR: scaffold + test (Batch 1) + Pattern A adoptions (Batch 2) + Pattern B adoptions (Batch 3) + verification pass (Batch 4).
- No feature flag. If any single sheet needs to opt out at PR review time, Engineer can pass `header: null` (Pattern A behavior — footer-only collapse) or revert that individual sheet's file — this is possible because each adoption is a self-contained edit with no cross-file coupling.
- The change gracefully degrades: worst-case scaffold failure is chrome staying fully visible, which is the current baseline.

## Out of Scope

- The 3 DraggableScrollableSheet pickers (`key_picker`, `tuning_picker`, `print_options`) — they have their own draggable-height behavior orthogonal to this collapsing model. Revisit as a follow-up feature.
- `calendar_subscription_dialog.dart` (a dialog, not a sheet) and the 3 not-applicable sheets — not modified.
- Any change to `SheetFooter` public API.
- Any change to init order, `--dart-define` config, PKCE auth, Supabase RLS/RPC/Edge Functions, deep links, or platform-specific entitlements.
- Documentation of the new scaffold in `docs/reference/` — leave to a follow-up doc PR unless explicitly requested; Engineer keeps this PR focused.
