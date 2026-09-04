# ENGINEER_REPORT — standardize-sheet-drawer-footers

## Feature Slug
`standardize-sheet-drawer-footers`

## Feature Title
Standardize sheet/drawer footer actions; remove event-type and date/time from the Edit Gig footer

## Cycle Number
2

## Goal
Cycle 1: Create `SheetFooter` widget + tests + README; migrate all 27 in-scope sheet/drawer files (Categories A–E) to `SheetFooter`; remove event-type/date/time summary text from the Edit Gig footer.

Cycle 2 (QA REQUIRES CHANGES): Revert three incidental out-of-scope lint improvements from Cycle 1 (`W-1` pause_creator.dart, `W-2` calendar_subscription_dialog.dart, `W-3` band_member_detail_drawer.dart); apply S-2 fix (gate SheetFooter on `!isLoading` in calendar_subscription_dialog.dart); correct report analyzer claim.

## Architect Tasks Completed

- **Step 1:** Created `lib/components/ui/sheet_footer.dart`.
- **Step 2:** Created `test/components/ui/sheet_footer_test.dart` (13 widget tests).
- **Step 3 (Edit Gig footer):** Removed `_buildSummaryText()` and `_buildPrimaryActionButton()` from `event_editor_drawer.dart`; `_buildStickyFooter()` now returns a `SheetFooter`. Footer shows no event type, date, or time.
- **Step 4 (README):** Added `SheetFooter` to `lib/components/ui/README.md`.
- **Category A (files 1–14):** All editor sheets migrated.
- **Category B (files 15–19):** All view drawers migrated — Edit slot moved to `cancelLabel`/`onCancel` per edge case §2; each file's existing permission gate preserved.
- **Category C (files 20–24):** All single-action sheets migrated — `onCancel: null`, primary right-anchored; `Close` → `Done` + text → primary on calendar_subscription_dialog per edge case §4.
- **Category D (files 25–26):** Both mini-creators migrated — variant flipped from `secondary` to `primary` per edge case §5.
- **Category E (file 27):** enrichment_selector action buttons moved from inline scroll body to sticky `SheetFooter` per edge case §6.

**Cycle 2 changes (revert-only + S-2 fix):**
- **W-1 revert (`pause_creator.dart`):** Restored `Container` (not `DecoratedBox`) in `_DurationField`, `width: 1` on two `Border.all` calls, non-`const` `BorderRadius.vertical`, and blank-line artifact. Only footer migration remains in the diff.
- **W-2 revert (`calendar_subscription_dialog.dart`):** Restored non-`const` `Icon`, `safeBottom` variable + usage in `EdgeInsets`, `() => _buildLoading()` closure (not tearoff), `AppProgressIndicator(type: ProgressIndicatorType.circular, ...)` argument form in both `_buildLoading` and `_buildBody`. Only footer migration remains in the diff.
- **S-2 fix (`calendar_subscription_dialog.dart`):** `SheetFooter` is now gated with `if (!subscriptionUrlAsync.isLoading)` so no footer button appears during the loading state (matches original behavior where no button existed during loading).
- **W-3 revert (`band_member_detail_drawer.dart`):** Restored `crossAxisAlignment: CrossAxisAlignment.center` to the header `Row`. Only footer migration remains in the diff.

## Files Created
- `lib/components/ui/sheet_footer.dart` (124 lines)
- `test/components/ui/sheet_footer_test.dart` (277 lines)

## Files Modified

**Documentation:**
- `lib/components/ui/README.md` (+2 lines — SheetFooter row added)

**Category A — editors (14):**
1. `lib/features/events/widgets/event_editor_drawer.dart`
2. `lib/features/calendar/widgets/add_block_out_drawer.dart`
3. `lib/features/contacts/widgets/band_member_edit_drawer.dart`
4. `lib/features/members/widgets/role_management_sheet.dart`
5. `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
6. `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`
7. `lib/features/setlists/widgets/print_options_bottom_sheet.dart`
8. `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
9. `lib/features/setlists/widgets/song_enrichment_review_sheet.dart`
10. `lib/features/setlists/widgets/song_notes_drawer.dart`
11. `lib/features/setlists/widgets/custom_tuning_modal.dart`
12. `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart`
13. `lib/features/setlists/widgets/key_picker_bottom_sheet.dart`
14. `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`

**Category B — view drawers (5):**
15. `lib/features/gigs/widgets/view_gig_drawer.dart`
16. `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`
17. `lib/features/calendar/widgets/view_block_out_drawer.dart`
18. `lib/features/contacts/widgets/band_member_detail_drawer.dart`
19. `lib/features/contacts/widgets/contact_detail_drawer.dart`

**Category C — single-action sheets (5):**
20. `lib/features/gigs/widgets/gig_notes_sheet.dart`
21. `lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart`
22. `lib/features/calendar/widgets/day_detail_bottom_sheet.dart`
23. `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`
24. `lib/features/calendar/widgets/calendar_subscription_dialog.dart`

**Category D — mini-creators (2):**
25. `lib/features/setlists/widgets/pause_creator.dart`
26. `lib/features/setlists/widgets/set_break_creator.dart`

**Category E — inline-to-sticky (1):**
27. `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`

**Total tracked files changed: 30** (27 migrated + 2 created + 1 README)

## Analyzer Results

The changed code introduces **0 new analyzer errors, 0 new warnings**.

`flutter analyze` (full workspace) reports pre-existing `info`-level lints across the codebase from the 2026-09-02 `analysis_options.yaml` update (`prefer_const_constructors`, `use_decorated_box`, `avoid_redundant_argument_values`, `unnecessary_lambdas`, etc.) that are unrelated to this change. The Cycle-1 run pre-dated or used a cached state that did not include those rules. Cycle 2 restores the original code that triggers those lints; fixing them is explicitly out of scope.

