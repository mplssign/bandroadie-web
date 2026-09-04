# ARCHITECT_PLAN — standardize-sheet-drawer-footers

## Feature Slug
`standardize-sheet-drawer-footers`

## Feature Title
Standardize sheet/drawer footer actions; remove event-type and date/time from the
Edit Gig footer

## Problem Summary
Two related UI problems:

1. **Edit Gig footer clutter.** The event editor drawer's sticky footer renders a
   left-aligned "summary" line (event type + date + time + duration, e.g.
   `Gig · Sep 3 · 8:00 PM · 2h`) alongside the Cancel and Update buttons. That
   duplicates fields the user already sees in the form and pushes the buttons
   into a narrower slot.

2. **Inconsistent footer conventions across sheets/drawers.** Across ~27
   modal sheets/drawers, the sticky-action footer varies on every dimension
   that matters: layout (Row vs. Column), button widget (`OutlinedButton`,
   `FilledButton`, `ElevatedButton`, raw `TextButton`, `AppButton` with
   `primary`/`secondary`/`outlined`/`text`/`destructive` variants), and
   left/right placement of the primary vs. cancel button. The stated
   convention — primary filled on the right, Cancel text on the left — is
   only partially followed.

## Root Cause
**Confidence: HIGH** — confirmed by reading every affected file.

There is no shared footer widget for modal sheets/drawers. Every sheet
open-codes its own `Container` (border + shadow + padding + SafeArea) plus
its own button arrangement, so each sheet locks in whatever pattern the
author reached for at the time it was written. The current top-level
convention lives only in prose; nothing in code enforces it, so drift is
guaranteed.

Two smaller root causes stacked on top of that:

- The Edit Gig footer specifically renders `_buildSummaryText()` (line 3131 of
  [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L3131))
  as an `Expanded(Text(...))` inside the footer `Row`. That text is
  produced by `_buildSummaryText()` at line 3190 by concatenating
  `_eventType.displayName` + formatted `_selectedDate` + hour/minute/AM-PM +
  duration. It's redundant with the form fields above it.
- A few sheets that predate the convention still use non-primary variants
  (`AppButtonVariant.secondary`, plain `OutlinedButton`, `ElevatedButton`)
  or place the primary button on the left / on top rather than on the right.

## Existing System Analysis

### Facade + design tokens already in place
- [lib/components/ui/app_button.dart](lib/components/ui/app_button.dart) — `AppButton` +
  `AppButtonVariant.{primary, secondary, text, outlined, destructive}` (Forui
  `FButton` under the hood). This is the single UI wrapper for buttons.
- [lib/components/ui/app_bottom_sheet.dart](lib/components/ui/app_bottom_sheet.dart) —
  `showAppBottomSheet` (Forui `FSheet` under the hood).
- [lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart) — `Spacing.pagePadding`
  (16), `Spacing.space12`, `Spacing.buttonRadius` (8), `AppColors.primary`
  (`#FF2056`), `AppColors.error`.
- [lib/components/ui/README.md](lib/components/ui/README.md) — documents the 15 existing
  UI facade wrappers.

### Full sheet/drawer footer inventory (27 in scope)

All rows are files under `lib/`. "Layout" = current arrangement of the
sticky/final action buttons. "Deviation" = how it differs from the target
convention.

#### Category A — editors: Save/Update + Cancel (14)

