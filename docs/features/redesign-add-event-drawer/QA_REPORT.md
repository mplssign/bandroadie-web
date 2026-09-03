# QA Report

**Feature Slug:** redesign-add-event-drawer
**Feature Title:** Redesign Add/Edit Event Drawer with Forui Dark Theme
**Branch:** feature/redesign-add-event-drawer
**Cycle:** 1
**QA Date:** 2026-09-03

---

## Final Verdict

**APPROVED** (with Warnings — none rise to Critical)

Manager's four pass criteria all met. Warnings are tracked for the next cycle or follow-up PR.

---

## Validation Summary

| Check | Result |
|---|---|
| `flutter analyze` 0 errors | PASS — 0 errors |
| Analyzer clean at every severity in diff files | PARTIAL — 1 newly-introduced `info` in event_editor_actions.dart; pre-existing `info` in touched files (see Analyzer Results) |
| Approved files only changed | WARNING — `button_group_grid.dart` in diff, not in plan's approved list |
| Off-limits files untouched | PASS — add_edit_event_bottom_sheet.dart, event_form_data.dart, events_repository.dart all clean |
| Structural checks (drawer) | PASS — see below |
| Soundcheck vars not in `_buildFormData()` | PASS — confirmed by code-path analysis |
| Slugs match (plan / report / branch) | PASS — all three: `redesign-add-event-drawer` / `feature/redesign-add-event-drawer` |
| No duplicate QA session | PASS — no prior QA_REPORT.md |
| No secrets / debug artifacts introduced | PASS — 0 new `debugPrint`/`TODO`/`FIXME` lines in diff |

---

## Architect Scope Review

Plan specifies 7 files to modify + 1 file to create. Engineer modified 8 files + created 1:

| File | Plan | Actual | Status |
|---|---|---|---|
| event_editor_drawer.dart | modify | modified | ✓ |
| event_type_selector.dart | modify | modified | ✓ |
| event_editor_helpers.dart | modify | modified | ✓ |
| event_editor_actions.dart | modify | modified | ✓ |
| gig_form_fields.dart | modify | modified | ✓ |
| event_form_fields.dart | modify | modified (import only; restyle deferred) | ⚠ partial |
| rehearsal_form_fields.dart | modify | modified (import only; restyle deferred) | ⚠ partial |
| event_editor_theme.dart | create | created (untracked) | ✓ |
| **button_group_grid.dart** | **not listed** | **modified** | ⚠ extra |

Engineer Report acknowledges the deviations on event_form_fields.dart and rehearsal_form_fields.dart. `button_group_grid.dart` is not mentioned.

---

## Completeness Check

### Completed tasks
- **Task 1** — `event_editor_theme.dart` created with `buildEventEditorTheme()` returning `FThemeData`, all required `kEd*` tokens present (`kEdSurface`, `kEdCardBg`, `kEdCardBorder`, `kEdInputFill`, `kEdSuccessBg`, `kEdSuccessBorder`, `kEdDangerBg`, `kEdDangerBorder`, `kEdMutedForegroundFaint`). ✓
- **Task 2** — `event_type_selector.dart` restyled. ✓
- **Task 3** — Soundcheck state vars added to `_EventEditorDrawerState` at lines 134–136. ✓
- **Task 4** — `build()` restructured: `FTheme` wrap, `ConstrainedBox(maxWidth: 680)`, `_buildStickyHeader`, `_buildScrollableBody`, six `_SectionCard` items for gig, three for rehearsal, `GigExpenseSubView` path preserved. ✓
- **Task 5** — `_SectionCard` private widget at line 3617. ✓
- **Task 8** — `EventEditorBottomActions` has new optional `String? summary` param; `_buildSummaryText()` wired at line 3132. ✓
- **Task 9** — `GigFormFields.buildSoundcheckRow` added with all specified props/callbacks. ✓ (but see Warning 2 below)
- **Task 11** — `flutter analyze` returns 0 errors. ✓

### Deferred tasks (acknowledged by Engineer)
- **Task 6** (`event_form_fields.dart` restyle) — date button, time selects, duration stepper, notes textarea, setlist chips retain previous styling. Import of `event_editor_theme.dart` added but no visual changes applied.
- **Task 10** (`rehearsal_form_fields.dart` restyle) — rehearsal fields render inside new section cards but without spec-compliant input styling.

---

## Behavior Verification

*Method: code-path analysis. No runtime device testing performed.*

