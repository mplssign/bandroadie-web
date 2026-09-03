# QA Report — unified-forui-switch-styling

## Feature Slug
`unified-forui-switch-styling`

## Feature Title
Unify all app toggle switches on one Forui Switch component with improved on-state contrast

## Cycle Number
1 (first QA pass)

## Final Verdict
**APPROVED**

---

## Validation Summary

| Check | Result |
|---|---|
| Branch | `feature/unified-forui-switch-styling` ✓ |
| Working tree | 15 modified files, uncommitted — expected ✓ |
| Existing QA report | None (Cycle 1) ✓ |
| Files to modify (count) | 15 modified / 0 created — matches plan exactly ✓ |
| Files off-limits touched | None ✓ |
| `flutter analyze` errors/warnings in touched files | 0 ✓ |
| `flutter test test/components/ui/app_switch_test.dart` | 9/9 PASS ✓ |
| All 6 grep gates | PASS ✓ |
| TODO/FIXME/debugPrint in diff | None ✓ |
| Secrets in diff | None ✓ |
| Database safety | N/A (pure client-side change) ✓ |

---

## Architect Scope Review

Plan called for 15 modified files, 0 created, 0 new dependencies. Actual diff is exactly those 15 files:

**Theme + shared component (3 files)**
- `lib/app/theme/design_tokens.dart` ✓
- `lib/app/theme/app_theme.dart` ✓
- `lib/components/ui/app_switch.dart` ✓