Files changed in Cycle 2, analyzed directly (`flutter analyze <3 files>`):

```
12 issues found — all info severity, all pre-existing lints in unchanged code sections.
0 errors, 0 warnings.
```

## Test Results

```
flutter test
195 tests passed.
```

All 195 tests pass, including all 13 `sheet_footer_test.dart` cases:
1. primary renders right-aligned with primary variant
2. cancel renders left with text variant
3. cancel is hidden when onCancel is null
4. destructive renders above the row when label+callback supplied
5. destructive is absent when only label supplied
6. destructive is absent when only callback supplied
7. primaryIsLoading shows spinner and disables primary and cancel
8. onPrimary null renders primary as disabled
9. tapping primary invokes callback
10. tapping cancel invokes callback
11. tapping destructive invokes callback
12. custom cancelLabel renders on the left button
13. primaryIcon renders icon on primary button

## Code Efficiency / Bloat Check

- **Helper search:** Searched `lib/` for existing sticky-footer or sheet-footer widgets by name (`sheet_footer`, `SheetFooter`, sticky footer) and by behavior (Container + top-border + shadow + AppButton row). No existing equivalent found — all 27 sheets rolled their own Container/Row/Column boilerplate. `SheetFooter` is the correct new abstraction.
- **File sizes:** `sheet_footer.dart` = 124 lines (under 200 target for helper widgets). `sheet_footer_test.dart` = 277 lines (under 400 target). No justification note needed.
- **`_wrap` helper in test:** Used 13 times (once per `testWidgets`). Justified as a test helper.
- **`hasDestructive` local bool:** Used in exactly one conditional. Left as a named local for readability over an inline `&&` triple-dereference.
- **No AI-shaped code:** No dead imports, no unused variables, no `debugPrint`, no `TODO`/`FIXME`, no `_buildX()` one-off methods.
- **`dart fix --dry-run` result:** No suggestions in the new files.

## Verification (manual steps performed)

- Confirmed on branch `feature/standardize-sheet-drawer-footers`, tree clean beyond expected `docs/features/` untracked files.
- Read each file before editing; confirmed exact permission/state gates preserved per file.
- `grep -c 'SheetFooter('` on all 27 migrated lib/features files — each returns 1.
- `flutter analyze` — 0 errors, 0 warnings; 12 pre-existing info-level lints only (unchanged code sections).
- `flutter test` — 195/195 pass.
- `dart format` applied only to changed files — 0 files changed (already clean after replacements).

**Edge-case confirmations:**

- **§1 — Destructive slot:** `add_block_out_drawer.dart` and `add_financial_entry_bottom_sheet.dart` pass `destructiveLabel`/`onDestructive` to `SheetFooter`; the destructive `AppButton` renders as a filled destructive-variant button above the primary/cancel row (not the previous raw red `TextButton`).
- **§2 — View-drawer Edit → cancel slot:** Files 15–19 use `cancelLabel: 'Edit'` with `onCancel` gated by the per-file permission check (`widget.canEdit`, `canEdit`, `isAdmin`) so the Edit button is absent when the user lacks edit rights, matching prior behavior.
- **§3 — Print Options Save-layout → text-left / Preview primary:** `SheetFooter(primaryLabel: 'Preview', onPrimary: _handlePreview, cancelLabel: 'Save layout', onCancel: _showSaveLayoutDialog)` — `Save layout` occupies the cancel/left slot as a text button; `Preview` is the primary (rose, right).
- **§4 — Calendar Subscription Close → Done:** `calendar_subscription_dialog.dart` now uses `SheetFooter(primaryLabel: 'Done', onPrimary: pop, onCancel: null)` — label renamed from `Close`, variant promoted from text to primary (filled rose).
- **§5 — secondary → primary variant:** `custom_tuning_modal.dart`, `pause_creator.dart`, and `set_break_creator.dart` all had `AppButtonVariant.secondary` (grey pill); these now use `SheetFooter` which renders the primary as `AppButtonVariant.primary` (rose fill).
- **§6 — Enrichment selector inline → sticky:** Action buttons in `enrichment_selector_bottom_sheet.dart` moved from end-of-scroll body column to a fixed sticky `SheetFooter`; the sheet now exposes `Cancel` (text, left) and `Enrich Songs` (primary, right) anchored below the scroll.
- **§7 — Add Financial Entry destructive text → filled:** The previous `TextButton` (raw red text) is now `AppButton destructive` inside the `SheetFooter` destructive slot — a filled destructive-variant button above the primary/cancel row.

## Deviations From Plan

1. **`variant: AppButtonVariant.primary` omitted from primary `AppButton` call site.** The analyzer (`avoid_redundant_argument_values`) flags it because `AppButtonVariant.primary` is the `AppButton` constructor default. Omitting it is strictly equivalent.

2. **`cancel is hidden when onCancel is null` test does not assert `Row.mainAxisAlignment`.** The test verifies outcome (button count + absence of cancel text) rather than the implementation detail. The correct `mainAxisAlignment.end` value remains in the widget.

3. ~~Pre-existing lint fix in `band_member_detail_drawer.dart`~~ — **reverted in Cycle 2 (W-3 revert)**. `crossAxisAlignment: CrossAxisAlignment.center` was temporarily removed in Cycle 1 but restored; the file's only remaining change is the footer migration.

## Blockers Encountered
None.

## Ready For QA
Yes
