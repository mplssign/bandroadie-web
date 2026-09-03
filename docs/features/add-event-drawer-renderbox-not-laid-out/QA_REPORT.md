# QA REPORT

**Feature Slug:** `add-event-drawer-renderbox-not-laid-out`
**Feature Title:** Add Event drawer — "BoxConstraints forces an infinite width" → cascade of "RenderBox was not laid out" (Android & iOS)
**Branch:** `bug/add-event-drawer-renderbox-not-laid-out`
**Cycle Number:** 2
**Date:** 2026-09-03
**Final Verdict:** ✅ APPROVED

---

## Validation Summary

All required checks passed at runtime or by confirmed code-path analysis. The fix is minimal, correct, and complete across all event-type/mode paths. No regressions, no out-of-scope changes, no debug artifacts.

---

## Architect Scope Review

Plan slug matches branch name and Engineer Report. Engineer Report Cycle Number is 2, matching. No prior QA_REPORT.md existed for this slug at this cycle level — not a duplicate session.

Plan designates off-limits files: `app_bottom_sheet.dart`, `add_edit_event_bottom_sheet.dart`. Confirmed untouched via `git status`.

Tasks from plan: Task 1 (pinpoint), Task 2 (fix), Task 3 (revert defer), Task 4 (finalise test), Task 5 (verify). All five marked complete in Engineer Report.

---

## Completeness Check

**PASS.** All five Architect tasks addressed:

- **Task 1 (pinpoint):** Engineer traced full stack via temporary `print(details.stack)` in `FlutterError.onError`, confirmed `_RenderInputPadding._computeSize` origin in `_buildPrimaryActionButton`. Print removed before final diff.
- **Task 2 (fix):** `minimumSize: const Size(0, 40)` added to both `ElevatedButton.styleFrom` instances in `_buildPrimaryActionButton`.
- **Task 3 (revert defer):** `_bodyReady` was never committed (Cycle 1 working-tree-only addition), so the diff vs HEAD shows 0 deletions for the drawer. `grep` of the current file confirms `_bodyReady` is absent; `build()` returns `child: _buildScrollableBody(context)` directly.
- **Task 4 (test):** New `EventEditorDrawer layout` group added to `event_dropdown_test.dart`; Supabase-not-initialized noise filtered; asserts both zero "BoxConstraints forces an infinite width" and zero "RenderBox was not laid out".
- **Task 5 (verify):** Test run and analyzer confirmed at runtime (see below).

---

## Behavior Verification

**Method:** Runtime — test executed + code-path analysis for non-rehearsal paths.

- **Pre-fix reproduction:** Engineer confirmed test failed before fix (per ENGINEER_REPORT task sequence). Not independently re-confirmed at runtime (would require reverting working-tree changes), but accepted: the assertion is structurally sound — `Size(double.infinity, 52)` on an unbounded-Row-child ElevatedButton provably fires the assertion; the test captures it.
- **Post-fix:** `flutter test test/features/events/widgets/event_dropdown_test.dart` → **`+6: All tests passed!`** (runtime confirmed). Test 6 (`EventEditorDrawer layout`) passed with Supabase harness noise visible in stdout but correctly filtered by the test's error accumulator logic.

Root cause addressed: both branches of `_buildPrimaryActionButton` (loading state + normal state `ElevatedButton`) now override `minimumSize` with `const Size(0, 40)`, preventing the `BoxConstraints.tighten(width: double.infinity)` → `BoxConstraints(∞, ∞)` assertion that `_RenderInputPadding._computeSize` fires when `minWidth == maxWidth == infinity`.

---

## Regression Check

**Overall risk: LOW**

| System | Risk | Reasoning |
|---|---|---|
| Event drawer — footer layout | LOW | Fix is purely additive (2 `minimumSize` property additions). Footer Row behaviour is unchanged; button still fills content width which is wider than 0px in practice. |
| Event drawer — gig path | LOW | `_buildPrimaryActionButton` and `_buildStickyFooter` are shared across all event types; gig mode uses the same footer Row. Code-path analysis. |
| Event drawer — edit mode | LOW | `EventEditorMode.edit` uses the same `_buildPrimaryActionButton`. Code-path analysis. |
| Event drawer — viewOnly mode | LOW | viewOnly branch returns a `SizedBox(width: double.infinity, height: 40)` wrapping the Close `OutlinedButton`; not a Row child at all. Safe. |
| auth/session | NONE | No auth or session code touched. |
| Supabase RPC | NONE | Layout-only change. |
| Init order | NONE | No `initState` changes in the final diff. |
| Platform parity | NONE | Row layout constraints are platform-agnostic in Flutter. |

---

## Database Safety

**N/A.** Layout-only change. No migrations, no RPC, no RLS.

---

## Analyzer Results

**PASS — runtime confirmed.**

```
flutter analyze --no-pub lib/features/events/widgets/event_editor_drawer.dart \
    test/features/events/widgets/event_dropdown_test.dart

Analyzing 2 items...
No issues found! (ran in 1.9s)
```

Zero issues at all severities on both changed files.

---

## Test Results

**PASS — runtime confirmed.**

```
flutter test test/features/events/widgets/event_dropdown_test.dart --reporter expanded

00:00 +1: EventDropdown renders with custom labelBuilder
00:00 +2: EventDropdown disables dropdown when isSaving is true
00:00 +3: EventDropdown backward compatibility with hour/minute pattern
00:00 +4: AppDropdown Form integration validates correctly when used in Form
00:00 +5: AppDropdown Form integration triggers onSaved callback on Form.save()
00:00 +6: EventEditorDrawer layout EventEditorDrawer inside bottom sheet emits no layout errors on Android (rehearsal)

00:00 +6: All tests passed!
```