| # | File | Current footer | Deviation from target |
|---|------|----------------|----------------------|
| 1 | [features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L3121) `_buildStickyFooter` | Row: `Expanded(Text(_buildSummaryText))`, `OutlinedButton Cancel`, `ElevatedButton` primary (rose `#FB2C5A`, hardcoded). View-only mode: single full-width `OutlinedButton "Close"`. | Summary text must go; Cancel must switch from outlined to text; primary must use `AppButton primary`; view-only single button must become primary right. |
| 2 | [features/calendar/widgets/add_block_out_drawer.dart](lib/features/calendar/widgets/add_block_out_drawer.dart#L771) `_buildBottomButtons` | Row: `Expanded AppButton outlined Cancel`, `Expanded AppButton primary Save/Update`. Destructive `AppButton destructive "Delete Block Out"` rendered separately in body just above the footer container (line 645, `_buildDeleteButton`). | Cancel must switch from outlined to text; destructive should move into the footer widget. |
| 3 | [features/contacts/widgets/band_member_edit_drawer.dart](lib/features/contacts/widgets/band_member_edit_drawer.dart#L515) `_buildFixedBottomActions` | Column: `AppButton primary Save fullWidth`, then `AppButton text Cancel` centered below. "Remove from band" `AppButton destructive` lives mid-body next to the role toggle, not adjacent to the footer. | Layout must switch to Row with Cancel left, Save right. Body destructive stays where it is (semantic body action, not a footer action). |
| 4 | [features/members/widgets/role_management_sheet.dart](lib/features/members/widgets/role_management_sheet.dart#L460) `_buildFooter` | Same as #3. | Same as #3. |
| 5 | [features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L481) inline footer | Row: `Expanded OutlinedButton Cancel`, `Expanded FilledButton Save`. Destructive is a raw red `TextButton "Delete income/expense"` in a Column below, gated by `canDeleteFinancials`. | Cancel outlined → text; equal-Expanded layout → primary right; destructive should move into footer widget destructive slot (see edge case #3). |
| 6 | [features/financials/widgets/gig_pay_bottom_sheet.dart](lib/features/financials/widgets/gig_pay_bottom_sheet.dart#L200) `_buildFixedBottomActions` | Normal: Column with `SizedBox fullWidth FilledButton Save`, then `TextButton Cancel` below. View-only: single full-width `OutlinedButton "Close"`. | Layout must switch to Row (Cancel text left, Save primary right); view-only "Close" must become primary right. |
| 7 | [features/setlists/widgets/print_options_bottom_sheet.dart](lib/features/setlists/widgets/print_options_bottom_sheet.dart#L875) inline footer | Row: `Expanded AppButton outlined "Save layout"`, `Expanded AppButton primary "Preview"`. **No Cancel.** | Edge case — see "Edge cases" §3 below. |
| 8 | [features/setlists/widgets/song_details_bottom_sheet.dart](lib/features/setlists/widgets/song_details_bottom_sheet.dart#L1468) `_buildFixedBottomActions` | Column: `AppButton primary Save/Done fullWidth`, `AppButton text Cancel/Close`. Includes a "✓ Enrichment saved automatically" success text row when `_justEnriched`. | Layout Column → Row (Cancel text left, Save primary right). Success text stays above the footer widget. |
| 9 | [features/setlists/widgets/song_enrichment_review_sheet.dart](lib/features/setlists/widgets/song_enrichment_review_sheet.dart#L445) inline footer | Column: `AppButton primary Save fullWidth`, `AppButton text Cancel`. | Layout Column → Row. |
| 10 | [features/setlists/widgets/song_notes_drawer.dart](lib/features/setlists/widgets/song_notes_drawer.dart#L186) `_buildFooter` | Column: primary (`Save` when editing, `Edit` when viewing) full-width, then `AppButton text Cancel`. | Layout Column → Row. |
| 11 | [features/setlists/widgets/custom_tuning_modal.dart](lib/features/setlists/widgets/custom_tuning_modal.dart#L432) `_buildActionButtons` | Row: `Expanded AppButton outlined Cancel`, `Expanded flex:2 AppButton **secondary** "Save Tuning"` (grey pill, not rose). | Cancel outlined → text; primary must switch from `secondary` to `primary` (rose). |
| 12 | [features/setlists/widgets/tuning_picker_bottom_sheet.dart](lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart#L785) footer | Column: `AppButton primary Save fullWidth`, `AppButton text Cancel`. | Layout Column → Row. |
| 13 | [features/setlists/widgets/key_picker_bottom_sheet.dart](lib/features/setlists/widgets/key_picker_bottom_sheet.dart#L295) footer | Column: `AppButton primary Save fullWidth`, `AppButton text Cancel`. | Layout Column → Row. |
| 14 | [features/setlists/widgets/setlist_picker_bottom_sheet.dart](lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart#L504) create-new mode | Row: `Expanded AppButton outlined Cancel`, `Expanded AppButton primary "Create & Add"`. Default (picker) mode has no footer. | Cancel outlined → text. |

#### Category B — view drawers: Done + optional Edit (5)

| # | File | Current footer | Deviation from target |
|---|------|----------------|----------------------|
| 15 | [features/gigs/widgets/view_gig_drawer.dart](lib/features/gigs/widgets/view_gig_drawer.dart#L497) | Column: `AppButton primary Done fullWidth`, then (if `canEdit`) `AppButton text Edit fullWidth` below. | Column → Row: `Edit` text-button in the secondary/left slot, `Done` primary on the right. See edge case §2. |
| 16 | [features/rehearsals/widgets/view_rehearsal_drawer.dart](lib/features/rehearsals/widgets/view_rehearsal_drawer.dart#L274) | Same as #15. | Same as #15. |
| 17 | [features/calendar/widgets/view_block_out_drawer.dart](lib/features/calendar/widgets/view_block_out_drawer.dart#L165) | Same as #15. | Same as #15. |
| 18 | [features/contacts/widgets/band_member_detail_drawer.dart](lib/features/contacts/widgets/band_member_detail_drawer.dart#L258) | Same as #15. | Same as #15. |
| 19 | [features/contacts/widgets/contact_detail_drawer.dart](lib/features/contacts/widgets/contact_detail_drawer.dart#L178) | Same as #15. | Same as #15. |

#### Category C — single-action sheets (5)

| # | File | Current footer | Deviation from target |
|---|------|----------------|----------------------|
| 20 | [features/gigs/widgets/gig_notes_sheet.dart](lib/features/gigs/widgets/gig_notes_sheet.dart#L105) | Single `AppButton primary Done fullWidth`. No Cancel. | Normalize container styling via shared widget. |
| 21 | [features/rehearsals/widgets/rehearsal_notes_sheet.dart](lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart#L101) | Same as #20. | Same as #20. |
| 22 | [features/calendar/widgets/day_detail_bottom_sheet.dart](lib/features/calendar/widgets/day_detail_bottom_sheet.dart#L207) | Conditional `AppButton primary "Add Event" fullWidth` only when `onAddEvent != null`. Sheet dismisses via header X. | Normalize container styling; keep single-action + no-cancel semantics. |
| 23 | [features/financials/widgets/financial_entry_details_bottom_sheet.dart](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart#L165) | Single `ElevatedButton.icon "Edit Entry" fullWidth` (rose fill hardcoded). | Switch to `AppButton` via shared widget; keep icon; normalize styling. |
| 24 | [features/calendar/widgets/calendar_subscription_dialog.dart](lib/features/calendar/widgets/calendar_subscription_dialog.dart#L233) | Single `AppButton text "Close"`. No primary. | Rename to `Done` and promote to primary on the right. See edge case §4. |

#### Category D — mini-creators with single "Add" action (2)

| # | File | Current footer | Deviation from target |
|---|------|----------------|----------------------|
| 25 | [features/setlists/widgets/pause_creator.dart](lib/features/setlists/widgets/pause_creator.dart#L396) | `AppButton secondary "Add Pause" fullWidth`. No Cancel; header X handles dismiss. | Switch variant `secondary` → `primary` (matches convention); normalize container. |
| 26 | [features/setlists/widgets/set_break_creator.dart](lib/features/setlists/widgets/set_break_creator.dart#L233) | `AppButton secondary "Add Set Break" fullWidth`. No Cancel; header X handles dismiss. | Same as #25. |

#### Category E — enrichment selector (1, inline-not-sticky)

| # | File | Current footer | Deviation from target |
|---|------|----------------|----------------------|
| 27 | [features/songs/widgets/enrichment_selector_bottom_sheet.dart](lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart#L176) | Not a sticky footer — action buttons live at the end of the scrollable body: `FilledButton "Enrich Songs" fullWidth` then `TextButton "Cancel"` (rose text) below. | Migrate to the shared footer widget (Row, Cancel text left, primary Enrich Songs right). |

### Explicitly out-of-scope files
- [features/lyrics/widgets/lyrics_editor_sheet.dart](lib/features/lyrics/widgets/lyrics_editor_sheet.dart#L395) uses an iOS-style **header** (Cancel top-left, "Edit Lyrics" title, Save top-right), not a footer. The feature spec targets footers.
- [features/contacts/widgets/contact_form_screen.dart](lib/features/contacts/widgets/contact_form_screen.dart#L195), [features/contacts/widgets/venue_form_screen.dart](lib/features/contacts/widgets/venue_form_screen.dart#L302), [features/calendar/one_calendar_settings_screen.dart](lib/features/calendar/one_calendar_settings_screen.dart) are full-screen routes (`AppScaffold` + `AppAppBar` with `Save` as an app-bar action), not modal sheets/drawers.
- Picker sheets that dismiss on tile-tap and have no action-button footer: `_CatalogSortSheet` and `_ShareFormatSheet` in [features/setlists/setlist_detail_screen.dart](lib/features/setlists/setlist_detail_screen.dart#L3229), `_SavingsSheet` in [features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart#L196), the backup/restore and image-source sheets in [features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart#L546), `_showNavigationAppPicker` in [features/contacts/widgets/venue_detail_screen.dart](lib/features/contacts/widgets/venue_detail_screen.dart#L284), `TipsAndTricksOverlay` in [components/overlays/tips_and_tricks_overlay.dart](lib/components/overlays/tips_and_tricks_overlay.dart#L244), the "Technical Details" info sheet in [features/home/home_screen.dart](lib/features/home/home_screen.dart#L635).
- All dialogs (`showAppDialog`, `AlertDialog`, `showDialog`) — the feature spec explicitly scopes to sheets/drawers, and dialog action rows already follow the app-wide `AlertDialog` conventions.

## Proposed Solution

Introduce one small shared widget, `SheetFooter`, at
[lib/components/ui/sheet_footer.dart](lib/components/ui/sheet_footer.dart) that
packages the standard footer container plus the standard button layout, and
migrate every in-scope sheet/drawer to use it.

Rationale for the shared-widget approach over per-file normalization:

1. **The problem is drift.** The current footers already implement roughly the
   same idea 5 different ways. Fixing them in place without a shared widget
   solves today's inconsistency but leaves the next sheet author free to
   introduce a 6th variant. A ~100-line widget prevents that.
2. **Code shrinks, not grows.** Each existing footer is 25–60 lines of
   Container/decoration/padding/Row-or-Column/button boilerplate. The
   `SheetFooter` widget absorbs all of that. Estimated net delta across the
   27 files is negative.
3. **It matches the existing pattern.** The `lib/components/ui/` folder is the
   established home for exactly this kind of thin facade (`AppButton`,
   `AppBottomSheet`, `AppDialog`, `AppCard`, …). Adding `SheetFooter` there is
   consistent with the existing architecture, not a new abstraction category.

### Target convention (exact)

**Container:**
- Background: `context.colors.surface`
- Top border: `Border(top: BorderSide(color: context.colors.border.withValues(alpha: 0.5)))`
- Shadow: `[BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: Offset(0, -2))]`
- Padding: `EdgeInsets.only(left: Spacing.pagePadding, right: Spacing.pagePadding, top: 12, bottom: MediaQuery.of(context).padding.bottom + 12)`

**Primary action:**
- `AppButton` with `variant: AppButtonVariant.primary` (Forui filled rose `#FF2056`)
- Right-aligned in the footer row
- Supports `isLoading` (spinner replaces label, `onPressed` gated to `null`)
- Auto-disabled when its `onPressed` is `null`

**Secondary (Cancel-slot) action:**
- `AppButton` with `variant: AppButtonVariant.text` (Forui `ghost` — no fill, no border)
- Left-aligned in the footer row
- Optional (omit for single-action sheets); when omitted, the primary right-anchors on its own

**Destructive (optional) action:**
- `AppButton` with `variant: AppButtonVariant.destructive` (Forui filled destructive)
- Full-width in a row **above** the primary/secondary row (separated by `SizedBox(height: Spacing.space12)`)
- Only shown when a caller supplies both `destructiveLabel` and `onDestructive`

**Row layout:**
- `Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [cancelSlot, primary])`
- When `onCancel == null`, the row uses `MainAxisAlignment.end` so the primary right-anchors

### `SheetFooter` API

```dart
class SheetFooter extends StatelessWidget {
  const SheetFooter({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,          // null disables primary
    this.primaryIsLoading = false,
    this.primaryIcon,                 // optional leading icon (used by Financial Entry Details)
    this.cancelLabel = 'Cancel',
    this.onCancel,                    // null hides the cancel slot
    this.destructiveLabel,            // null hides destructive
    this.onDestructive,
    this.destructiveIsLoading = false,
  });
  // ... fields ...
}
```

No new providers, controllers, repositories, or services. Widget is a pure
`StatelessWidget` that composes existing `AppButton` calls.

## Database Impact
n/a — client-side UI only. No schema, RLS, RPC, edge-function, migration, or
seed changes.

## Flutter Architecture Changes

- Adds one new widget file in the existing `lib/components/ui/` facade
  directory. Same architectural layer as `AppButton`, `AppBottomSheet`,
  `AppDialog` — no new category.
- No changes to state management (Riverpod), routing, deep-linking, auth,
  init order, or platform-conditional code.
- No new dependencies in `pubspec.yaml`.
- No changes to `docs/reference/general/RUNTIME_CONFIG.md` or
  `docs/reference/general/AI_DECISIONS.md` — this change doesn't affect init
  order, config surface, or any architectural decision recorded there.

## Files to Create

1. [lib/components/ui/sheet_footer.dart](lib/components/ui/sheet_footer.dart) — the `SheetFooter` widget per the API above.
2. [test/components/ui/sheet_footer_test.dart](test/components/ui/sheet_footer_test.dart) — widget tests (see Verification Plan Tier 1).

## Files to Modify

**27 sheet/drawer files, plus 1 doc:**

Category A — editors (14):
1. [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) — remove `_buildSummaryText()` call **and** its method definition; remove `_buildPrimaryActionButton()`; rewrite `_buildStickyFooter()` to return a `SheetFooter`. View-only mode: `SheetFooter(primaryLabel: 'Close', onPrimary: pop-and-onCancelled, onCancel: null)`. Normal mode: `SheetFooter(primaryLabel: _primaryButtonLabel, onPrimary: canSave ? _handleSave : null, primaryIsLoading: _isSaving, onCancel: _isSaving ? null : cancel-handler)`.
2. [lib/features/calendar/widgets/add_block_out_drawer.dart](lib/features/calendar/widgets/add_block_out_drawer.dart) — replace both `_buildBottomButtons()` branches with `SheetFooter`; move `_buildDeleteButton()` into `SheetFooter.destructiveLabel/onDestructive` and delete the standalone helper.
3. [lib/features/contacts/widgets/band_member_edit_drawer.dart](lib/features/contacts/widgets/band_member_edit_drawer.dart) — replace `_buildFixedBottomActions()` with `SheetFooter`. Leave the mid-body "Remove from band" `AppButton destructive` (line 491) in place; it's a body action, not a footer action.
4. [lib/features/members/widgets/role_management_sheet.dart](lib/features/members/widgets/role_management_sheet.dart) — same as #3.
5. [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart) — replace the inline `Row(Cancel, Save)` and the `Column` "Delete income/expense" block with a single `SheetFooter` that carries the destructive slot when `widget.initialEntry != null && widget.onDelete != null && perms.canDeleteFinancials`.
6. [lib/features/financials/widgets/gig_pay_bottom_sheet.dart](lib/features/financials/widgets/gig_pay_bottom_sheet.dart) — replace both view-only and normal branches with `SheetFooter`.
7. [lib/features/setlists/widgets/print_options_bottom_sheet.dart](lib/features/setlists/widgets/print_options_bottom_sheet.dart) — `SheetFooter(primaryLabel: 'Preview', onPrimary: _handlePreview, cancelLabel: 'Save layout', onCancel: _showSaveLayoutDialog)`. See edge case §3.
8. [lib/features/setlists/widgets/song_details_bottom_sheet.dart](lib/features/setlists/widgets/song_details_bottom_sheet.dart) — replace `_buildFixedBottomActions()` with `SheetFooter`. Keep the `_justEnriched` "✓ Enrichment saved automatically" success line just above the `SheetFooter`. Read-only mode uses `SheetFooter(primaryLabel: 'Close', onPrimary: pop, onCancel: null)`.
9. [lib/features/setlists/widgets/song_enrichment_review_sheet.dart](lib/features/setlists/widgets/song_enrichment_review_sheet.dart) — replace the inline footer with `SheetFooter`.
10. [lib/features/setlists/widgets/song_notes_drawer.dart](lib/features/setlists/widgets/song_notes_drawer.dart) — replace `_buildFooter()` with `SheetFooter`. Edit mode: primary `Save`; view mode: primary `Edit`.
11. [lib/features/setlists/widgets/custom_tuning_modal.dart](lib/features/setlists/widgets/custom_tuning_modal.dart) — replace `_buildActionButtons()` with `SheetFooter`. Primary variant flips from `secondary` (grey pill) to `primary` (rose) — this is a deliberate visible change to match the convention.
12. [lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart](lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart) — replace footer with `SheetFooter`. Note there are two Cancel buttons in the source (one in the `_handleClose` guard around line 435 and one in the sticky footer around line 785); only the sticky footer is in scope.
13. [lib/features/setlists/widgets/key_picker_bottom_sheet.dart](lib/features/setlists/widgets/key_picker_bottom_sheet.dart) — replace footer with `SheetFooter`.
14. [lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart](lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart) — replace the "Create New" mode footer Row with `SheetFooter(primaryLabel: 'Create & Add', onPrimary: _handleConfirmCreate, onCancel: _handleCancelCreate)`. Default picker mode is unchanged.

Category B — view drawers (5):

15. [lib/features/gigs/widgets/view_gig_drawer.dart](lib/features/gigs/widgets/view_gig_drawer.dart) — `SheetFooter(primaryLabel: 'Done', onPrimary: pop, cancelLabel: 'Edit', onCancel: canEdit ? () => _handleEdit(context) : null)`.
16. [lib/features/rehearsals/widgets/view_rehearsal_drawer.dart](lib/features/rehearsals/widgets/view_rehearsal_drawer.dart) — same as #15.
17. [lib/features/calendar/widgets/view_block_out_drawer.dart](lib/features/calendar/widgets/view_block_out_drawer.dart) — same as #15.
18. [lib/features/contacts/widgets/band_member_detail_drawer.dart](lib/features/contacts/widgets/band_member_detail_drawer.dart) — same as #15, gated on `isAdmin`.
19. [lib/features/contacts/widgets/contact_detail_drawer.dart](lib/features/contacts/widgets/contact_detail_drawer.dart) — same as #15.

Category C — single-action sheets (5):

20. [lib/features/gigs/widgets/gig_notes_sheet.dart](lib/features/gigs/widgets/gig_notes_sheet.dart) — `SheetFooter(primaryLabel: 'Done', onPrimary: pop, onCancel: null)`.
21. [lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart](lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart) — same as #20.
22. [lib/features/calendar/widgets/day_detail_bottom_sheet.dart](lib/features/calendar/widgets/day_detail_bottom_sheet.dart) — when `onAddEvent != null`, use `SheetFooter(primaryLabel: 'Add Event', primaryIcon: AppIcons.add, onPrimary: onAddEvent, onCancel: null)`. When `onAddEvent == null`, render nothing (unchanged behavior).
23. [lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart) — replace the `ElevatedButton.icon` with `SheetFooter(primaryLabel: 'Edit Entry', primaryIcon: AppIcons.edit, onPrimary: ..., onCancel: null)`.
24. [lib/features/calendar/widgets/calendar_subscription_dialog.dart](lib/features/calendar/widgets/calendar_subscription_dialog.dart) — replace the standalone `AppButton text "Close"` with `SheetFooter(primaryLabel: 'Done', onPrimary: pop, onCancel: null)`. This is a `Close` → `Done` label change and text → primary variant change. See edge case §4.

Category D — mini-creators (2):

25. [lib/features/setlists/widgets/pause_creator.dart](lib/features/setlists/widgets/pause_creator.dart) — `SheetFooter(primaryLabel: 'Add Pause', onPrimary: _hasContent ? _submit : null, onCancel: null)`. Variant changes from `secondary` to `primary`.
26. [lib/features/setlists/widgets/set_break_creator.dart](lib/features/setlists/widgets/set_break_creator.dart) — `SheetFooter(primaryLabel: 'Add Set Break', onPrimary: _submit, onCancel: null)`. Variant changes from `secondary` to `primary`.

Category E — inline-to-sticky (1):

27. [lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart](lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart) — the current end-of-scroll Column becomes a sticky `SheetFooter(primaryLabel: 'Enrich Songs', onPrimary: hasSelection ? () => _handleEnrichSongs(context, overwriteExisting) : null, onCancel: () => Navigator.of(context).pop(null))`. The action buttons move from inside the scrollable body to a fixed bottom container.

Doc:
28. [lib/components/ui/README.md](lib/components/ui/README.md) — add `SheetFooter` to the facade component list (single row).

## Files Off-Limits

- [lib/features/lyrics/widgets/lyrics_editor_sheet.dart](lib/features/lyrics/widgets/lyrics_editor_sheet.dart) — header-based iOS-style Cancel/Save, not a footer. Out of scope per the feature spec's "footer" wording.
- [lib/features/contacts/widgets/contact_form_screen.dart](lib/features/contacts/widgets/contact_form_screen.dart), [lib/features/contacts/widgets/venue_form_screen.dart](lib/features/contacts/widgets/venue_form_screen.dart), [lib/features/calendar/one_calendar_settings_screen.dart](lib/features/calendar/one_calendar_settings_screen.dart) — full-screen routes with `AppAppBar` actions, not modal sheets.
- All dialogs: [lib/components/ui/app_dialog.dart](lib/components/ui/app_dialog.dart), [lib/components/ui/confirm_action_dialog.dart](lib/components/ui/confirm_action_dialog.dart), [lib/features/setlists/widgets/bpm_input_dialog.dart](lib/features/setlists/widgets/bpm_input_dialog.dart), [lib/features/setlists/widgets/duration_input_dialog.dart](lib/features/setlists/widgets/duration_input_dialog.dart), [lib/features/songs/widgets/enrichment_confirm_dialog.dart](lib/features/songs/widgets/enrichment_confirm_dialog.dart), [lib/features/gigs/widgets/availability_prompt_modal.dart](lib/features/gigs/widgets/availability_prompt_modal.dart), [lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart](lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart), [lib/features/notifications/widgets/notification_settings_modal.dart](lib/features/notifications/widgets/notification_settings_modal.dart). Dialogs are not sheets/drawers.
- Picker sheets that dismiss on tile-tap and have no action-button footer (listed in "Explicitly out-of-scope files" above).
- [lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart), [lib/app/theme/event_editor_theme.dart](lib/app/theme/event_editor_theme.dart), [lib/app/theme/app_theme.dart](lib/app/theme/app_theme.dart) — no token or theme changes required. `SheetFooter` reads tokens; it doesn't add them.
- [lib/components/ui/app_button.dart](lib/components/ui/app_button.dart) — reuse as-is. `SheetFooter` composes `AppButton`; do not modify `AppButton` itself.
- All Supabase migrations, RPC functions, edge functions, and repositories — pure UI change.
- Sheet **content** (the form fields, headers, drag handles, body scroll views) — only the footer widget itself is in scope. Business logic (save handlers, dirty checks, validators, permission gates) is untouched.
- [pubspec.yaml](pubspec.yaml) — no new dependencies.

## Change Budget

- **Expected new files:** 2 ([lib/components/ui/sheet_footer.dart](lib/components/ui/sheet_footer.dart), [test/components/ui/sheet_footer_test.dart](test/components/ui/sheet_footer_test.dart))
- **Expected new public classes/methods:** 1 (`SheetFooter` widget)
- **Expected new dependencies:** 0
- **Expected net line delta per file:**
  - `sheet_footer.dart`: +100 to +140 lines
  - `sheet_footer_test.dart`: +80 to +140 lines
  - `event_editor_drawer.dart`: −60 to −40 (removes `_buildSummaryText`, `_buildPrimaryActionButton`, and inline `_buildStickyFooter` body)
  - `add_block_out_drawer.dart`: −60 to −40 (removes `_buildDeleteButton` + both `_buildBottomButtons` branches)
  - `add_financial_entry_bottom_sheet.dart`: −55 to −35 (removes both button rows + destructive Column)
  - `gig_pay_bottom_sheet.dart`: −55 to −35 (removes both view-only + normal footer branches)
  - `song_details_bottom_sheet.dart`: −40 to −25 (removes `_buildFixedBottomActions`)
  - Remaining 21 sheet files: −25 to −10 each (removes footer Container/Row/Column boilerplate)
- **Expected total net delta across all files:** roughly **−400 to −700 lines net**
- **README.md:** +2 lines

## System Impact Map

| System | Affected? | Notes |
|--------|-----------|-------|
| Gigs | Yes (UI-only) | Edit-gig footer content and gig view-drawer footer layout change; save/delete logic untouched. |
| Rehearsals | Yes (UI-only) | Rehearsal notes/view-drawer/editor footer layout changes. |
| Setlists | Yes (UI-only) | Song details, song notes, song enrichment review, print options, setlist picker (create-new), tuning/key/custom-tuning pickers, pause/set-break creators — all footer layout changes. |
| Members | Yes (UI-only) | Role management + band member edit/detail drawer footers. |
| Contacts | Yes (UI-only) | Contact detail drawer footer. Contact/venue form **screens** untouched. |
| Calendar | Yes (UI-only) | Day detail sheet, block-out add/view drawers, calendar subscription dialog (sheet). One Calendar Settings **screen** untouched. |
| Financials | Yes (UI-only) | Add/edit financial entry sheet, gig-pay sheet, financial entry details sheet. |
| Auth | No | |
| Routing | No | |
| Notifications | No | |
| Platforms (iOS/Android/macOS/web) | All (identical dark-mode-only rendering) | No platform-conditional code touched. |
| Init order | No | |
| DB / RLS / RPC | No | |

## Regression Risk

**MEDIUM.**

- **Scope is wide (27 files touched)** but every change is UI-shape. No
  auth/session/routing/init-order/DB touched. Business logic (save handlers,
  dirty checks, permission gates, validators) is untouched by design.
- **State plumbing must land intact.** Each sheet's `_isSaving`,
  `_hasChanges`, `_isDeleting`, `_isDirty`, `canSave`, and permission gates
  must map onto the `onPrimary`/`primaryIsLoading`/`onCancel` inputs
  correctly. Any misplumb produces a stuck spinner or a save that fires when
  disabled.
- **Deliberate visible design changes** (see Edge Cases): three sheet
  categories change how a button looks (Print Options "Save layout"
  demoted to left text-button; view drawers' Edit action moves from below
  Done to left of Done; calendar_subscription "Close" text → "Done" primary;
  custom_tuning / pause_creator / set_break_creator's Save/Add variant
  flips from grey `secondary` to rose `primary`). None of these change
  behavior, only appearance, but they will show up on a visual diff.
- **Enrichment selector layout shift:** its buttons move from inside the
  scroll to a sticky footer. That's the largest layout change in the set —
  users of that sheet who scroll to the bottom to reach the buttons will
  now see them anchored instead.

Not HIGH because: no auth/session/routing, no DB, no init-order, and each
file is independent — a regression in one sheet doesn't cascade.

## Engineer Task Breakdown

Ordered, atomic. Each task compiles on its own.

1. **Create the widget.** Add [lib/components/ui/sheet_footer.dart](lib/components/ui/sheet_footer.dart) with the `SheetFooter` API and rendering rules from "Target convention" and "`SheetFooter` API" above. It composes `AppButton` — do not touch `AppButton`.

2. **Test the widget.** Add [test/components/ui/sheet_footer_test.dart](test/components/ui/sheet_footer_test.dart) covering the assertions in "Verification Plan — Tier 1" below.

3. **Fix the Edit Gig footer (the explicit ask).** In [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart): (a) rewrite `_buildStickyFooter(BuildContext)` to return a `SheetFooter`, view-only vs normal branch preserved; (b) delete `_buildSummaryText()`; (c) delete `_buildPrimaryActionButton(BuildContext)`. Verify `_isSaving`, `canSave`, `widget.onCancelled`, and `_primaryButtonLabel` still drive the footer correctly. This is the single change that fulfills the "remove event-type and date/time from Edit Gig footer" half of the spec.

4. **Migrate Category A (editors).** Migrate the remaining 13 files (list items 2 and 5–14 above) one at a time. Each file: replace the existing footer helper with a `SheetFooter` call, preserving the file's existing dirty/loading/permission gates. Delete now-dead helpers.

5. **Migrate Category B (view drawers).** Migrate the 5 files (list items 15–19). Each maps `Done` → primary right, `Edit` → cancel-slot label with `onCancel` gated by `canEdit`.

6. **Migrate Category C (single-action).** Migrate the 5 files (list items 20–24). `onCancel: null`, primary right-anchored. For file #23 use `primaryIcon: AppIcons.edit`; for file #22 use `primaryIcon: AppIcons.add`. For file #24, apply the `Close` → `Done` and text → primary changes noted in edge case §4.

7. **Migrate Category D (mini-creators).** Migrate files #25 and #26. Variant switches from `secondary` to `primary`.

8. **Migrate Category E (enrichment_selector).** In file #27, move the two action buttons from inside the scrollable body into a sticky `SheetFooter` at the bottom of the sheet. The `Container`/`Padding` around them at line 165 can go.

9. **Update the facade README.** Add a single row for `SheetFooter` to the "Forui-Styled Wrappers" list in [lib/components/ui/README.md](lib/components/ui/README.md).

10. **Analyzer + tests.** Run `flutter analyze` (must produce no new warnings) and `flutter test` (all existing tests plus the new `sheet_footer_test.dart` must pass).

## Verification Plan

### Tier 1 — pre-deploy (must pass before opening PR)

**Analyzer.** `flutter analyze` produces zero new warnings/errors compared to `main` at `84f6ebe`.

**Widget tests for `SheetFooter`.** [test/components/ui/sheet_footer_test.dart](test/components/ui/sheet_footer_test.dart) covers:
- **Two-action layout:** with `onCancel != null`, the Row has exactly two `AppButton`s. The one on the left has `variant: text` and label `'Cancel'` (default). The one on the right has `variant: primary`. Ordering is verified by widget position, not just presence.
- **Single-action layout:** with `onCancel: null`, only the primary `AppButton` is rendered, right-anchored (no cancel slot widget in the tree).
- **Loading state:** `primaryIsLoading: true` disables the primary (`onPressed` is `null`) and shows a spinner instead of the label; also disables the cancel button.
- **Disabled state:** `onPrimary: null` renders the primary button as disabled (still visible, `onPressed == null`).
- **Destructive slot:** with `destructiveLabel` and `onDestructive` supplied, a third `AppButton destructive` renders above the primary/cancel Row (verified by widget position in a Column).
- **Custom cancel label:** `cancelLabel: 'Edit'` renders on the left button.
- **Custom primary icon:** `primaryIcon: AppIcons.edit` renders an icon on the primary button.

None of these tests touches the sheets being migrated — they exercise the widget in isolation.

**Migration smoke test.** For each migrated file, at least one existing widget/unit test (where one already exists in `test/`) still passes. No new per-sheet test is required — the widget-level tests plus Tier 2's visual per-sheet check cover the change.

### Tier 2 — post-deploy visual check (per sheet)

Verified on `macOS` and one mobile target (`iOS` simulator or `Android` emulator), dark mode. For each sheet, the tester confirms: (a) primary button style (filled rose) and right placement; (b) cancel/secondary button style (text) and left placement; (c) any destructive button style and above-row placement; (d) for the Edit Gig sheet only, absence of event-type and date/time text in the footer.

Explicit per-sheet checklist:

**Category A — editors:**
1. **Edit Gig drawer** — footer shows ONLY `Cancel` (text, left) and the primary label (`Update` for edit, `Add Gig` / `Add Rehearsal` / `Add Block Out` for create; rose fill, right). NO summary text. NO event-type. NO date/time. View-only mode shows a single primary `Close` on the right.
2. **Add/Edit Block Out drawer** — Cancel text left; `Add Block Out` (create) or `Update` (edit) primary right. In edit mode: destructive `Delete Block Out` full-width above the row.
3. **Band Member Edit drawer** — Cancel text left; `Save` primary right; mid-body `Remove from band` destructive still present in the body (unchanged).
4. **Role Management sheet** — same as #3 without the body remove-button.
5. **Add Financial Entry sheet** — Cancel text left; `Save` primary right; in edit mode with delete permission, `Delete income` / `Delete expense` destructive above.
6. **Gig Pay sheet** — Cancel text left; `Save` primary right (normal mode). View-only: single primary `Close` right.
7. **Print Options sheet** — `Save layout` text left; `Preview` primary right.
8. **Song Details sheet** — Cancel text left; `Save` primary right. `_justEnriched`: success text appears above the footer, primary shows `Done`, cancel is hidden. Read-only mode: single primary `Close` right.
9. **Song Enrichment Review sheet** — Cancel text left; `Save` primary right.
10. **Song Notes drawer** — Cancel text left; `Save` (edit mode) or `Edit` (view mode) primary right.
11. **Custom Tuning modal** — Cancel text left; `Save Tuning` primary (rose fill, not the previous grey pill) right.
12. **Tuning Picker sheet** — Cancel text left; `Save` primary right.
13. **Key Picker sheet** — Cancel text left; `Save` primary right.
14. **Setlist Picker (create-new mode)** — Cancel text left; `Create & Add` primary right.

**Category B — view drawers:**
15. **View Gig drawer** — `Edit` text left (when `canEdit`); `Done` primary right.
16. **View Rehearsal drawer** — same.
17. **View Block Out drawer** — same.
18. **Band Member Detail drawer** — `Edit` text left (when `isAdmin`); `Done` primary right.
19. **Contact Detail drawer** — `Edit` text left; `Done` primary right.

**Category C — single-action:**
20. **Gig Notes sheet** — single `Done` primary right; no cancel.
21. **Rehearsal Notes sheet** — same.
22. **Day Detail sheet** — when `onAddEvent != null`: single `Add Event` (with `+` icon) primary right; no cancel. Otherwise no footer.
23. **Financial Entry Details sheet** — single `Edit Entry` (with edit icon) primary right; no cancel.
24. **Calendar Subscription sheet** — single `Done` primary right (previously `Close` text; verify the rename and variant flip are correct).

**Category D — mini-creators:**
25. **Pause Creator** — single `Add Pause` primary (rose, not previous grey) right; no cancel.
26. **Set Break Creator** — single `Add Set Break` primary right; no cancel.

**Category E — enrichment selector:**
27. **Enrichment Selector** — buttons now anchored at the bottom (were inline at end of scroll). Cancel text left; `Enrich Songs` primary right.

## QA Regression Areas

- **Save/Cancel behavior on every editor sheet in Category A** — save still respects `_isSaving` / `_hasChanges` / `_isDirty` / permission gates; loading spinner shows during save; cancel closes the sheet without saving.
- **Destructive actions (block-out delete, financial entry delete)** — still trigger the confirmation dialog, still perform the delete, still show the correct success/error snackbar.
- **Event editor drawer view-only mode** — Close button still pops with `false` and fires `onCancelled`.
- **Song Details "just enriched" state** — success text renders above the footer, primary is `Done` (not `Save`), cancel is hidden.
- **Read-only mode on every sheet that has one** (Song Details, Gig Pay view-only, Event Editor view-only) — appropriate single-close button appears.
- **`day_detail_bottom_sheet` when `onAddEvent == null`** — footer renders nothing (existing behavior).
- **Print Options** — `Save layout` still opens the save-layout dialog; `Preview` still triggers `_handlePreview`.
- **Enrichment Selector** — bottom overscroll no longer needed to reach the buttons; sheet still returns the correct `EnrichmentSelectorResult` or `null` on cancel.
- **Loading state during save** on Add Financial Entry, Gig Pay, Custom Tuning, band-member-edit, role management — spinner in the primary button, cancel disabled.
- **Dark mode contrast** — text-button `Cancel` on `context.colors.surface` must remain legible (existing `AppButton text` variant already handles this via Forui theme).

## Rollout Strategy

Single PR on branch `feature/standardize-sheet-drawer-footers` off `main`
at `84f6ebe`. Merge after Tier 1 automated checks pass and Tier 2 visual QA
covers every entry in the 27-sheet checklist above.

No feature flag. Change is UI-only, low-risk to individual sheets and
independent per sheet, so a partial rollout adds review complexity without
buying anything.

## Out of Scope

- **`lyrics_editor_sheet.dart`** — uses a header-based Cancel/Save layout,
  not a footer. Feature spec explicitly targets footers.
- **Full-screen forms** — `contact_form_screen.dart`, `venue_form_screen.dart`,
  `one_calendar_settings_screen.dart` are `AppScaffold`+`AppAppBar` routes,
  not modal sheets/drawers.
- **All dialogs** — `showAppDialog`, `AlertDialog`, `showDialog`, and the
  dialog wrappers in `lib/components/ui/`. Dialog action rows are a separate
  convention.
- **Picker sheets that dismiss on tile-tap** — they have no action-button
  footer to standardize (share format, catalog sort, backup/restore, image
  source, navigation app, savings, tips overlay, technical details).
- **Sheet content, headers, drag handles, body scroll views** — only the
  footer widget is in scope.
- **Business logic** — no changes to save handlers, dirty checks, permission
  gates, validators, error mapping, snackbar messages, or any Supabase call.
- **Design tokens** — no changes to spacing, colors, typography, or animations.
- **Theme** — no changes to `app_theme.dart` or `event_editor_theme.dart`.
- **Platform-conditional code** — none touched.
- **Any new dependencies** — none.

## Edge Cases

The following are deliberate design choices baked into this plan. None
require a Tony decision on their own — each is a small, justified extension
of the stated convention — but each is a visible change that a reviewer
should see called out.

**§1. Destructive slot placement.** Destructive actions (Delete Block Out,
Delete income/expense) that today sit **inside or immediately above** the
footer container move into the `SheetFooter.destructive` slot (full-width
row above the primary/cancel row). Destructive actions that sit **mid-body**
next to the semantically related fields (e.g. `band_member_edit_drawer`'s
"Remove from band" button next to the role toggle) stay where they are —
those are body actions, not footer actions.

**§2. View drawers map "Edit" → cancel-slot.** The five view drawers
(view_gig, view_rehearsal, view_block_out, band_member_detail,
contact_detail) currently show `Done` full-width primary with `Edit` text
below when available. Under the new convention, `Edit` moves to the
LEFT text-slot and `Done` stays as the primary on the right. `Edit` is
semantically a "secondary action," not a "cancel," but it fits the
convention's shape and preserves the affordance (main dismissal on the
right, secondary go-to-edit on the left). This is a small visible change
in placement; behavior is unchanged.

**§3. Print Options has two non-cancel actions.** `Save layout` + `Preview`.
This plan puts `Save layout` in the text-left slot and `Preview` in the
primary-right slot. The tradeoff is that `Save layout` is visually demoted
from a full-width outlined button to a text button. This is the natural
extension of the stated convention (primary on the right, "everything else"
on the left), and it matches how `Save layout` behaves — it's a side-action
that saves the current template state without exiting or applying. If Tony
later wants `Save layout` to keep visual weight, an alternative is to move
it into the header (icon-only button next to the sheet title) and add a
proper `Cancel` in the text-left slot. That would be a follow-up feature,
not part of this plan.

**§4. Calendar Subscription "Close" → "Done".** The current
`calendar_subscription_dialog` footer is a single `AppButton text "Close"`.
Under the convention, single-action sheets take a primary right button.
The label also changes from `Close` to `Done` to match every other
single-action sheet in the app (gig notes, rehearsal notes, day detail,
financial entry details). This is a visible label + variant change on a
single button.

**§5. `custom_tuning_modal`, `pause_creator`, `set_break_creator`
variant fix.** These three currently use `AppButtonVariant.secondary`
(Forui grey pill) for their primary action. The feature spec's convention is
"primary action = primary (filled) button," so the variant switches to
`AppButtonVariant.primary` (rose fill). This is a deliberate visible color
change on the primary button, correcting a pre-existing drift.

**§6. `enrichment_selector_bottom_sheet` layout shift.** Its Enrich/Cancel
buttons currently live at the end of the scrollable body. Under the
convention they move to a fixed sticky footer at the bottom of the sheet.
Users who scroll down to reach them will now find them anchored, so short
sheets will look tighter and long ones will not require scrolling to
reach the actions.

**§7. `add_financial_entry_bottom_sheet` destructive style.** The current
"Delete income" / "Delete expense" action is a plain red `TextButton`.
It becomes an `AppButton destructive` (Forui filled destructive), matching
the destructive style already used in `add_block_out_drawer` and
`band_member_edit_drawer`. This is a visible variant change from text to
filled destructive.
