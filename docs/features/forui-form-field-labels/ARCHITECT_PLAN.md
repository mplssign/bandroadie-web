# ARCHITECT_PLAN.md

## Feature Slug

`bug/forui-form-field-labels`

## Type

Bug

## Title

Forui-wrapped form fields render with no label/hint because callers pass Material `InputDecoration`/`style`, which the wrapper silently drops.

## Problem Summary

`AppTextField` and `AppTextFormField` are Forui wrappers that only render labels/hints through wrapper props (`labelText`, `hintText`). Many call sites still pass Material `decoration` and `style`, which are currently ignored by wrapper internals. This causes missing labels/hints in multiple screens (most visibly Contacts/Venues), and there are still raw Material `TextField`/`TextFormField` usages that are out of design-system scope.

## Root Cause (Confidence: HIGH)

1. Wrapper implementation confirms `decoration` and `style` are accepted but not used in rendering.
2. Confirmed-broken screens (`venue_form_screen.dart`, `contact_form_screen.dart`, `venue_contact_block.dart`) pass label/hint via `InputDecoration` only, so wrapper renders neither label nor hint.
3. Workspace-wide audit found 54 wrapper call sites total (excluding wrapper definitions):
   - 52 call sites pass dead `decoration`/`style`
   - 2 call sites are already compliant
4. Additional raw Material text-field call sites remain in 7 files.

## Scope Rules

1. UI-layer only. No DB, RLS, RPC, migration, or backend changes.
2. Do not change `AppTextField` or `AppTextFormField` behavior unless a call site absolutely requires unsupported capability (none identified in this audit).
3. For oversized files (`setlist_detail_screen.dart`), only minimal local edits at listed lines.
4. No new dependencies.

## Audit Method

1. Read wrappers in full:
   - `lib/components/ui/app_text_field.dart`
   - `lib/components/ui/app_text_form_field.dart`
2. Enumerated all wrapper call sites and classified each call by arguments (`decoration`, `style`, `labelText`, `hintText`).
3. Inspected local UI context around each dead-prop call to classify likely user-visible impact:
   - `both missing` (no adjacent label + decoration-provided label/hint dropped)
   - `hint missing only` (separate adjacent label exists)
   - `dead-prop cleanup` (no label/hint expected; decoration/style still no-op)
4. Enumerated raw Material `TextField`/`TextFormField` call sites for migration.

## Wrapper Call Sites: Explicit Change List

### Priority 0 (Tony-reported symptom): both label and hint missing

1. `lib/features/contacts/widgets/venue_form_screen.dart`
   - `AppTextField` at lines 354, 362, 373, 386, 401, 411
   - Fix: Replace `decoration: _inputDecoration(...)` and `style:` usage with wrapper-native props:
     - `labelText: ...` for Name/Address/City/State/Phone/Notes
     - `hintText` where placeholder text is desired
     - keep existing keyboard/input formatter/focus/lines behavior
2. `lib/features/contacts/widgets/contact_form_screen.dart`
   - `AppTextField` at lines 245, 271, 284, 296, 314
   - Fix: same pattern; move labels from `_inputDecoration(...)` into `labelText`, optional `hintText` as needed.
3. `lib/features/contacts/widgets/venue_contact_block.dart`
   - `AppTextField` at lines 178, 207, 219, 237
   - Fix: same pattern; move labels into `labelText`, retain phone/email formatters and callbacks.

### Priority 1: wrapper fields with external label text; hint currently dropped

4. `lib/features/calendar/widgets/add_block_out_drawer.dart`
   - `AppTextField` line 761
   - Current visible state: external `Text(label)` present; hint from decoration is dropped.
   - Fix: remove dead `style`/`decoration`; pass `hintText: hint`.
5. `lib/features/auth/login_screen.dart`
   - `AppTextField` line 629
   - Current visible state: field label rendered as separate `Text`; placeholder dropped.
   - Fix: move placeholder to `hintText: 'you@email.com'`; remove dead `style`/`decoration`.
6. `lib/features/contacts/widgets/invite_members_screen.dart`
   - `AppTextFormField` line 304
   - Current visible state: hint dropped.
   - Fix: set `hintText: 'name@example.com'`; remove dead `style`/`decoration`.