**Component-drift migrations (6 files — 4 raw Switch + 2 SwitchListTile)**
- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` ✓
- `lib/features/financials/widgets/gig_pay_bottom_sheet.dart` ✓
- `lib/features/contacts/widgets/band_member_edit_drawer.dart` ✓
- `lib/features/members/widgets/role_management_sheet.dart` ✓

**Override cleanup on existing AppSwitch call sites (6 files)**
- `lib/features/calendar/one_calendar_settings_screen.dart` ✓
- `lib/features/events/widgets/gig_expense_subview.dart` ✓
- `lib/features/events/widgets/gig_form_fields.dart` ✓
- `lib/features/events/widgets/rehearsal_form_fields.dart` ✓
- `lib/features/notifications/notification_settings_screen.dart` ✓
- `lib/features/setlists/widgets/print_options_bottom_sheet.dart` ✓
- `lib/features/settings/settings_screen.dart` ✓

**Test coverage (1 file extended)**
- `test/components/ui/app_switch_test.dart` ✓

No off-limits files (`lib/main.dart`, auth files, routing config, Supabase artifacts, `pubspec.yaml`/`pubspec.lock`, other Forui wrappers) appear in the diff.

---

## Completeness Check

All 12 tasks from the plan (Tasks 1–8 original + Tasks 9–12 AMENDMENT 1) implemented and confirmed in the diff:

| Task | Description | Status |
|---|---|---|
| 1 | `AppColors.primarySoft = Color(0xFFFB7185)` in design_tokens.dart | ✓ confirmed in diff |
| 2 | `switchStyle` delta in `foruiTheme` — `.selected` → `primarySoft`, `thumbColor` → `.all(Colors.white)` | ✓ confirmed in diff |
| 3 | `label` + `leadingLabel` params added to `AppSwitch`, passed to both FSwitch branches | ✓ confirmed in diff |
| 4 | 3 raw `Switch(` in add_financial replaced with `AppSwitch`; 1 in gig_pay replaced | ✓ confirmed in diff |
| 5 | 2 `SwitchListTile(` in band_member_edit + role_management replaced with `AppSwitch(leadingLabel: true, label: Text(...))` | ✓ confirmed in diff |
| 6 | All `activeColor`/`activeTrackColor` overrides removed from 7 existing AppSwitch call-site files; both `Color(0xFFfb2c5a)` literals removed from rehearsal_form_fields | ✓ confirmed in diff |
| 7 | Two new testWidgets cases in app_switch_test.dart (ON-state colors + label-tap) | ✓ confirmed in diff |
| 8 | `flutter analyze` + `flutter test` verified | ✓ confirmed below |
| 9 | `AppColors.switchTrackOff = Color(0xFF52525B)` in design_tokens.dart below primarySoft | ✓ confirmed in diff |
| 10 | `FVariantValueDeltaOperation.base(AppColors.switchTrackOff)` prepended to trackColor delta | ✓ confirmed in diff |
| 11 | OFF-state test case added asserting `trackColor.resolve({})` == `switchTrackOff` | ✓ confirmed in diff |
| 12 | `flutter analyze` + `flutter test` verified by Engineer | ✓ confirmed by independent QA run |

---

## Behavior Verification

**Method: code-path analysis (static review). Runtime UI exercising was NOT performed; all checks are code-review only unless explicitly marked otherwise.**

### ON-state theme override

Confirmed by code review:
```dart
// app_theme.dart diff — exact match to plan Task 2 / Task 10 spec
switchStyle: FSwitchStyleDelta.delta(
  trackColor: FVariantsValueDelta.delta([
    FVariantValueDeltaOperation.base(AppColors.switchTrackOff),     // Task 10: OFF-fill
    FVariantValueDeltaOperation.match(
      {FSwitchVariant.selected},
      AppColors.primarySoft,                                        // Task 2: ON-fill
    ),
  ]),
  thumbColor: FVariantsValueDelta.delta([
    FVariantValueDeltaOperation.all(Colors.white),                  // Task 2: thumb
  ]),
),
```
Token values `Color(0xFFFB7185)` and `Color(0xFF52525B)` match the plan exactly. Variant targeting is correct: `.base(...)` touches only the default (OFF, no variants) entry; `.match({selected}, ...)` touches only the ON variant; disabled variants are untouched (plan scope guard satisfied).

### SwitchListTile → AppSwitch migrations

Both `_buildPermissionToggle` helpers (band_member_edit_drawer + role_management_sheet) were correctly rewritten. Confirmed by code review:
- `leadingLabel: true` passed → label renders left of switch, tap-anywhere-to-toggle UX preserved via FSwitch's built-in label interaction.
- Enabled/disabled `TextStyle` color ternary (`context.colors.textPrimary` / `context.colors.textDisabled`) is preserved on the `Text(label, style: TextStyle(...))` passed as `label:`.
- Outer `Padding(EdgeInsets.only(bottom: 4))` preserved for vertical rhythm.
- Note: SwitchListTile's internal `contentPadding: horizontal: 4` and `dense: true` have no direct equivalent on FSwitch and were not replicated. The plan's intent was to preserve the outer padding wrapper (done) — FSwitch has its own built-in internal layout. This is not a defect.

### `viewOnly` disabled behavior in gig_pay

Confirmed by code review:
```dart
onChanged: widget.viewOnly
    ? null
    : (value) { setState(() => _is1099Expected = value); },
```
`AppSwitch` passes `enabled: onChanged != null` to `FSwitch`, so `viewOnly == true` disables the switch. ✓

### 3 raw Switch migrations in add_financial_entry_bottom_sheet

All three (`_is1099Expected`, `_disburse`, `_depositToSavings`) replaced with `AppSwitch(value:, onChanged:)`. Dropped `activeTrackColor`, `inactiveTrackColor`, `inactiveThumbColor`. Callback signatures unchanged. Confirmed by code review. ✓

### Override cleanup on existing AppSwitch sites

Confirmed by code review across 7 files. Line counts match plan:
- `one_calendar_settings_screen`: 2 `activeTrackColor:` removed
- `gig_expense_subview`: 1 `activeColor:` removed
- `gig_form_fields`: 1 `activeColor:` removed
- `rehearsal_form_fields`: 2 × (activeColor + activeTrackColor) = 4 lines removed, both `Color(0xFFfb2c5a)` literals gone
- `notification_settings_screen`: 1 `activeColor:` removed
- `print_options_bottom_sheet`: 2 `activeTrackColor:` removed from AppSwitch sites; 2 Slider sites at lines 660–661 / 748–749 intentionally preserved (confirmed non-switch: `SliderThemeData`)
- `settings_screen`: 1 `activeColor:` removed

### `app_switch.dart` param additions

`label` and `leadingLabel` added at end of constructor (no existing param reordering). Passed to FSwitch in both build branches (with-style-delta AND without). Existing `activeColor`, `activeTrackColor`, `useAdaptiveSwitch` params retained unchanged. ✓

---

## Regression Check

**Rated: LOW.** No regressions identified.

| Area | Assessment | Risk |
|---|---|---|
| Auth/session | Not touched | LOW |
| Supabase RPCs / DB | Not touched | LOW |
| Init order (main.dart) | Not touched | LOW |
| Platform parity | Pure theme/widget change; identical across iOS/Android/macOS/Web | LOW |
| Controller/FocusNode disposal | No new controllers or FocusNodes | LOW |
| Rebuild triggers | No new providers/notifiers; theme override propagates via existing FTheme wrap | LOW |
| Setlists (print_options) | Override removal only; non-switch Slider lines untouched | LOW |
| Rehearsals (rehearsal_form_fields) | Override removal only; both `Color(0xFFfb2c5a)` literals removed as planned | LOW |
| Gigs (gig_form_fields, gig_expense, gig_pay) | Override removal + 1 raw→AppSwitch migration; viewOnly preserved | LOW |
| Calendar | Override removal only | LOW |
| Members (role_management_sheet) | SwitchListTile→AppSwitch; label/disabled color preserved; leadingLabel=true | LOW |
| Contacts (band_member_edit_drawer) | SwitchListTile→AppSwitch; label/disabled color preserved; leadingLabel=true | LOW |
| Notifications | Override removal only | LOW |
| Settings | Override removal only | LOW |
| Financials | 4 raw Switch→AppSwitch; callbacks preserved; viewOnly preserved | LOW |

---

## Database Safety

**N/A.** No migrations, RLS policies, RPCs, triggers, or edge functions. Pure client-side Flutter widget/theme change.

---

## Analyzer Results

```
flutter analyze — errors:   0
                  warnings:  1 (pre-existing `undefined_lint` in analysis_options.yaml — NOT in diff)
                  info:    598 (all pre-existing, none in touched files)
```

Touched-file-specific check: 0 errors, 0 warnings, 0 new info lints in any of the 15 modified files.

The 14 info-level lints in `app_theme.dart` are at lines 65, 143, 147, 151, 155, 188, 194, 316, 437, 445, 449, 468 — all well away from the diff's changes at lines 626–640. Pre-existing; not introduced by this change.

No lint suppressions added anywhere in the diff.

---

## Test Results

```
flutter test test/components/ui/app_switch_test.dart
00:02 +9: All tests passed!
```

**9/9 pass.** Breakdown:
- 6 pre-existing cases: all pass (unchanged)
- Task 7 new case: "renders under AppTheme.foruiTheme with distinct on-state track and thumb colors" — PASS
- Task 7 new case: "renders label and toggles when label is tapped when leadingLabel is true" — PASS
- Task 11 (AMENDMENT 1) new case: "off-state track resolves to AppColors.switchTrackOff under AppTheme.foruiTheme" — PASS

Test approach note: the ON/OFF state tests assert `FTheme.of(element).switchStyle.trackColor.resolve(...)` directly — i.e., they test the resolved theme value, not a rendered pixel. This confirms the delta wiring is correct without requiring a visual render. The label-tap test actually pumps and taps via `tester`, exercising the widget interaction path.

---

## Diff Safety Review

- **Secrets/API keys**: None found. (The grep for "token" matched only a Dart import for `design_tokens.dart` — false positive, not a secret.)
- **TODO/FIXME/debugPrint**: None in diff (grepped explicitly).
- **Leftover test scaffolding**: None.
- **Accidental deletions**: None — only intentional override/param removals per plan.
- **Unrelated formatting churn**: None — `dart format` was run but produced no extraneous whitespace diffs.
- **Out-of-scope changes**: None. Every hunk maps to a named plan task.

---

## Change Budget Review

Budget comparison (plan vs. actual via `git diff --numstat`):

| File | Plan budget | Actual (+added / −deleted) | Assessment |
|---|---|---|---|
| `design_tokens.dart` | +7 lines (combined) | +6 / −0 (net +6) | ✓ within budget |
| `app_theme.dart` | +13 to +19 lines (combined) | +14 / −1 (net +13) | ✓ within budget |
| `app_switch.dart` | +6 to +10 lines | +12 / −0 (net +12) | Note: 1.2× upper bound; within 1.5× threshold |
| `add_financial_entry_bottom_sheet.dart` | −9 lines | +4 / −12 (net −8) | ✓ within budget |
| `gig_pay_bottom_sheet.dart` | −2 lines | +2 / −3 (net −1) | ✓ within budget |
| `band_member_edit_drawer.dart` | −3 lines | +6 / −7 (net −1) | ✓ within budget |
| `role_management_sheet.dart` | −3 lines | +6 / −7 (net −1) | ✓ within budget |
| 7 override-cleanup files combined | −10 lines | 0 / −12 (net −12) | ✓ within budget |
| `app_switch_test.dart` | +45 to +70 lines (combined Tasks 7+11) | +87 / −0 (net +87) | Note: 1.24× upper bound; within 1.5× threshold |

All per-file deltas are within ~1.5× of their plan budgets. The plan's stated "total net delta of +15 to +30 lines" was underestimated relative to its own per-file numbers (the test file alone was budgeted at +45–70); the per-file budgets are the operative constraints and all pass.

**No new files, no new public classes, no new dependencies** — matches plan exactly.

---

## Code Efficiency Review

- No new helpers, extensions, utils, or private widget classes.
- No new providers or notifiers.
- No barrel files created.
- No config, flags, or enum cases added for future use.
- No `_buildX()` single-use private methods that should be inlined.
- No `FutureBuilder`/`StreamBuilder` where a provider would do.
- No wrapper abstractions added.
- `AppSwitch` was confirmed as the existing shared widget; no equivalent was created.
- Comments in the diff are doc-level (1-line token comments) and the existing `app_switch.dart` field comments — not redundant restatements.

---

## Issues Found

**Critical:** None.

**Warnings:** None.

**Suggestions:** None.

---

## Verification Method Disclosure

Per QA hard rules — honesty about method:

| Check | Method |
|---|---|
| Token values, delta structure, variant targeting | **Code-path analysis** (reviewed diff + Forui API) |
| Override removals complete and correct | **Code-path analysis** |
| SwitchListTile migration preserves label/disabled colors | **Code-path analysis** |
| `viewOnly` disabled behavior preserved | **Code-path analysis** |
| Non-switch Slider lines at print_options 660/748 untouched | **Code-path analysis** + grep verification |
| `flutter analyze` | **Runtime-exercised** (command run, output read) |
| `flutter test` 9/9 pass | **Runtime-exercised** (tests run, all passed) |
| Grep gates (Switch/SwitchListTile/activeColor/literals/switchTrackOff) | **Runtime-exercised** (grep commands run) |
| Visual: ON/OFF state appearance on macOS | **NOT exercised** — macOS build not run. Visual correctness inferred from code-path analysis of the theme delta and token values. |
| Visual: tap-anywhere-to-toggle UX on device | **NOT exercised** at runtime on device/simulator. Validated by the passing `label-tap` widget test (which exercises the FSwitch label interaction path in the test framework). |
| Disabled state dimming preserved | **Code-path analysis** — `.disabled` variants not touched by `.base(...)` or `.match({selected}, ...)` ops per Forui's `FVariantValueDeltaOperation` semantics. |
