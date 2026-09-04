# ARCHITECT_PLAN

## Feature Slug
`add-event-loadin-default-add-buttons`

## Feature Title
Add Event sheet — default Load-in to 2h before start, and consistent "add value" buttons

## Problem Summary
In the Add Event sheet (create + edit), four optional gig fields — Load-in, Contacts, Gig Pay, Expenses — should behave and look more consistently:

1. When the user opts in to Load-in, the initial value should be **2 hours before the event start time** (currently hard-coded to 6:00 PM regardless of start).
2. The **Load-in** "add" control should visually match the existing **Soundcheck** "add" button (rose-outlined pill).
3. **Contacts**, **Gig Pay**, and **Expenses** should each surface an "add a value" button in the same Soundcheck style. Today each of them uses a different visual pattern (some use `AppButton.outlined`, some use a muted placeholder container with tap-to-add text, some pair a header text button with a placeholder).

This is a UI consistency + a single default-value change. No data model, no persistence, no backend.

## Root Cause
**Confidence: HIGH** (verified in code).

- The Add Event sheet is a thin wrapper: `AddEditEventBottomSheet.show(...)` (in [lib/features/events/widgets/add_edit_event_bottom_sheet.dart](lib/features/events/widgets/add_edit_event_bottom_sheet.dart)) delegates entirely to `EventEditorDrawer` in [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart). All state lives in `_EventEditorDrawerState`.
- The **canonical** Soundcheck "add" button is defined **inline** in `EventEditorDrawer._buildScheduleSection` at [event_editor_drawer.dart#L3037-L3062](lib/features/events/widgets/event_editor_drawer.dart#L3037-L3062): `SizedBox(width: double.infinity, child: OutlinedButton(...))` with rose `Color(0xFFfb2c5a)` border (1.5px) and foreground, radius 8, `minimumSize: (double.infinity, 40)`, label `"Set soundcheck time"`.
- The **Load-in** "add" button is defined in [gig_form_fields.dart#L1414-L1454](lib/features/events/widgets/gig_form_fields.dart#L1414-L1454) as a `GestureDetector` wrapping a bordered `Container` with `context.colors.background` fill and `context.colors.border`, muted add-icon, label `"Set Load-in Time (Optional)"`. This is the visual mismatch.
- The Load-in **default value** is hard-coded to 6:00 PM in the `onLoadInTimeSet` callback in `_createGigFormFields` at [event_editor_drawer.dart#L2555-L2562](lib/features/events/widgets/event_editor_drawer.dart#L2555-L2562) (`_loadInHour = 6; _loadInMinutes = 0; _loadInIsPM = true;`). It reads no start-time state.
- **Contacts** ([gig_form_fields.dart#L1543](lib/features/events/widgets/gig_form_fields.dart#L1543) `_buildContactsSection`) shows a header row with an `AppButton` "Add" / "Add another" (text variant) plus, when empty, an `InkWell`/`Container` placeholder with muted text `"No contacts linked — tap to add one"`. No Soundcheck-style button anywhere.
- **Gig Pay** ([gig_form_fields.dart#L723](lib/features/events/widgets/gig_form_fields.dart#L723) `buildGigPayButton`) uses `AppButton` variant `outlined` with a dollar/edit icon. Label is `"Set Gig Pay"` when empty, `"$X.XX · payer name"` when set. Similar shape to Soundcheck but not the same style.
- **Expenses** ([gig_form_fields.dart#L751](lib/features/events/widgets/gig_form_fields.dart#L751) `buildExpensesSection`) mirrors Contacts: header `AppButton` "Add Expense" (text variant) plus empty-state bordered container `"No expenses added yet."`.
- No existing pattern in the codebase reactively updates a derived time field when start time changes. `endTime24` / `endTimeDisplay` are getters computed on render (not editable/stored fields). Load-in and Soundcheck are both initialize-on-tap-then-user-editable — the pattern is "hard-code on tap." That is the existing convention this feature will update.

## Existing System Analysis

### Add Event sheet composition
- `AddEditEventBottomSheet.show()` (backward-compat shim) → `showModalBottomSheet` hosting `EventEditorDrawer`.
- `EventEditorDrawer` orchestrates three form-type paths: gig, rehearsal, block-out. It composes:
  - `EventFormFields` (shared: error banner, date, start time, additional dates, duration).
  - `GigFormFields` (gig-only builder-methods class exposing `buildLoadInTimeSelector`, `buildContactsSection`, `buildGigPayButton`, `buildExpensesSection`, plus city/address/venue).
  - `RehearsalFormFields` (rehearsal-only — no Load-in, Contacts, Gig Pay, Expenses).
  - Inline Soundcheck row + `_buildSoundcheckTimePicker` inside `_buildScheduleSection` (gig-only, gated by `if (isGig)`).
- Section layout for gigs (per `_buildScheduleSection` / `_buildShowPrepSection` / `_buildMoneySection`):
  - **Schedule** section — `eventFormFields` (date/time/duration) + `gigFormFields.buildLoadInTimeSelector` + inline Soundcheck row.
  - **Show prep** section — `eventFormFields.buildSetlistSelector` + `gigFormFields.buildContactsSection`.
  - **Money** section — `gigFormFields.buildGigPayButton` + `gigFormFields.buildExpensesSection`.

### Start-time state, available at load-in-set time
`_EventEditorDrawerState` holds `_selectedHour` (1-12), `_selectedMinutes` (0/15/30/45), `_isPM` (bool) — updated whenever the user changes the start-time dropdowns or AM/PM toggle. These are readable synchronously from the `onLoadInTimeSet` callback.

### Prior related work (context)
- The `redesign-add-event-drawer` feature introduced Soundcheck as UI-only state and inlined its "add" button in `EventEditorDrawer`. QA flagged that `GigFormFields.buildSoundcheckRow` and 8 associated constructor params became dead code because the drawer inlined its own version. **This plan does not touch that dead surface** — that is pre-existing debt outside this feature's scope.

### Design decision (documented, not escalating)
"Load-in defaults to start − 2h" is implemented as: **computed at the moment the user taps "Set Load-in Time," using the current start-time state.** After that tap, load-in is user-editable via the existing dropdowns and does NOT continue to auto-track subsequent start-time changes.

Rationale:
- The feature input's parenthetical explicitly says "per whatever the existing pattern is for derived time defaults — Architect to confirm in code how start time and other derived times behave." The existing pattern is **initialize-on-tap**, not **reactive tracking**. `endTime24` is the only derived time in the drawer and it is a computed getter (not an editable field), so it does not constitute a reactive-tracking precedent for Load-in.
- Reactive tracking would require a new "was-user-set" state flag on load-in (to distinguish "still at default" from "user edited") and setState hooks on every start-time change to conditionally re-derive. That is out of proportion for the input's "keep the solution minimal" directive.
- Practically, users open the sheet, set start time, then opt into load-in — the tap-time computation gives the right answer for that flow. Load-in already stays put after a user edit; this change preserves that.

## Proposed Solution

1. Add one small reusable widget — `EventAddValueButton` — in [lib/features/events/widgets/event_editor_helpers.dart](lib/features/events/widgets/event_editor_helpers.dart) that reproduces the Soundcheck OutlinedButton style exactly.
2. Use `EventAddValueButton` in **five** places, guaranteeing visual consistency now and forever:
   - Load-in empty-state (gig_form_fields.dart).
   - Contacts empty-state (gig_form_fields.dart).
   - Gig Pay empty-state (gig_form_fields.dart).
   - Expenses empty-state (gig_form_fields.dart).
   - Soundcheck empty-state (event_editor_drawer.dart) — replaces the current inline OutlinedButton so the shared widget is the single source of truth.
3. For Contacts and Expenses (multi-value fields), suppress the pre-existing header `AppButton` add-CTAs (`"Add"`, `"Add Expense"`) when their lists are **empty**, to avoid duplicate CTAs alongside the new Soundcheck-style button. Keep those header buttons unchanged for the non-empty state ("Add another", "Add Expense" — the established multi-add ergonomics).
4. For Gig Pay (single-value field), use `EventAddValueButton` only in the empty state (no `gigPayDetails`). Keep the current `AppButton.outlined` for the value-set state — that button displays the value and re-opens the sheet to edit; it is not an "add" affordance.
5. Rewrite the body of `onLoadInTimeSet` in `_createGigFormFields` to compute `start − 2h` from `_selectedHour` / `_selectedMinutes` / `_isPM`, with correct 12-hour + AM/PM wraparound handling (e.g., start 1:00 AM → load-in 11:00 PM). Wrap-around uses a total-minutes-mod-1440 approach so it stays correct for every start value.

## Database Impact
**Not applicable.** No schema change, no new column, no RLS policy, no RPC, no edge function, no migration. Load-in is already a persisted column (`gigs.load_in_time`, text); this feature only changes the client-side default that populates it. Soundcheck remains UI-only.

## Flutter Architecture Changes
None structural. One new `StatelessWidget` (`EventAddValueButton`) added to the existing helpers file. No new providers, notifiers, controllers, or repositories. Existing composition (`EventEditorDrawer` orchestrating `GigFormFields` builder methods + inline sections) is preserved.

## Files to Create
None.

## Files to Modify
| File | Change |
| --- | --- |
| [lib/features/events/widgets/event_editor_helpers.dart](lib/features/events/widgets/event_editor_helpers.dart) | Add `EventAddValueButton` — a small `StatelessWidget` that wraps `SizedBox(width: double.infinity, child: OutlinedButton(...))` with the Soundcheck-canonical style. Constructor: `label` (String), `onPressed` (VoidCallback?), `isSaving` (bool). Disable button when `isSaving == true`. |
| [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) | (1) `_buildLoadInTimeSelector` — replace the empty-state `GestureDetector`/`Container` block (the `loadInHour == null` branch) with the "Load-in Time" label + `EventAddValueButton(label: 'Set Load-in Time', onPressed: onLoadInTimeSet, isSaving: isSaving)`. Populated-state branch (time-picker Row) unchanged. (2) `buildGigPayButton` — when `hasDetails == false`, render the "Gig Pay (optional)" label + `EventAddValueButton(label: 'Set Gig Pay', onPressed: onGigPayTap, isSaving: isSaving)`. Keep the current `AppButton.outlined` branch for the value-set state. (3) `_buildContactsSection` — hide the header "Add" `AppButton` when `contactAutocompleteControllers.isEmpty`; replace the empty-state `InkWell`/`Container` placeholder with `EventAddValueButton(label: 'Add a contact', onPressed: onAddContact, isSaving: isSaving)`. Non-empty state (header "Add another" + per-row autocomplete inputs) unchanged. (4) `buildExpensesSection` — hide the header "Add Expense" `AppButton` when `gigExpenses.isEmpty`; replace the empty-state placeholder container ("No expenses added yet.") with `EventAddValueButton(label: 'Add an expense', onPressed: (isSaving \|\| !canEditExpenses) ? null : onAddExpense, isSaving: isSaving)`. Non-empty state unchanged. |
| [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) | (1) In `_buildScheduleSection` — replace the inline `SizedBox`/`OutlinedButton` for Soundcheck's empty state (the `_soundcheckHour == null` branch inside the `AnimatedSize`) with `EventAddValueButton(label: 'Set soundcheck time', onPressed: () => setState(() { _soundcheckHour = 6; _soundcheckMinutes = 0; _soundcheckIsPM = false; }), isSaving: _isSaving)`. The `AnimatedSize` wrapper, the section label, and the populated-state Row (time pickers + Clear button) stay unchanged. (2) In `_createGigFormFields` — rewrite the body of `onLoadInTimeSet` to compute `start − 2h` from `_selectedHour` / `_selectedMinutes` / `_isPM` with wrap-around. The other load-in callbacks (`onLoadInTimeCleared`, `onLoadInHourChanged`, `onLoadInMinutesChanged`, `onLoadInAmPmChanged`) stay unchanged. |

## Files Off-Limits
| File / area | Why |
| --- | --- |
| [lib/features/events/models/event_form_data.dart](lib/features/events/models/event_form_data.dart) | Model unchanged. No new fields, no default-value logic in the model. |
| [lib/features/events/events_repository.dart](lib/features/events/events_repository.dart) | Persistence unchanged. `load_in_time` continues to be written from `formData.loadInTimeDisplay`. |
| Dead `buildSoundcheckRow` + 8 unused constructor params in [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) (approx. lines 405–415, 503–511, 601–716) | Pre-existing debt from the `redesign-add-event-drawer` engineer/architect divergence. Not this feature's concern — do NOT delete or refactor. |
| [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart) | Rehearsal path is unaffected — none of the four fields exist on rehearsals. |
| Any file under `supabase/` | No DB impact. |
| Any file outside `lib/features/events/widgets/` | Scope is the event editor UI only. |
| `lib/components/ui/app_button.dart` and `AppButton` variants | Not extending or changing the shared button system — the Soundcheck style is unusual enough (specific rose 1.5px outline) that a purpose-built local widget is cleaner than a new `AppButton` variant. |

## Change Budget
| File | Expected net line delta |
| --- | --- |
| `event_editor_helpers.dart` | +~40 (one small `StatelessWidget`) |
| `gig_form_fields.dart` | between −20 and +30 (four spots: net roughly flat — removing bordered-Container placeholder markup, adding a single widget call, adding a small `if (list.isEmpty)` guard around header buttons) |
| `event_editor_drawer.dart` | between −25 and +5 (Soundcheck inline OutlinedButton block replaced by one call; `onLoadInTimeSet` body grows by ~8 lines) |

- Expected new files: 0.
- Expected new public classes/methods: 1 (`EventAddValueButton`).
- Expected new dependencies: 0.

## System Impact Map
| System | Affected? |
| --- | --- |
| Gigs (add/edit) | Yes — Load-in / Contacts / Gig Pay / Expenses / Soundcheck buttons restyled; Load-in default value changed |
| Rehearsals | No — none of these fields exist on the rehearsal path; Soundcheck refactor is inside `if (isGig)` block |
| Block Out | No — `_buildBlockOutForm` is a separate branch |
| Setlists | No |
| Members | No |
| Auth / session / routing / init order | No |
| Notifications | No |
| Platforms (iOS / Android / macOS / Web) | No platform-conditional code touched; shared Flutter widgets only |

## Regression Risk
**LOW.**

- Pure UI restyling in four locations + one single computed-default change.
- No auth, session, routing, init-order, DB, RLS, or RPC changes.
- The `onLoadInTimeSet` change only fires when the user explicitly taps "Set Load-in Time" (i.e., when `_loadInHour == null`); pre-existing DB-loaded load-in values are unaffected because the callback is not triggered for them.
- The visible behavioral change: with the drawer's default start time of 7:00 PM, tapping "Set Load-in Time" now produces **5:00 PM** instead of **6:00 PM**. This is the asked-for behavior.
- Suppressing the header add buttons for Contacts / Expenses in the empty state is a UI-only conditional; the non-empty flows retain the identical header add button.

## Engineer Task Breakdown
Ordered, atomic. Each step is a single logical edit.

1. **Add `EventAddValueButton` to `event_editor_helpers.dart`.** Small `StatelessWidget`. Constructor takes `String label`, `VoidCallback? onPressed`, `bool isSaving`. Renders `SizedBox(width: double.infinity, child: OutlinedButton(onPressed: isSaving ? null : onPressed, style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFfb2c5a), width: 1.5), foregroundColor: const Color(0xFFfb2c5a), minimumSize: const Size(double.infinity, 40), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: Text(label)))`. Match the existing Soundcheck inline style exactly.

2. **Refactor Load-in empty-state in `gig_form_fields.dart` `_buildLoadInTimeSelector`.** In the `loadInHour == null || loadInMinutes == null || loadInIsPM == null` branch, replace the current `GestureDetector`/`Container` block with a `Column` that has the existing "Load-in Time" label (`AppTextStyles.footnote`, `context.colors.textSecondary`, followed by the existing `SizedBox(height: 6)`) + `EventAddValueButton(label: 'Set Load-in Time', onPressed: onLoadInTimeSet, isSaving: isSaving)`. Leave the populated-state branch (time-picker Row) completely untouched.

3. **Refactor `buildGigPayButton` in `gig_form_fields.dart`.** When `hasDetails == false`, render the existing "Gig Pay (optional)" label + `SizedBox(height: 6)` + `EventAddValueButton(label: 'Set Gig Pay', onPressed: onGigPayTap, isSaving: isSaving)`. When `hasDetails == true`, keep the current `AppButton.outlined` (label = value string, icon = edit) branch unchanged.

4. **Refactor `_buildContactsSection` in `gig_form_fields.dart`.** Wrap the header `AppButton` in `if (contactAutocompleteControllers.isNotEmpty)`. Replace the empty-state `InkWell`/`Container` placeholder block with `EventAddValueButton(label: 'Add a contact', onPressed: onAddContact, isSaving: isSaving)`. Leave the non-empty per-row autocomplete rendering unchanged. Preserve the existing "Loading your shared contacts..." branch — if `isLoadingContacts && contactAutocompleteControllers.isEmpty`, render a small muted text placeholder instead of the button (that transient loading state should not show an actionable button).

5. **Refactor `buildExpensesSection` in `gig_form_fields.dart`.** Wrap the header `AppButton` "Add Expense" in `if (gigExpenses.isNotEmpty)`. Replace the empty-state placeholder container ("No expenses added yet.") with `EventAddValueButton(label: 'Add an expense', onPressed: (isSaving || !canEditExpenses) ? null : onAddExpense, isSaving: isSaving)`. When `!showExpensesSection`, keep the current `SizedBox.shrink()` early return. Leave the non-empty per-expense rendering unchanged.

6. **Refactor Soundcheck inline OutlinedButton in `event_editor_drawer.dart` `_buildScheduleSection`.** Inside the `AnimatedSize` at approximately [event_editor_drawer.dart#L3037-L3062](lib/features/events/widgets/event_editor_drawer.dart#L3037-L3062), replace the `SizedBox`/`OutlinedButton` (the `_soundcheckHour == null` branch) with `EventAddValueButton(label: 'Set soundcheck time', onPressed: () => setState(() { _soundcheckHour = 6; _soundcheckMinutes = 0; _soundcheckIsPM = false; }), isSaving: _isSaving)`. The populated-state Row (time pickers + Clear TextButton) stays exactly as-is. Import `EventAddValueButton` if the file does not already import from `event_editor_helpers.dart`.

7. **Rewrite `onLoadInTimeSet` body in `event_editor_drawer.dart` `_createGigFormFields`.** Replace the current three-line hard-coded assignment (lines ~2555-2562) with:

    ```dart
    onLoadInTimeSet: () {
      final start24 = _isPM && _selectedHour != 12
          ? _selectedHour + 12
          : (!_isPM && _selectedHour == 12 ? 0 : _selectedHour);
      final startTotal = start24 * 60 + _selectedMinutes;
      final loadInTotal = (startTotal - 120 + 24 * 60) % (24 * 60);
      final loadIn24 = loadInTotal ~/ 60;
      final loadInMin = loadInTotal % 60;
      final loadInPm = loadIn24 >= 12;
      int loadIn12 = loadIn24 % 12;
      if (loadIn12 == 0) loadIn12 = 12;
      setState(() {
        _loadInHour = loadIn12;
        _loadInMinutes = loadInMin;
        _loadInIsPM = loadInPm;
      });
      _markDirty();
    },
    ```

    Keep `onLoadInTimeCleared`, `onLoadInHourChanged`, `onLoadInMinutesChanged`, `onLoadInAmPmChanged` unchanged.

## Verification Plan

### Tier 1 (pre-deploy, no external service needed)
- **Static analysis:** `flutter analyze` passes with no new warnings or errors on `event_editor_helpers.dart`, `gig_form_fields.dart`, `event_editor_drawer.dart`.
- **Existing test suite:** `flutter test test/features/events/` continues to pass unchanged. No test in this directory currently drives the Load-in default or the four affected buttons directly, so no test file rewrite is expected.
- **Manual smoke — macOS + Web (either dev target) — Add Event → Gig:**
  1. Open Add Event, select Gig. Confirm start time defaults to 7:00 PM.
  2. Scroll to Schedule section. Confirm the Load-in "Set Load-in Time" button visually matches the Soundcheck "Set soundcheck time" button (same rose outline, same height, same shape).
  3. Tap "Set Load-in Time". Confirm time pickers appear showing **5:00 PM**.
  4. Tap Load-in "Clear". Confirm the button returns.
  5. Change start time to 8:00 PM via the dropdowns / PM toggle. Tap "Set Load-in Time" again. Confirm time pickers show **6:00 PM**.
  6. Repeat with start time 1:00 AM → confirm Load-in shows **11:00 PM**. (Wraparound.)
  7. Repeat with start time 12:00 PM → confirm Load-in shows **10:00 AM**.
  8. Repeat with start time 12:15 AM → confirm Load-in shows **10:15 PM**.
  9. Scroll to Show prep section. Confirm Contacts empty state shows a Soundcheck-styled "Add a contact" button (no separate header "Add" button, no muted placeholder container). Tap it — confirm one contact autocomplete row appears and a header "Add another" `AppButton` now appears above.
  10. Scroll to Money section. Confirm Gig Pay empty state shows a Soundcheck-styled "Set Gig Pay" button. Confirm Expenses empty state shows a Soundcheck-styled "Add an expense" button (no separate header "Add Expense" button, no "No expenses added yet." placeholder). Tap the Expenses button — confirm the expense editor opens; save one expense; return; confirm the header "Add Expense" `AppButton` now appears above the expense row.
  11. Scroll to Soundcheck. Confirm its "Set soundcheck time" button still renders and still opens the time pickers when tapped — no visual regression from switching to the shared widget.
- **Manual regression — macOS — Add Event → Rehearsal:** Confirm the Soundcheck / Load-in / Contacts / Gig Pay / Expenses controls are NOT rendered (rehearsal path is unaffected).
- **Manual regression — macOS — Edit an existing gig that has a saved Load-in time:** Confirm the time-pickers render (not the button), the saved value is displayed correctly, and the save flow still writes `load_in_time` unchanged.

### Tier 2 (post-deploy)
Not applicable. No new backend interaction, no new function, no new schema.

## QA Regression Areas
- Add Event → Gig create: all five refactored buttons render in the Soundcheck style in empty state; populated states render correctly.
- Add Event → Gig create → save: written `load_in_time` string in `gigs.load_in_time` still uses the "H:MM AM/PM" format (verify one save).
- Add Event → Gig edit: existing load-in / contacts / gig_pay / expenses values still pre-populate correctly (via `EventFormData.fromGig`).
- Add Event → Rehearsal create + edit: unchanged flows.
- Add Event → Block Out create + edit: unchanged flows.
- Contacts multi-add ergonomics: after adding the first contact, the header "Add another" `AppButton` appears and functions.
- Expenses multi-add ergonomics: after adding the first expense, the header "Add Expense" `AppButton` appears and functions.
- Load-in "Clear" still returns to the (new) Soundcheck-style empty-state button.
- Start-time boundary values: 7:00 PM → 5:00 PM (default case); 1:00 AM → 11:00 PM (wraparound); 12:00 PM → 10:00 AM; 12:15 AM → 10:15 PM.
- Soundcheck default value (6:00 AM) is unchanged — this feature does not change Soundcheck behavior.

## Rollout Strategy
Standard branch → PR → CI (`flutter analyze` + tests) → review → merge to `main` → auto-deploy via existing pipeline. No feature flag, no DB migration, no config change, no cache invalidation.

## Out of Scope
- Persisting Soundcheck time to the database (still UI-only per the `redesign-add-event-drawer` scope).
- Removing the pre-existing dead `GigFormFields.buildSoundcheckRow` public surface + 8 unused constructor parameters (pre-existing debt).
- Any refactor of `AppButton`, `AppButtonVariant`, or `SheetFooter` primary/cancel buttons.
- Any change to the "Add another" / "Add Expense" header `AppButton.text` styling — kept intact for the non-empty multi-add state.
- Any change to how Load-in is persisted, or making Load-in reactively track subsequent start-time changes after being explicitly set.
- Any change to Rehearsal or Block Out event types.
- Adding a widget test file specifically for `EventAddValueButton` — the widget is small enough that visual/manual verification via the smoke steps above is proportional; a dedicated test file would be over-scope.

---

## Amendment (label + sizing)

**Amendment date:** 2026-09-04. **Status:** Additive — does not alter any preceding section's design intent.

### Verbatim requirement
> "Change the button labels to: Set load-in time, Set soundcheck time, Add contact, Add expense. Ensure labels are all the same size (14px)"

### Scope
Post-QA-approval polish on the shared `EventAddValueButton` introduced by the original plan. Two things:
1. Tighten five button labels to a shorter, sentence-case-plus-verb form (Tony's list, plus Gig Pay).
2. Guarantee all five labels render at exactly 14px by pinning the size in the shared widget's `Text` style — one source of truth for all call-sites.

No new files, no DB, no new dependencies, no changes to the Off-Limits table.

### Final label strings (verbatim, all five)

Verified against current live call-sites — the five `EventAddValueButton` usages in [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) (lines 738, 801, 1439, 1568) and [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L3050).

| Button | Current label (in code) | Final label (verbatim) | Change? |
| --- | --- | --- | --- |
| Load-in (empty state) | `'Set Load-in Time'` | `'Set load-in time'` | **Yes** — sentence case; drop hyphenated proper-noun casing |
| Soundcheck (empty state) | `'Set soundcheck time'` | `'Set soundcheck time'` | No — already matches |
| Contacts (empty state) | `'Add a contact'` | `'Add contact'` | **Yes** — drop the article |
| Gig Pay (empty state) | `'Set Gig Pay'` | `'Set Gig Pay'` | No — preserved intentionally (see decision below) |
| Expenses (empty state) | `'Add an expense'` | `'Add expense'` | **Yes** — drop the article |

### Gig Pay label decision (documented, not escalating)

Tony's list did not include Gig Pay. The instruction was: keep the existing "Set Gig Pay" text (do not invent a new label that wasn't requested) but ensure Gig Pay still receives the same 14px sizing as the other four.

Reasoning this is not a UX ambiguity worth flagging:
- The section label directly above the button is `'Gig Pay (optional)'` — treating "Gig Pay" as a Title-Case product concept. Lowercasing the button to "Set gig pay" would break internal consistency inside the same visual group.
- The other four labels use lowercase common nouns ("load-in time", "soundcheck time", "contact", "expense"). "Gig Pay" is a proper product-concept name in this codebase (searchable, referenced elsewhere as `Gig Pay`), not a common noun — so preserving Title Case is the internally-consistent call.
- Confidence: **HIGH** that Tony's default ("keep 'Set Gig Pay', apply 14px") is the right answer. No flag.

### Font-size mechanism (single source of truth)

**Location:** [lib/features/events/widgets/event_editor_helpers.dart](lib/features/events/widgets/event_editor_helpers.dart#L139) — the `EventAddValueButton.build` method's `Text` child.

**Current code (verified):**
```dart
child: Text(label),
```
No explicit `style`. `OutlinedButton`'s default `textStyle` (Material 3 `labelLarge`) resolves this to approximately 14sp / weight 500 — **theme-dependent and not guaranteed**. That is exactly the fragility this amendment removes.

**New code:**
```dart
child: Text(
  label,
  style: const TextStyle(fontSize: AppFontSizes.subhead),
),
```

**Token choice:** `AppFontSizes.subhead` (defined at [lib/app/theme/design_tokens.dart#L320](lib/app/theme/design_tokens.dart#L320) as `static const double subhead = 14.0;`) is the app's canonical 14px scale token. It is the *only* `const double` value of `14.0` in `AppFontSizes` and its docstring in `design_tokens.dart` says it "absorbs old 15px uses". No `AppTextStyles.*` preset resolves to 14px, so a bare `TextStyle(fontSize: AppFontSizes.subhead)` is the correct minimal expression — and works as `const` because `AppFontSizes.subhead` is `const`.

**Why not specify weight or family:** Leaving weight and font family unset means the label continues to inherit the `OutlinedButton`'s default weight/family from theme. This amendment's stated ask is size only ("all the same size (14px)"). Specifying just `fontSize` gives us the guarantee the amendment requires without introducing any other visual delta that could be a QA surprise.

**Why the shared widget is the single source of truth:** Because all five call-sites already render through `EventAddValueButton`, applying the size override in `event_editor_helpers.dart` makes all five buttons identical by construction — the Engineer cannot forget one and the compiler enforces uniformity. Zero call-site edits are needed to enforce sizing.

**Import status:** No new import needed. `event_editor_helpers.dart` already imports `../../../app/theme/design_tokens.dart` (see line 4 of that file), which exports `AppFontSizes`.

### Files to Modify (this amendment)

| File | Change |
| --- | --- |
| [lib/features/events/widgets/event_editor_helpers.dart](lib/features/events/widgets/event_editor_helpers.dart) | In `EventAddValueButton.build`, replace `child: Text(label),` with `child: Text(label, style: const TextStyle(fontSize: AppFontSizes.subhead)),`. This is the *only* font-size edit in the amendment. |
| [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) | Three literal-string edits at the three affected `EventAddValueButton` call-sites: `'Set Load-in Time'` → `'Set load-in time'` (line ~1439); `'Add a contact'` → `'Add contact'` (line ~1568); `'Add an expense'` → `'Add expense'` (line ~801). `'Set Gig Pay'` at line ~738 is unchanged. |
| [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) | **No amendment edit.** Verified: the Soundcheck call-site at line 3050 already reads `label: 'Set soundcheck time'`. The file remains modified by the original plan's Tasks 6 and 7, but this amendment adds nothing to it. Documented here explicitly so the Engineer does not go looking for a change to make. |

Same file set as the original plan — no expansion, no new file, no touching the Off-Limits table.

### Change Budget (this amendment)

| File | Expected net line delta (amendment only) |
| --- | --- |
| `event_editor_helpers.dart` | +2 to +3 (`Text(label)` grows into a 3-line `Text` with `style:`) |
| `gig_form_fields.dart` | 0 (three literal-string replacements, no line count change) |
| `event_editor_drawer.dart` | 0 |

- Expected new files: 0.
- Expected new public classes/methods: 0.
- Expected new dependencies: 0.

### Amendment Task Breakdown

Ordered, atomic. Each step is a single logical edit.

1. **Pin 14px in the shared widget.** In [lib/features/events/widgets/event_editor_helpers.dart](lib/features/events/widgets/event_editor_helpers.dart), inside `EventAddValueButton.build`, change the `OutlinedButton` `child` from `Text(label)` to `Text(label, style: const TextStyle(fontSize: AppFontSizes.subhead))`. Do not add any weight, family, color, height, or letter-spacing. No import change needed. Do not touch the `OutlinedButton.styleFrom` block, the `SizedBox`, or the constructor.

2. **Load-in label.** In [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) around line 1439, change `label: 'Set Load-in Time'` to `label: 'Set load-in time'`. Do not touch the `Text('Load-in Time', ...)` section-label directly above it — the *section* label stays Title Case (that's the field name, not the button).

3. **Contacts label.** In [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) around line 1568, change `label: 'Add a contact'` to `label: 'Add contact'`. Do not touch the surrounding `if (isLoadingContacts) ... else` structure or the `Text('Loading your shared contacts...')` branch.

4. **Expenses label.** In [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) around line 801, change `label: 'Add an expense'` to `label: 'Add expense'`. Do not touch the enclosing `if (gigExpenses.isEmpty)` guard or the `onPressed: (isSaving || !canEditExpenses) ? null : onAddExpense` expression.

5. **Verify Soundcheck & Gig Pay untouched.** No code edit — but the Engineer must visually confirm before opening the PR that (a) [event_editor_drawer.dart#L3050](lib/features/events/widgets/event_editor_drawer.dart#L3050) still reads `label: 'Set soundcheck time'` and (b) [gig_form_fields.dart#L738](lib/features/events/widgets/gig_form_fields.dart#L738) still reads `label: 'Set Gig Pay'`. If either has drifted from those exact strings, restore them.

### Amendment Verification Plan

**Tier 1 (pre-deploy):**

- **Static analysis:** `flutter analyze` passes with no new warnings or errors on `event_editor_helpers.dart` or `gig_form_fields.dart`.
- **Existing tests:** `flutter test test/features/events/` continues to pass.
- **Label-string grep (deterministic, no simulator needed):**
  - `grep -rn "EventAddValueButton" lib/features/events/widgets/` must return exactly 5 usages (unchanged from the original plan's implementation).
  - `grep -rn "label: '" lib/features/events/widgets/ | grep EventAddValueButton -A0 -B0` — QA reads the surrounding lines and confirms the five labels resolve to, in any order: `'Set load-in time'`, `'Set soundcheck time'`, `'Add contact'`, `'Set Gig Pay'`, `'Add expense'`. No other strings.
  - Negative check: `grep -rn "'Set Load-in Time'\|'Add a contact'\|'Add an expense'" lib/features/events/widgets/` must return **zero** matches. If any survive, an edit was missed.
- **Font-size code inspection:** the diff on `event_editor_helpers.dart` must show the `Text` child gaining `style: const TextStyle(fontSize: AppFontSizes.subhead)`. This is how QA confirms "the change is real" — the previous rendering may have already landed near 14px through Material 3's `labelLarge` default, so visual size alone is not a reliable signal; the diff is. The presence of `AppFontSizes.subhead` in the widget's `Text` style is the load-bearing evidence.
- **Manual smoke — macOS (or Web) — Add Event → Gig:**
  1. Open Add Event → Gig. Confirm the Load-in empty-state button reads exactly `Set load-in time`.
  2. Confirm the Soundcheck empty-state button reads exactly `Set soundcheck time`.
  3. Confirm the Gig Pay empty-state button reads exactly `Set Gig Pay` (Title Case preserved).
  4. Confirm the Contacts empty-state button (after any "Loading..." transient clears) reads exactly `Add contact`.
  5. Confirm the Expenses empty-state button reads exactly `Add expense`.
  6. Visually compare all five buttons side-by-side (screenshotting the sheet is fine): label text must appear at identical size. If any label reads visibly larger or smaller than the others, the shared-widget override was not applied correctly — this is the whole point of the amendment.
  7. All other behaviors from the original plan's smoke (Load-in default `start − 2h`, wrap-around cases, header CTA suppression rules, populated-state pickers, Clear-button behavior) must continue to pass unchanged.
- **Manual regression — macOS — Add Event → Rehearsal / Block Out:** Confirm none of the five buttons appear on these paths (unchanged from original plan).

**Tier 2 (post-deploy):** Not applicable — no backend, no schema, no RPC.

### Amendment QA Regression Areas

In addition to the original plan's QA Regression Areas (all still apply unchanged):

- All five `EventAddValueButton` labels match the verbatim strings in the table above — no leftover title-case or article-carrying labels anywhere in `lib/features/events/widgets/`.
- All five buttons render at visually identical label size on the Add Event → Gig sheet. If any button appears larger/smaller than its neighbors, the shared-widget size override was skipped or overridden at a call-site.
- The section labels *above* the buttons (`'Load-in Time'`, `'Gig Pay (optional)'`, `'Contacts'`, `'Expenses'`, plus the Soundcheck section label) are untouched — those are field labels, not buttons, and their `AppTextStyles.footnote` styling is unchanged.

### Amendment Out of Scope

- Any change to Gig Pay's label wording beyond keeping it as "Set Gig Pay". If a future design pass wants "Set gig pay" (all lowercase) for strict pattern consistency, that is a separate feature.
- Any change to the label styling *other than* size (no color, weight, family, letter-spacing, or line-height changes).
- Applying 14px to any button in the app other than the five `EventAddValueButton` usages. The override is intentionally scoped to the shared widget only.
- Restyling the section labels above the buttons.
- Anything covered by the original plan's own Out of Scope section, which remains authoritative.