7. `lib/features/contacts/widgets/title_pill_selector.dart`
   - `AppTextField` line 166
   - Current visible state: custom-title input missing placeholder.
   - Fix: set `hintText: 'Enter custom title'`; remove dead `style`/`decoration`.
8. `lib/features/profile/my_profile_screen.dart`
   - `AppTextFormField` line 1053
   - Current visible state: label row exists; hint dropped.
   - Fix: set `hintText` from existing `hint` param; remove dead `style`/`decoration`.
9. `lib/features/profile/profile_screen.dart`
   - `AppTextFormField` line 327
   - Current visible state: external label exists; hint dropped.
   - Fix: set `hintText: hint`; remove dead `style`/`decoration`.
10. `lib/features/events/widgets/gig_form_fields.dart`
    - `AppTextField` lines 216, 474
    - Current visible state: external label exists; address hint dropped; state field mostly dead-prop cleanup.
    - Fix: move address hint to `hintText`; remove dead style/decoration in both.
11. `lib/features/events/widgets/gig_expense_subview.dart`
    - `AppTextField` lines 312, 455, 495
    - Current visible state: section labels visible; placeholders dropped.
    - Fix: move each placeholder to `hintText`; remove dead style/decoration.
12. `lib/features/setlists/widgets/custom_tuning_modal.dart`
    - `AppTextField` lines 374, 431
    - Current visible state: explicit section labels exist; placeholders dropped.
    - Fix: move placeholders to `hintText`; remove dead style/decoration.
13. `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart`
    - `AppTextField` line 742
    - Current visible state: label above input exists; placeholder dropped.
    - Fix: set computed hint via `hintText`; remove dead style/decoration.

### Priority 2: wrapper fields where hint/aux icons are primary affordance

14. `lib/features/auth/invite_screen.dart`
    - `AppTextField` line 464
    - Current visible state: `InputDecoration.labelText` ignored; label not rendered.
    - Fix: move `labelText: 'Email address'` to wrapper prop; optionally add explicit `hintText`.
15. `lib/features/setlists/setlist_detail_screen.dart` (oversized file: isolate edits)
    - `AppTextFormField` line 249 (rename dialog)
    - `AppTextField` line 2299 (search bar)
    - Current visible state: rename placeholder dropped; search hint/icons from decoration dropped.
    - Fix:
      - rename dialog: use `hintText: 'Enter setlist name'`
      - search: use `hintText: 'Filter songs...'`, wrapper `prefixIcon` and `suffixIcon` instead of `InputDecoration` icons.
16. `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
    - `AppTextField` lines 723, 751, 1419
    - Current visible state: placeholder-only fields missing hint text.
    - Fix: move each placeholder to wrapper `hintText`; remove dead style/decoration.
17. `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`
    - `AppTextField` line 492
    - Current visible state: create form lacks placeholder.
    - Fix: set `hintText: 'Setlist name'`; remove dead style/decoration.
18. `lib/features/setlists/widgets/print_options_bottom_sheet.dart`
    - `AppTextField` line 169
    - Current visible state: save-layout field lacks placeholder.
    - Fix: set `hintText: 'Layout name'`; remove dead style/decoration.
19. `lib/features/setlists/widgets/song_notes_drawer.dart`
    - `AppTextField` line 172
    - Current visible state: notes placeholder dropped.
    - Fix: set `hintText: 'Add notes for this song...'`; remove dead style/decoration.
20. `lib/features/setlists/widgets/bulk_add_songs_overlay.dart`
    - `AppTextField` line 486
    - Current visible state: CSV example placeholder dropped.
    - Fix: set wrapper `hintText` from existing string; remove dead style/decoration.
21. `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`
    - `AppTextField` lines 511, 990
    - Current visible state: both helper placeholders dropped.
    - Fix: move placeholder strings to wrapper `hintText`; remove dead style/decoration.
22. `lib/features/setlists/widgets/bpm_input_dialog.dart`
    - `AppTextField` line 133
    - Current visible state: BPM placeholder dropped.
    - Fix: set `hintText: 'Enter BPM (20-300)'`; remove dead style/decoration.
23. `lib/features/setlists/widgets/duration_input_dialog.dart`
    - `AppTextField` line 101
    - Current visible state: duration placeholder dropped.
    - Fix: set `hintText: 'MM:SS'`; remove dead style/decoration.
24. `lib/features/setlists/widgets/pause_creator.dart`
    - `AppTextField` lines 295, 505
    - Current visible state: custom reason and numeric hint dropped.
    - Fix: move hints to `hintText`; remove dead style/decoration.
25. `lib/features/setlists/widgets/add_to_setlist/pause_screen.dart`
    - `AppTextField` lines 412, 564
    - Current visible state: custom-purpose and duration hints dropped.
    - Fix: move hints to `hintText`; remove dead style/decoration.
26. `lib/features/profile/my_profile_screen.dart`
    - `AppTextField` line 459
    - Current visible state: custom-role prompt shown elsewhere; inline field hint dropped.
    - Fix: set `hintText: 'e.g. Rhythm Guitar'`; remove dead style/decoration.

### Priority 3: dead-prop cleanup (no explicit hint/label expected, but no-op props remain)

27. `lib/features/setlists/new_setlist_screen.dart`
    - `AppTextField` line 1289
    - Current visible state: no label/hint intended; decoration/style currently no-op anyway.
    - Fix: remove dead `style` and `decoration` args; preserve submit/edit callbacks.
28. `lib/features/setlists/widgets/masked_duration_input.dart`
    - `AppTextField` line 301
    - Current visible state: controlled masked input; decoration-only padding/border currently ignored.
    - Fix: remove dead `style`/`decoration`; keep formatter-driven behavior unchanged.
29. `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
    - `AppTextField` lines 1042, 1115
    - Current visible state: edit-inline title/artist mode; decoration-only border/padding currently ignored.
    - Fix: remove dead `style`/`decoration`; keep inline edit behavior and focus flow.