Six tests, all pass. Pre-existing three `EventDropdown` tests and two `AppDropdown` integration tests remain green. The new `EventEditorDrawer layout` test (test 6) is the reproducing test.

---

## Diff Safety Review

**PASS.**

- **Secrets/API keys:** None present. ✓
- **`TODO`/`FIXME`:** None in diff. ✓ (grepped diff manually)
- **`debugPrint`/`print`:** None in diff. The temporary `print(details.stack...)` from Task 1 is absent from the final working tree — confirmed by reading both changed files. ✓
- **Off-limits files:** `app_bottom_sheet.dart` and `add_edit_event_bottom_sheet.dart` not in diff. ✓
- **Unrelated churn:** No formatting-only or unrelated changes in diff. ✓

---

## Change Budget Review

**PASS.**

No explicit Change Budget section in the Architect Plan; assessed against plan task scope:

| File | Insertions | Deletions | Assessment |
|---|---|---|---|
| `event_editor_drawer.dart` | 4 | 0 | 2 `minimumSize` lines + 2 explanatory comments. Zero deletions: bug was a missing property, purely additive fix. `_bodyReady` was working-tree-only (never committed) so zero tracked deletions vs HEAD is correct and explained in ENGINEER_REPORT. ✓ |
| `event_dropdown_test.dart` | 63 | 0 | New reproducing test group (~60 lines). Proportionate for a widget test pumping a full drawer. ✓ |

No new files, public classes, helpers, providers, or dependencies introduced.

---

## Code Efficiency Review

**PASS.**

- No new symbols introduced (no helpers, extensions, private widget classes).
- No new providers or `FutureBuilder`/`StreamBuilder`.
- No dead code, no unused imports/vars.
- Two added comments (`// override theme's Size(double.infinity, 52) — button is in an unbounded Row slot`) explain non-obvious rationale (theme deviation + layout-safety context); acceptable per "state what the code cannot show on its own."
- No "AI-shaped code" patterns (no single-use methods, no wrapper abstractions).

---

## Issues Found

### Critical
None.

### Warnings
None.

### Suggestions

**S1 — `code-quality`:** The two added comments (`// override theme's Size(double.infinity, 52) — button is in an unbounded Row slot`) are borderline explanatory-vs-restating. They do convey non-obvious context (which theme default is overridden and why the layout context makes it mandatory), so they pass the "cannot show on its own" bar — but could be tightened to `// override global ElevatedButton minimumSize: theme sets Size(∞, 52)` to be more precise. Not a blocker.

---

## COMPLETENESS CHECK — Other Drawer Buttons (Check #6)

**All paths clear. No additional unguarded Row-child buttons.**

Scope of buttons with `double.infinity` minimumSize from theme: `FilledButton`, `ElevatedButton`, `OutlinedButton` (see `app_theme.dart` lines 75, 91, 118). `TextButton` has no `minimumSize` theme override.

Audit of every `OutlinedButton`/`ElevatedButton`/`FilledButton` in `event_editor_drawer.dart` and the four form-field widgets:

| Location | Button type | Row child? | Status |
|---|---|---|---|
| `_buildPrimaryActionButton` (loading state) | `ElevatedButton` | Yes (via `SizedBox(height:40)`) | **Fixed** — `minimumSize: Size(0,40)` ✓ |
| `_buildPrimaryActionButton` (normal state) | `ElevatedButton` | Yes (via `SizedBox(height:40)`) | **Fixed** — `minimumSize: Size(0,40)` ✓ |
| `_buildStickyFooter` — Cancel | `OutlinedButton` | Yes, non-Expanded | **Safe** — explicit `minimumSize: Size(80,40)` overrides theme ✓ |
| `_buildStickyFooter` — viewOnly Close | `OutlinedButton` | No — inside `SizedBox(width:∞, height:40)` in a Container | **Safe** — bounded by parent container width ✓ |
| Soundcheck "Set soundcheck time" (gig-only) | `OutlinedButton` | No — inside `SizedBox(width:∞)` in a Column | **Safe** — `SizedBox` bounded by column's bounded maxWidth; gig-only section ✓ |
| `event_form_fields.dart` | — | — | No `ElevatedButton`/`OutlinedButton`/`FilledButton` present ✓ |
| `rehearsal_form_fields.dart` | — | — | No `ElevatedButton`/`OutlinedButton`/`FilledButton` present ✓ |
| `gig_form_fields.dart` | — | — | No `ElevatedButton`/`OutlinedButton`/`FilledButton` present ✓ |
| `FilledButton` (all files) | — | — | Zero instances in any drawer-related file ✓ |

The soundcheck Row contains a "Clear" `TextButton` as a non-Expanded Row child; `TextButton` has no `minimumSize: Size(∞, ...)` theme default — safe.

**Gig path:** Uses the same `_buildStickyFooter` and `_buildPrimaryActionButton` — both fixed/safe.
**Edit mode:** Uses the same `_buildPrimaryActionButton` — fixed.
**View-only mode:** Uses the Close `OutlinedButton` in a `SizedBox` — safe.

All paths covered.

---

## Final Verdict

**✅ APPROVED**

Regression risk: **LOW**. The fix is two bounded-`minimumSize` overrides on `ElevatedButton` instances that were the confirmed sole source of the "BoxConstraints forces an infinite width" crash. All other drawer buttons on all paths (rehearsal/gig, create/edit/viewOnly) are either Column children, wrapped in width-bounded `SizedBox`, or already have explicit bounded `minimumSize` overrides. Test passes at runtime. Analyzer clean. No secrets, debug artifacts, or out-of-scope changes.

Device verification (Tony, post-merge): Open Add Event from Dashboard on Android/iOS — drawer should render without any "RenderBox was not laid out" / "BoxConstraints forces an infinite width" in console.