- `FTheme(data: buildEventEditorTheme(), ...)` wraps the entire drawer at line 2702 — confirmed in code.
- `ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680))` at line 2706 — confirmed in code.
- `_buildStickyHeader` (line 2772) and `_buildScrollableBody` (line 2867) are both called from `build()` — confirmed in code.
- `_SectionCard` at line 3617 is private (`_`) — confirmed.
- Section cards titled 'The gig', 'Schedule', 'Location', 'Show prep', 'Money', 'Notes' at lines 2896–2909 — confirmed.
- Soundcheck state (`_soundcheckHour`, `_soundcheckMinutes`, `_soundcheckIsPM`) declared at lines 134–136, initialised inline, used in `_buildScheduleSection` via `AnimatedSize` — confirmed. **Not present in `_buildFormData()`** (lines 1201–1257 inspected; no soundcheck vars) — confirmed.
- `GigExpenseSubView` at line 2961: replaces normal body when `_isEditingExpense` — preserved — confirmed.
- `viewOnly` prop used in 9 places; `_forcePotentialOnly` in 3 places — confirmed.
- `_buildSummaryText()` defined at line 3160, called at line 3132 — confirmed.

Bug-fix root cause: N/A (this is a planned visual redesign).

---

## Regression Check

| Area | Risk | Notes |
|---|---|---|
| Gig save/delete | LOW | No save/delete code paths changed — code-path confirmed |
| Rehearsal save/delete | LOW | Same |
| Block-out save/delete | LOW | `_buildBlockOutForm()` unchanged, no `_SectionCard` wrapper on it |
| `GigExpenseSubView` path | LOW | Preserved as body-replacement for `_isEditingExpense` — code confirmed |
| `viewOnly` mode | LOW | Guards unchanged |
| RBAC / `_forcePotentialOnly` | LOW | Both present and wired as before |
| Multi-date gig | LOW | State vars/rendering not touched |
| Contact autocomplete | LOW | Props passed identically |
| Recurring rehearsal | LOW | State vars/rendering not touched |
| Setlist picker | LOW | `buildShowPrepSection` delegates to existing `buildSetlistSelector` |
| Availability grid | MEDIUM | `button_group_grid.dart` now uses `kEd*` tokens — old `context.colors.success` / `AppColors.primary` replaced with `kEdSuccessBg`/`kEdDangerBg`; visual change only, no state logic changed |
| Auth / Session | UNAFFECTED | — |
| Platform parity | LOW | No platform-conditional code introduced |
| Provider / init order | LOW | No new providers; `initState` / `dispose` order unchanged |

Overall regression risk: **MEDIUM** (per plan §10 — complex stateful widget; code review cannot substitute for manual QA testing of all three event types).

---

## Database Safety

Not applicable. Pure UI change. No migrations, RLS, RPC, or edge functions.

---

## Analyzer Results

`flutter analyze --no-pub` — **0 errors, 0 warnings**.

Info-level violations in diff-touched files:

| File | Line | Lint | New or Pre-existing? |
|---|---|---|---|
| event_editor_actions.dart | 39 | `prefer_const_constructors` — `TextStyle(...)` without `const` | **New** (in added line) |
| event_form_fields.dart | 365, 371, 583, 714 | `avoid_redundant_argument_values`, `prefer_const_constructors` | Pre-existing (lines not in diff hunks) |
| rehearsal_form_fields.dart | 288, 311, 427, 446, 579, 911 | `avoid_redundant_argument_values`, `unnecessary_null_checks` | Pre-existing (lines not in diff hunks) |

The newly-introduced violation at event_editor_actions.dart:39 is logged as a Suggestion below.

---

## Test Results

No tests specified in the Manager's check list for this cycle. Plan §12 Tier 1 calls for widget tests in `test/features/events/widgets/event_editor_drawer_test.dart`; Engineer Report does not mention running or adding these. Not blocking per Manager's criteria for this cycle.

---

## Diff Safety Review

- **Secrets / API keys**: None found.
- **New `debugPrint` / `TODO` / `FIXME`**: 0 new lines in diff (grep confirmed). Pre-existing `debugPrint` calls in event_editor_drawer.dart are unchanged and pre-date this PR.
- **Leftover test scaffolding**: None.
- **Accidental deletions**: None observed.
- **Unrelated churn**: `button_group_grid.dart` is an undisclosed out-of-scope modification (see Warnings).

---

## Change Budget Review

