# QA_REPORT.md

## Feature Slug
`bug/add-event-date-picker-calendar-header-overflow`

## Feature Title
Calendar header RenderFlex overflow in the "Add Event" date picker for certain months (e.g. September)

## Cycle Number
2

## Final Verdict
**APPROVED**

---

## Validation Summary

All plan requirements met. 0 analyzer errors. Both acceptance test cases pass. No off-limits files touched. No debug artifacts or secrets. DB/RLS/RPC not applicable. Change budget within bounds. No regressions identified.

---

## Architect Scope Review

- Plan slug: `bug/add-event-date-picker-calendar-header-overflow` — matches branch ✓  
- Engineer Report slug: `bug/add-event-date-picker-calendar-header-overflow` — matches ✓  
- Plan is Revision 2; Engineer Report is Cycle 2 — consistent ✓  
- QA_REPORT.md did not previously exist for this slug at any cycle number — no duplicate session detected ✓  

---

## Completeness Check

All five tasks from the Architect plan verified:

| Task | Status |
|------|--------|
| 1. Preserve Part A: `FDialogStyleDelta.delta(insetPadding: horizontal 16)` + `BoxConstraints(min 280, max 360)` + inner `ConstrainedBox` removed | ✓ confirmed on disk |
| 2. Add `headerBuilder:` with exactly `LayoutBuilder → SingleChildScrollView(horizontal) → ConstrainedBox(minWidth: viewport.maxWidth) → IntrinsicWidth(child: header)` | ✓ matches plan spec verbatim |
| 3. No new imports | ✓ imports unchanged |
| 4. No `physics:` on `SingleChildScrollView` (default intentional) | ✓ confirmed absent |
| 5. All other `FCalendar.grid` args preserved verbatim | ✓ `control:`, `selectionControl:`, `fixedWeeks:` all present and unchanged |

No partial implementations. No missing edge cases.

---

## Behavior Verification

_Method: code-path analysis of the working-tree implementation against the plan's layout arithmetic, plus runtime-exercised widget-test execution._

### Part A (dialog widening) — code-path analysis
`FDialogStyleDelta.delta(insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24))` reduces horizontal inset from 40 → 16 px; `BoxConstraints(minWidth: 280, maxWidth: 360)` sets dialog width bounds. At a 360-px logical viewport the dialog takes the full available width minus 32 px inset. After FCalendar border + padding (~26 px) the `SizedBox(width: 308)` sees a parent maxWidth of ~302 px, clamped to 302. This lifts the `Row`'s tight width from the original 254 px to 302 px — sufficient for the ~262 px intrinsic content at default font scale with ~40 px of slack. Matches the plan's arithmetic exactly.

### Part B (headerBuilder) — code-path analysis
`LayoutBuilder` receives tight constraints (302, 302) from the forui `SizedBox`.  
`SingleChildScrollView(horizontal)` passes its child unbounded horizontal max while preserving cross-axis.  
`ConstrainedBox(minWidth: 302, maxWidth: ∞)` forwards that to `IntrinsicWidth`.  
`IntrinsicWidth` measures intrinsic content width; lays out child with `max(intrinsic, 302)`:

- Default font (~262 px intrinsic): `max(262, 302) = 302` → `Row` fills 302, `Spacer` gets ~40 px, nav buttons align right. Visual identical to post-Part-A baseline. ✓  
- Widget-test fallback font (~376 px, September; ~358 px, February): `max(376, 302) = 376 / max(358, 302) = 358` → `Row` fills intrinsic, no `RenderFlex` overflow. `SingleChildScrollView` scrolls the surplus silently; `tester.takeException()` is null. ✓  
- Accessibility font scale ≳1.15× (on-device): same shape as widget-test case; header grows past 302 px, becomes horizontally scrollable rather than throwing. Known plan-documented tradeoff — see tradeoff note below.

### Root cause fixed
The bug is `RenderFlex` overflow caused by forui's 308-px `SizedBox` hard cap clamping the `Row`'s tight width to less than the header's intrinsic content width, with no overflow tolerance in the `Row`. Part B adds that tolerance (scroll instead of overflow) upstream of the `SizedBox` cap, making overflow arithmetically impossible regardless of content width.

---

## Regression Check

| Area | Risk | Finding |
|------|------|---------|
| Add Event drawer date pickers | LOW | `showAppDatePicker` fix inherited; on-device layout unchanged at default font |
| Add Block Out drawer date pickers | LOW | Same |
| Gig Expenses / Financial Entry / Gig Pay date pickers | LOW | Same |
| Calendar main view (`FCalendar.wheel`) | NONE | `calendar_grid.dart` untouched; different widget |
| Wide-screen / macOS | LOW | Dialog width capped at 360; `Row` layout unchanged at default font |
| Auth / session / Supabase / RLS / RPC | NONE | No data layer touched |
| Init order | NONE | Unchanged |
| Platform parity | LOW | Single-file fix with no platform-conditional code; all platforms use same path |
| Controller / FocusNode disposal | NONE | No new widgets with lifecycle |
| `setState` after async gap | NONE | No async state mutation added |