## Raw Material Text Field Migrations (Design-System Consistency)

### Raw `TextFormField` -> `AppTextFormField`

1. `lib/features/bands/band_form_screen.dart`
   - `TextFormField` line 1693 (`_buildTextInput` helper)
   - `TextFormField` line 2095 (`_buildEmailInput`)
   - Fix: migrate to `AppTextFormField`; map current hint text to `hintText`; preserve validator, focus, input formatters, keyboard/action settings.
2. `lib/features/feedback/bug_report_screen.dart`
   - `TextFormField` line 196
   - Fix: migrate description input to `AppTextFormField`; preserve `maxLines`, validator, keyboard/action.

### Raw `TextField` -> `AppTextField`

3. `lib/features/events/widgets/event_editor_helpers.dart`
   - `TextField` line 46 (`EventTextField` shared helper)
   - Fix: migrate helper internals to `AppTextField` so all helper consumers inherit wrapper behavior.
4. `lib/features/lyrics/widgets/lyrics_editor_sheet.dart`
   - `TextField` line 633
   - Fix: migrate multiline lyrics editor input to `AppTextField`; preserve `expands`, multiline keyboard/action, controller/focus.
5. `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
   - `TextField` lines 315, 710, 787, 832
   - Fix: migrate dialog/body text inputs to `AppTextField`; map existing hints to `hintText`; preserve capitalization/action.
6. `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`
   - `TextField` lines 358, 436
   - Fix: migrate payer/custom-name inputs to `AppTextField`; keep enabled/view-only logic.
7. `lib/shared/widgets/currency_input_field.dart`
   - `TextField` line 368
   - Fix: migrate internal input to `AppTextField`; keep custom formatter/controller behavior and clear button logic.

## Known Compliant Wrapper Calls (No Change)

1. `lib/features/contacts/widgets/az_search_field.dart` line 30 (`AppTextField` already uses wrapper-native props)
2. `lib/features/setlists/widgets/song_lookup_overlay.dart` line 491 (`AppTextField` already wrapper-native)

## Forbidden Areas / Guardrails for Engineer

1. Do not modify wrapper implementation contracts in:
   - `lib/components/ui/app_text_field.dart`
   - `lib/components/ui/app_text_form_field.dart`
     unless an explicit unsupported capability block is encountered (none expected from this audit).
2. Do not refactor unrelated UI/layout/theming while touching these files.
3. Do not change provider/repository/state architecture.
4. Do not modify database, migrations, edge functions, or app init order.
5. In oversized files (`lib/features/setlists/setlist_detail_screen.dart`), keep edits surgical at listed call sites only.

## Files To Modify (Engineer)

1. `lib/features/contacts/widgets/venue_form_screen.dart`
2. `lib/features/contacts/widgets/contact_form_screen.dart`
3. `lib/features/contacts/widgets/venue_contact_block.dart`
4. `lib/features/calendar/widgets/add_block_out_drawer.dart`
5. `lib/features/auth/login_screen.dart`
6. `lib/features/contacts/widgets/invite_members_screen.dart`
7. `lib/features/contacts/widgets/title_pill_selector.dart`
8. `lib/features/profile/my_profile_screen.dart`
9. `lib/features/profile/profile_screen.dart`
10. `lib/features/events/widgets/gig_form_fields.dart`
11. `lib/features/events/widgets/gig_expense_subview.dart`
12. `lib/features/setlists/widgets/custom_tuning_modal.dart`
13. `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart`
14. `lib/features/auth/invite_screen.dart`
15. `lib/features/setlists/setlist_detail_screen.dart`
16. `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
17. `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`
18. `lib/features/setlists/widgets/print_options_bottom_sheet.dart`
19. `lib/features/setlists/widgets/song_notes_drawer.dart`
20. `lib/features/setlists/widgets/bulk_add_songs_overlay.dart`
21. `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`
22. `lib/features/setlists/widgets/bpm_input_dialog.dart`
23. `lib/features/setlists/widgets/duration_input_dialog.dart`
24. `lib/features/setlists/widgets/pause_creator.dart`
25. `lib/features/setlists/widgets/add_to_setlist/pause_screen.dart`
26. `lib/features/setlists/new_setlist_screen.dart`
27. `lib/features/setlists/widgets/masked_duration_input.dart`
28. `lib/features/bands/band_form_screen.dart`
29. `lib/features/feedback/bug_report_screen.dart`
30. `lib/features/events/widgets/event_editor_helpers.dart`
31. `lib/features/lyrics/widgets/lyrics_editor_sheet.dart`
32. `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
33. `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`
34. `lib/shared/widgets/currency_input_field.dart`

## Files Explicitly Off-Limits

1. `lib/main.dart` (init/routing safety)
2. `lib/features/setlists/setlist_repository.dart` (architecture debt; unrelated)
3. Any file not listed in "Files To Modify"

## Regression Risk

`MEDIUM`

Rationale:

1. Change surface is wide (many UI call sites), but all changes are local parameter migrations.
2. No backend/database/state-model risk.
3. Largest residual risk is visual regressions in dialogs/sheets that previously attempted custom `InputDecoration` styles; those styles were already no-op in wrappers, so behavior shift should be limited.

## Engineer Task Breakdown (Ordered by Risk)

1. Fix Tony-reported breakage first:
   - `venue_form_screen.dart`, `contact_form_screen.dart`, `venue_contact_block.dart`
2. Fix auth/profile/contacts/event call sites where hint affordance is currently missing.
3. Fix setlist dialogs/overlays, with `setlist_detail_screen.dart` handled surgically.
4. Apply dead-prop cleanup-only edits (`new_setlist_screen.dart`, `masked_duration_input.dart`, inline editor fields in `song_details_bottom_sheet.dart`).
5. Migrate raw `TextFormField` call sites to `AppTextFormField`.
6. Migrate raw `TextField` call sites to `AppTextField`.
7. Run `flutter analyze` and targeted manual smoke checks for listed screens.
8. Document exact before/after behavior in `ENGINEER_REPORT.md` (especially label/hint restoration on Contacts/Venues).

## Verification Plan

1. Contacts flow:
   - Contacts -> Venues -> Add Venue: Name/Address/City/State/Phone/Notes labels visible.
   - Contacts -> Add Contact: Name/Company/Phone/Email/Notes labels visible.
   - Venue detail -> add/edit Venue Contact: Name/Phone/Email/Notes labels visible.
2. Auth/profile:
   - Login + Invite screens: placeholders/labels visible as expected.
3. Setlists:
   - Rename dialog and search bar in setlist detail show hint and search icons.
   - Song notes/details dialogs show intended placeholders.
4. Financials + Lyrics:
   - Inputs still accept text/formatters/validation after raw-field migration.
5. No regression:
   - Focus traversal, submit callbacks, validators, formatters remain intact.

## Out of Scope

1. Redesigning Forui wrapper API surface.
2. Re-styling all text fields to perfectly match prior Material `InputDecoration` visuals.
3. Any non-input UI refactor or architecture cleanup.

## Branch

Target branch name: `bug/forui-form-field-labels`
