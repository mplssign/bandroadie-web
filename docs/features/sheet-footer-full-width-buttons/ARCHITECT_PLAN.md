# ARCHITECT_PLAN — sheet-footer-full-width-buttons

## Feature Slug
`sheet-footer-full-width-buttons`

## Feature Title
Make the footer primary and secondary (Cancel) buttons each span the full width of their half of the footer

## Problem Summary
In the shared sheet/drawer footer widget (`SheetFooter`), the primary (filled
rose) and secondary (Cancel, text-style) buttons currently render at their
intrinsic content width and are pushed to opposite ends of the footer row via
`MainAxisAlignment.spaceBetween`. The design calls for each button to fill its
half of the footer: Cancel = full width of the LEFT half, primary = full width
of the RIGHT half, 50/50 split with an inter-button gap. This is a shared
component (adopted by ~27 sheets/drawers per the standardization in PR #241),
so the layout change belongs in the shared widget — not in any adopter.

## Root Cause (HIGH confidence)
Confirmed by reading `lib/components/ui/sheet_footer.dart` lines 66–79.

The primary/cancel row is built as:

```dart
final row = Row(
  mainAxisAlignment: onCancel != null
      ? MainAxisAlignment.spaceBetween
      : MainAxisAlignment.end,
  children: [
    if (onCancel != null)
      AppButton(
        label: cancelLabel,
        onPressed: primaryIsLoading ? null : onCancel,
        variant: AppButtonVariant.text,
      ),
    primary,
  ],
);
```

Both `AppButton` children are given no width constraint, so they size to their
intrinsic content. `MainAxisAlignment.spaceBetween` pins them to the row's two
ends, leaving empty space in the middle. Nothing forces either child to occupy
half the available width. This is a pure layout defect — the fix is structural
(`Expanded` + explicit `fullWidth: true`), not stylistic.

## Existing System Analysis
- `AppButton` (`lib/components/ui/app_button.dart`) already exposes a
  `fullWidth: bool` prop that wraps the underlying `FButton` in a
  `SizedBox(width: double.infinity, child: FButton(...))`. This is the correct
  primitive: inside a tight width constraint (which `Expanded` provides), the
  `double.infinity` is clamped to the parent constraint, so the button
  reliably fills the Expanded slot regardless of `FButton`'s internal
  intrinsic sizing behavior.
- The destructive-action row (when both `destructiveLabel` and `onDestructive`
  are provided) already uses `AppButton(..., fullWidth: true)` inside a
  `Column`. The primary/cancel row is the only part that currently sizes to
  content. The destructive row is unrelated to this change and must stay as-is.
- Verified via `grep`: `SheetFooter(` is used in 27 adopter sheets/drawers
  (`add_block_out_drawer.dart`, `event_editor_drawer.dart` — used by both Add
  Event and Edit Gig — `view_gig_drawer.dart`, `financial_entry_details_bottom_sheet.dart`,
  `song_details_bottom_sheet.dart`, etc.). Every call site uses the public API
  only (`primaryLabel`, `onPrimary`, `onCancel`, optional destructive props);
  none reference row/layout internals. The layout change propagates
  automatically with zero adopter edits.
- Existing widget test file `test/components/ui/sheet_footer_test.dart` covers
  variants, counts, labels, loading state, and callbacks — but has zero layout
  assertions today. The Expanded structure needs to be pinned down by tests so
  a future edit can't silently regress it.

## Proposed Solution
Restructure only the primary/cancel `Row` inside `SheetFooter` so:

1. When `onCancel != null` (both actions present):
   - Wrap the cancel `AppButton` in `Expanded`, with `fullWidth: true` on the
     `AppButton` itself for defense-in-depth against Forui `FButton`'s
     intrinsic sizing.
   - Insert a `SizedBox(width: Spacing.space12)` gap between the two.
   - Wrap the primary `AppButton` in `Expanded`, also with `fullWidth: true`.
   - Drop the `MainAxisAlignment.spaceBetween` — Expanded pair splits the row
     naturally 50/50.
2. When `onCancel == null` (lone primary — e.g. view-only "Close"/"Done",
   `Edit Entry`, single-action sheets):
   - The lone primary spans the FULL footer width (via `AppButton(fullWidth: true)`
     with no surrounding Expanded, or a single Expanded — either works;
     simplest is `fullWidth: true` alone, since the parent Container already
     provides a bounded width via padding). This is the standard mobile
     bottom-sheet pattern and matches the destructive row's existing
     full-width behavior in this same widget. Decided without Tony's input:
     the alternative (primary hugging the right half with an empty left half)
     is inconsistent with the destructive row already in this widget and
     inconsistent with Material Design + iOS HIG guidance for single-action
     confirmation footers. This is a UX-best-practice call, not a genuine
     product fork.

Preserved as-is:
- The outer `Container` decoration (top border + shadow, `context.colors.surface`).
- Safe-area padding (`MediaQuery.of(context).padding.bottom + 12`).
- Horizontal padding `Spacing.pagePadding` and top padding `12`.
- The destructive-row-above-primary-row branch (unchanged structurally).
- Cancel remains `AppButtonVariant.text`; primary remains
  `AppButtonVariant.primary` (filled rose).
- Cancel is still hidden entirely when `onCancel == null` (no visible ghost
  slot on the left).
- `primaryIsLoading` still disables both buttons and shows the spinner on
  primary; `primaryIcon` still renders on primary.

## Database Impact
n/a

## Flutter Architecture Changes
None. No new controllers, providers, repositories, or services. No public
API change to `SheetFooter` (all existing named parameters keep their names,
types, defaults, and semantics) or to `AppButton`. This is a layout-internals
edit inside `SheetFooter.build()` only.

## Files to Create
n/a

## Files to Modify
- `lib/components/ui/sheet_footer.dart` — restructure the primary/cancel
  `Row` per the Proposed Solution. Everything outside that row (destructive
  branch, container decoration, padding, safe-area math) is untouched.
- `test/components/ui/sheet_footer_test.dart` — extend with layout
  assertions: (a) when both actions present, both cancel and primary are
  each wrapped in an `Expanded`; (b) an inter-button gap widget renders
  between them; (c) when `onCancel == null`, the lone primary renders with
  `fullWidth: true` and is NOT wrapped in an `Expanded`. Existing tests
  (variant, count, label, loading, callback) stay as-is — the Expanded
  restructure must not break any of them.

## Files Off-Limits
- `lib/components/ui/app_button.dart` — public API stays untouched. We're
  consuming the existing `fullWidth` prop, not changing it.
- The 27 adopter sheets/drawers listed above (`event_editor_drawer.dart`
  including both Add Event and Edit Gig code paths,
  `view_gig_drawer.dart`, `add_block_out_drawer.dart`,
  `view_block_out_drawer.dart`, `calendar_subscription_dialog.dart`,
  `day_detail_bottom_sheet.dart`, `band_member_detail_drawer.dart`,
  `band_member_edit_drawer.dart`, `contact_detail_drawer.dart`,
  `add_financial_entry_bottom_sheet.dart`,
  `financial_entry_details_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart`,
  `gig_notes_sheet.dart`, `role_management_sheet.dart`,
  `rehearsal_notes_sheet.dart`, `view_rehearsal_drawer.dart`,
  `custom_tuning_modal.dart`, `key_picker_bottom_sheet.dart`,
  `pause_creator.dart`, `print_options_bottom_sheet.dart`,
  `set_break_creator.dart`, `setlist_picker_bottom_sheet.dart`,
  `song_details_bottom_sheet.dart`, `song_enrichment_review_sheet.dart`,
  `song_notes_drawer.dart`, `tuning_picker_bottom_sheet.dart`,
  `enrichment_selector_bottom_sheet.dart`) — no per-sheet changes required.
  If any adopter turns out to need tweaks, that's a signal something else is
  wrong; stop and report rather than silently editing them.
- `lib/main.dart`, `supabase/**`, `pubspec.yaml`, `pubspec.lock`,
  `analysis_options.yaml`, platform manifests.

## Change Budget
- Expected net line delta:
  - `lib/components/ui/sheet_footer.dart`: **+8 to +12 lines** (Row body
    grows from ~11 lines to ~20 lines to add Expanded wrappers, the gap
    SizedBox, and `fullWidth: true` on both AppButtons).
  - `test/components/ui/sheet_footer_test.dart`: **+30 to +50 lines** for
    2–3 new `testWidgets` cases covering Expanded structure and the lone
    primary full-width case. Existing tests should remain unchanged.
- Expected new files: **0**
- Expected new public classes/methods: **0**
- Expected new dependencies: **0**

## System Impact Map
- Gigs: unaffected (Edit Gig footer inherits new layout — visual change only, same actions).
- Rehearsals: unaffected (same).
- Setlists: unaffected (same).
- Members: unaffected (same).
- Auth: unaffected.
- Routing: unaffected.
- Notifications: unaffected.
- Platforms (iOS/Android/macOS/Web): all inherit the change identically via the
  shared widget. No platform-conditional code touched. Dark mode only (as with
  the entire app).

## Regression Risk
**LOW.**
- No auth, session, routing, init-order, or DB code touched.
- No public API change on `SheetFooter` or `AppButton`.
- All 27 adopter sites use only the public API — the layout change is
  purely internal to `SheetFooter.build()`.
- The destructive row (which is the higher-risk / higher-blast-radius
  branch) is not being touched.
- The only user-observable behavior change is exactly the requested one:
  buttons stretch to fill their half of the footer instead of hugging
  content.

## Engineer Task Breakdown
1. In `lib/components/ui/sheet_footer.dart`, replace the current
   primary/cancel `Row` construction (lines ~66–79) with a layout that:
   - When `onCancel != null`: `Row(children: [Expanded(child: AppButton(cancel..., fullWidth: true)), SizedBox(width: Spacing.space12), Expanded(child: AppButton(primary..., fullWidth: true))])`.
   - When `onCancel == null`: a single `AppButton(primary..., fullWidth: true)` (no `Row`, no `Expanded` — the parent Container's padding already bounds the width).
   - Remove the now-redundant `MainAxisAlignment` argument.
   - Keep the existing `primary` local variable but add `fullWidth: true` to its constructor; keep the `AppButtonVariant.text` cancel with `fullWidth: true`.
2. Keep the destructive-branch `Column` untouched — it already renders a full-width destructive above whichever primary/cancel widget the code now returns; verify by inspection it still composes correctly with the new no-cancel single-widget form.
3. In `test/components/ui/sheet_footer_test.dart`, add three `testWidgets` cases:
   - "primary and cancel are each wrapped in Expanded when both present" — assert `find.byType(Expanded)` finds exactly 2 within the footer, and that each Expanded's direct child is an `AppButton`.
   - "inter-button gap renders between cancel and primary" — assert a `SizedBox` with `width == Spacing.space12` sits between the two Expandeds (find via widget tree traversal or `find.byWidgetPredicate`).
   - "lone primary spans full footer width when onCancel is null" — assert `find.byType(Expanded)` finds none, the sole `AppButton` has `fullWidth == true`, and no `Row` is rendered as a direct child of the footer's inner Container.
4. Do NOT edit any adopter sheet. Do NOT touch `app_button.dart`.
5. Run `flutter analyze` and `flutter test test/components/ui/sheet_footer_test.dart` — both must pass before opening the PR.

## Verification Plan
**Tier 1 (pre-deploy):**
- `flutter analyze` — must be clean (0 issues).
- `flutter test test/components/ui/sheet_footer_test.dart` — all existing
  tests plus the 3 new layout tests pass.
- Visual/manual (dev build on macOS or web, dark mode):
  - Open **Add Event** drawer (`event_editor_drawer.dart` — add path):
    footer shows Cancel filling the left half and Save filling the right
    half, with a small gap between them.
  - Open **Edit Gig** drawer (`event_editor_drawer.dart` — edit path):
    same 50/50 layout; when the destructive "Delete" action is present,
    it stays as a full-width row above the Cancel/Save row.
  - Open a lone-primary sheet (e.g. a view-only drawer that uses
    `SheetFooter(primaryLabel: 'Close', onPrimary: …)` with no `onCancel`):
    the primary spans the full footer width.
- Spot-check one bottom sheet (`song_details_bottom_sheet.dart`) and one
  dialog (`calendar_subscription_dialog.dart`) to confirm the change looks
  right in a shorter footer context too.

**Tier 2 (post-deploy):** n/a — this is a pure client-side layout tweak with
no backend, migration, or edge-function surface.

## QA Regression Areas
- Every screen that opens a sheet or drawer with a footer — QA should confirm
  the primary/cancel layout looks right and nothing else moved. Priority list
  matches the visual/manual spot-checks above (Add Event, Edit Gig, one lone-
  primary sheet, one bottom sheet, one dialog). Full 27-sheet sweep is not
  required — if the shared widget is right, all adopters inherit it correctly.
- Confirm destructive-action sheets (e.g. `view_block_out_drawer.dart`,
  `event_editor_drawer.dart` in edit mode) still show the destructive row
  full-width above the primary/cancel row.
- Confirm `primaryIsLoading` still shows the spinner on the primary side and
  disables both buttons.
- Confirm dark-mode-only styling is unchanged (rose primary, ghost/text cancel).

## Rollout Strategy
Standard feature branch → PR → merge to `main`. No feature flag, no staged
rollout, no migration coordination. Layout change ships in the next web
deploy / native build.

## Out of Scope
- Any change to `AppButton`'s public API or internal layout logic.
- The destructive action row structure (stays full-width above the primary/
  cancel row).
- Per-sheet layout tweaks in any of the 27 adopters.
- Any change to spacing tokens, colors, or typography in
  `lib/app/theme/design_tokens.dart`.
- Scroll-collapse / sticky-footer behavior (reverted in `1d65e98` — not
  relevant to this change).
- Light-mode styling (app is dark-mode only).
