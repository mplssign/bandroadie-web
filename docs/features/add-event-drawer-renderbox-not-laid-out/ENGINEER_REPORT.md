# ENGINEER REPORT

**Feature Slug:** `bug/add-event-drawer-renderbox-not-laid-out`
**Feature Title:** Add Event drawer — "BoxConstraints forces an infinite width" → cascade of "RenderBox was not laid out" (Android & iOS)
**Cycle Number:** 2
**Goal:** Pinpoint and fix the Material button that receives tight-infinite-width constraints, revert the ineffective `_bodyReady` defer, and make the reproducing widget test green.

---

## Architect Tasks Completed

- **Task 1** — Pinpointed exact widget via the oracle test (temporary stack-trace print).
- **Task 2** — Fixed the offending Material button.
- **Task 3** — Reverted the ineffective `_bodyReady` defer.
- **Task 4** — Finalized the reproducing test (removed debug prints, proper assertions).
- **Task 5** — Verified: test passes, analyzer clean.

---

## Pinpointed Widget (Task 1 Output)

Added a temporary `print(details.stack.toString().split('\n').take(30).join('\n'))` inside `FlutterError.onError` when the exception message contained `'infinite width'`, then ran:

```
flutter test test/features/events/widgets/event_dropdown_test.dart --name 'EventEditorDrawer' 2>&1
```

Stack trace confirmed `_RenderInputPadding._computeSize` (flutter/src/material/button_style_button.dart:698) as the direct origin. Tracing the mechanism:

1. `AppTheme.darkTheme` sets `minimumSize: const Size(double.infinity, 52)` globally on `ElevatedButton` (`lib/app/theme/app_theme.dart` lines 75, 91, 118).
2. `_buildPrimaryActionButton` in `event_editor_drawer.dart` returns `SizedBox(height: 40, child: ElevatedButton(...))`. The `ElevatedButton` has no explicit `minimumSize` override → inherits `Size(double.infinity, 52)` from the theme.
3. This `SizedBox` is a **direct non-`Expanded` child of the footer `Row`** → the Row supplies `maxWidth: double.infinity`.
4. `_RenderInputPadding._computeSize` calls `layoutChild(child!, constraints)` where the child is a `RenderConstrainedBox` with `additionalConstraints = BoxConstraints.tighten(width: double.infinity, height: 52)`. Combined with incoming `maxWidth: infinity`, `BoxConstraints.enforce` yields `BoxConstraints(minWidth: ∞, maxWidth: ∞)` — tight-infinite → `debugAssertIsValid` fires "BoxConstraints forces an infinite width."
5. All 20 "RenderBox was not laid out" cascade errors and the semantics assertion (21 total on Frame 0) are consequences of this single failure.

**Exact file + mechanism:**
`lib/features/events/widgets/event_editor_drawer.dart` — `_buildPrimaryActionButton` — both `ElevatedButton` instances (loading state and normal state) lacked a bounded `minimumSize` and were direct non-`Expanded` children of the footer `Row` via `SizedBox(height: 40)`.

---

## Fix Applied (Task 2)

Added `minimumSize: const Size(0, 40)` to `ElevatedButton.styleFrom(...)` in both branches of `_buildPrimaryActionButton`. `Size(0, 40)` is bounded (overrides the theme's `Size(double.infinity, 52)`), content-sizes the button width, and keeps height at 40px consistent with the existing `SizedBox(height: 40)` wrapper. Visually equivalent: button labels ("Add Rehearsal", "Save Changes", etc.) are wider than zero and the button renders normally.

The `SizedBox(height: 40)` wrapper was left unchanged — it is not part of the problem (height-only tight constraints are fine).

---

## `_bodyReady` Defer Reverted (Task 3)

Removed from `event_editor_drawer.dart`:
- `bool _bodyReady = false;` field declaration (with associated comment)
- `WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _bodyReady = true); });` at the end of `initState`
- The conditional `_bodyReady ? _buildScrollableBody(context) : SizedBox(height: ...)` in `build()`; restored to `child: _buildScrollableBody(context)`

The defer did not address the root cause (the footer `Row` and its buttons render on Frame 0 regardless of the body), and the `FAutocomplete`/`FPortal` widgets in the body present no compositing issue on initial render.

---

## Files Created

- `docs/features/add-event-drawer-renderbox-not-laid-out/ENGINEER_REPORT.md` (this file)

## Files Modified

- `lib/features/events/widgets/event_editor_drawer.dart` — fix + revert
- `test/features/events/widgets/event_dropdown_test.dart` — finalized reproducing test

---

## Analyzer Results

```
Analyzing 2 items...
No issues found! (ran in 3.0s)
```

Zero issues at all severities on both changed files.

---

## Test Results

```
00:00 +6: All tests passed!
```

All 6 tests pass, including the `EventEditorDrawer layout` reproducing test (previously failing). The three pre-existing `EventDropdown` tests and the two `AppDropdown Form integration` tests remain green.

---

## Code Efficiency/Bloat Check

**Existing helpers searched:** No new helpers, extensions, or utilities were created. Searched for existing `minimumSize` patterns across `lib/app/theme/` before modifying anything — confirmed the root cause is the global theme default.

**No-AI-shaped-code check:**
- No unused imports/vars introduced.
- No `_buildX()` methods or private widget classes added.
- No new providers.
- No `TODO`/`FIXME`/`debugPrint` left in.
- The fix is two `minimumSize:` lines added — purely additive, no dead code.
- The `_bodyReady` removal is a net-deletion (3 lines removed, 0 added for that change).

---

## Verification (Manual Steps Performed)

1. Ran `flutter test test/features/events/widgets/event_dropdown_test.dart` before fix → FAILED with "BoxConstraints forces an infinite width" + 20 cascade "RenderBox was not laid out" errors. ✓ (pre-fix reproduction confirmed)
2. Added temporary stack-trace print to isolate widget. ✓
3. Identified `AppTheme.darkTheme` global `minimumSize: Size(double.infinity, 52)` as the source. ✓
4. Applied fix + revert. ✓
5. Removed temporary print. ✓
6. Ran `flutter test test/features/events/widgets/event_dropdown_test.dart` → ALL 6 PASSED. ✓
7. Ran `flutter analyze --no-pub` on both changed files → 0 issues. ✓
8. Ran `dart format` on both changed files. ✓
9. Re-ran tests post-format → ALL 6 PASSED. ✓

---

## Deviations From Plan

None. The plan anticipated the exact class of bug (Material button with `double.infinity` minimumSize in an unbounded-width Row slot). The oracle pinpointing confirmed the mechanism matched the plan's prediction exactly. The fix and revert were applied as specified.

---

## Blockers Encountered

None.

---

## Ready For QA

**Yes.**

**Manual verification on device** (Tony, post-merge): Open Add Event from Dashboard on Android/iOS — drawer should render without any "RenderBox was not laid out" / "BoxConstraints forces an infinite width" in console.