| File | Budget (net) | Actual added | Actual removed | Actual net | Ratio |
|---|---|---|---|---|---|
| event_editor_theme.dart (new) | +55 | +40 | — | +40 | 0.73× ✓ |
| event_editor_drawer.dart | +220 | +588 | −258 | +330 | 1.50× ✓ (at threshold) |
| event_type_selector.dart | +20 | +21 | −10 | +11 | 0.55× ✓ |
| event_form_fields.dart | +60 | +23 | −23 | 0 | 0× ✓ (restyle deferred) |
| gig_form_fields.dart | +90 | +131 | 0 | +131 | 1.46× ✓ |
| rehearsal_form_fields.dart | +45 | +10 | −6 | +4 | 0.09× ✓ (restyle deferred) |
| event_editor_helpers.dart | +25 | +39 | −13 | +26 | 1.04× ✓ |
| event_editor_actions.dart | +30 | +68 | −17 | +51 | **1.70× ⚠** |
| button_group_grid.dart | 0 (not in plan) | +8 | −10 | −2 | N/A |
| **Total** | **~545** | **+928** | **−337** | **+591** | **1.08× ✓** |

`event_editor_actions.dart` is 1.7× over its individual budget — logged as Warning below.

---

## Code Efficiency Review

- No new providers, controllers, or repositories. ✓
- `_SectionCard` is file-private — not a new public API surface. ✓
- **Dead public API**: `GigFormFields.buildSoundcheckRow` (line 606) and its 8 associated constructor props/callbacks (`soundcheckHour`, `soundcheckMinutes`, `soundcheckIsPM`, `onSoundcheckTimeSet`, `onSoundcheckTimeCleared`, `onSoundcheckHourChanged`, `onSoundcheckMinutesChanged`, `onSoundcheckAmPmChanged`) are never passed from `_createGigFormFields()` and `buildSoundcheckRow` is never called. The drawer builds the soundcheck row inline in `_buildScheduleSection` instead. This is the dominant driver of `gig_form_fields.dart`'s +131 line count. Logged as Warning.
- No barrel files, no single-use abstractions, no config/enum cases added for future use.
- Grepped `lib/` for pre-existing `buildSoundcheckRow` / soundcheck equivalents — none found prior to this branch.

---

## Issues Found

### Warnings

**W1 — `out-of-scope`**: `button_group_grid.dart` modified but absent from Architect Plan §3 (Files to Modify) and Engineer Report (Files Modified). Change replaces `context.colors.success` / `AppColors.primary` availability-grid colours with `kEdSuccessBg`/`kEdDangerBg` tokens. Functionally consistent with the design spec but undisclosed.

**W2 — `code-quality`**: `GigFormFields` contains 8 dead optional constructor parameters (`soundcheckHour`, `soundcheckMinutes`, `soundcheckIsPM`, `onSoundcheckTimeSet`, `onSoundcheckTimeCleared`, `onSoundcheckHourChanged`, `onSoundcheckMinutesChanged`, `onSoundcheckAmPmChanged`) and one dead public method (`buildSoundcheckRow`). The plan specified this as the rendering interface; the Engineer instead built the soundcheck row inline in `_buildScheduleSection`, bypassing `GigFormFields` entirely. The dead public surface contributes ~80 lines to `gig_form_fields.dart`'s overage.

**W3 — `code-quality`**: `event_editor_actions.dart` net line delta +51 vs. plan budget +30 (1.7× over). No explanation in Engineer Report.

**W4 — `implementation-gap`**: `event_form_fields.dart` restyle (plan Task 6) deferred — date button, time row, duration stepper, notes textarea, setlist chips retain pre-redesign styling. Engineer acknowledged.

**W5 — `implementation-gap`**: `rehearsal_form_fields.dart` restyle (plan Task 10) deferred — all input fields retain pre-redesign styling. Engineer acknowledged.

### Suggestions

**S1 — `code-quality`**: `event_editor_actions.dart:39` — `TextStyle(fontSize: 14, color: kEdMutedForegroundFaint)` should be `const TextStyle(...)`. Newly introduced `prefer_const_constructors` info lint in an added line.

**S2 — `code-quality`**: Pre-existing `avoid_redundant_argument_values`, `prefer_const_constructors`, `unnecessary_null_checks` info violations in touched files at unmodified lines (event_form_fields.dart:365,371,583,714; rehearsal_form_fields.dart:288,311,427,446,579,911). Not introduced by this diff; worth cleaning in a follow-up.