Overall regression risk: **LOW**. No regressions identified.

### Known behavioral tradeoff (plan-documented, not a defect)
At large accessibility font scales (≳1.15×) the header becomes horizontally scrollable rather than overflowing. This is explicitly the plan's intent: `SingleChildScrollView` default physics allow accessibility users to scroll to off-viewport nav buttons. The plan states: "Do not pass a custom `physics:` — default scroll physics is intentional so that accessibility users at large font scales can horizontally scroll the header to reach off-viewport nav buttons." Confirmed present and intentional. Not flagged as a finding.

---

## Database Safety

Not applicable. No migrations, no RPC changes, no RLS changes, no schema changes, no edge-function changes.

---

## Analyzer Results

Command: `flutter analyze lib/components/ui/app_date_picker.dart test/components/ui/app_date_picker_test.dart`

```
2 issues found.

   info • avoid_redundant_argument_values  (lib/components/ui/app_date_picker.dart:19:25 — barrierDismissible: true)
   info • avoid_redundant_argument_values  (lib/components/ui/app_date_picker.dart:38:21 — fixedWeeks: false)
```

**Errors: 0. Warnings: 0. Info: 2.**  
Both info lints are explicitly accepted by the plan ("documentary and not part of this fix"). No pre-existing violations in files touched by the diff. ✓

---

## Test Results

Command: `flutter test test/components/ui/app_date_picker_test.dart --reporter=expanded`

```
00:00 +1: showAppDatePicker header overflow (narrow phones) September 2026 renders without overflow at 360×800
00:00 +2: showAppDatePicker header overflow (narrow phones) February 2026 renders without overflow at 360×800
00:00 +2: All tests passed!
```

**Both cases PASS.** (Runtime-exercised.)

### Test quality verification
The tests are a genuine regression guard, not vacuous:
- `tester.view.physicalSize = Size(360 × 3.0, 800 × 3.0)` + `devicePixelRatio = 3.0` → logical surface is exactly 360×800. ✓  
- `addTearDown(tester.view.reset)` — isolates view mutation between tests. ✓  
- Taps button → `showAppDatePicker()` → `pumpAndSettle()` — actually opens the dialog. ✓  
- `tester.takeException()` is null — real guard: `RenderFlex` overflow errors are captured as exceptions and returned here; a null result proves no overflow fired. ✓  
- `find.byType(FCalendar)` — confirms the picker opened (not just silently skipped). ✓  
- Test file is untracked (`??` in `git status`), not modified — plan requirement "Do not touch the test file" upheld. ✓

---

## Diff Safety Review

- **`git diff --name-only`**: `lib/components/ui/app_date_picker.dart` only. ✓  
- **`git status` untracked**: `test/components/ui/app_date_picker_test.dart` (created, not modified — correct). ✓  
- **Off-limits files**: `add_block_out_drawer.dart`, `event_editor_drawer.dart`, `gig_expense_subview.dart`, `add_financial_entry_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart`, `calendar_grid.dart`, `app_theme.dart`, `event_editor_theme.dart`, `main.dart` — all confirmed untouched by `git diff --name-only`. ✓  
- **Debug artifacts**: No `TODO`, `FIXME`, `debugPrint`, or `print(` in diff or test file. ✓  
- **Secrets/API keys**: None found. ✓  
- **Accidental deletions / unrelated churn**: None. The 13 deleted lines are exactly the `ConstrainedBox` wrapper removal from Part A (on-scope). ✓

---

## Change Budget Review

`git diff --numstat`: **26 additions, 13 deletions** against HEAD.

This covers the entire uncommitted working tree: both Cycle 1's Part A (dialog widening, ConstrainedBox removal) and Cycle 2's Part B (headerBuilder). The diff is larger than Part B alone because Cycle 1's Part A changes were also uncommitted at HEAD (per pipeline convention). Part B alone = 11 lines added, 0 deleted — exactly within the plan's "+11 to +14 lines on top of the current on-disk state" budget. ✓

- New files: 0 (test file pre-existed from prior revision; unmodified). ✓  
- New public classes/methods: 0. ✓  
- New dependencies: 0. ✓  
- New migrations: 0. ✓

---

## Code Efficiency Review

- `headerBuilder` is an inline closure at the single call site — correct scope, no `_buildX()` method. ✓  
- No new provider, notifier, repository, model, or service. ✓  
- Existing-helper check for `IntrinsicWidth` / scroll-wrapper for header layout: `grep lib/` found only one `IntrinsicWidth` usage (`rehearsal_card.dart`), unrelated to header layout. No duplicate helper exists. ✓  
- No `FutureBuilder` / `StreamBuilder` added. ✓  
- No `try/catch` added. ✓  
- No new fields, parameters, or `copyWith` entries. ✓  
- File `app_date_picker.dart` is 53 lines — well within the 500-line target. ✓  
- Zero deleted lines in Part B is correct and stated: the defect lives in third-party forui source; our fix adds a wrapper rather than patching it. ✓

---

## Issues Found

None.

---

_QA performed by GitHub Copilot (Claude Sonnet 4.6) on 2026-09-04._
