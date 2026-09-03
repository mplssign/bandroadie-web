# QA REPORT

**Feature Slug:** `bug/add-event-drawer-no-size`  
**Feature Title:** Add Event drawer still fails to appear — "Cannot hit test a render box with no size"  
**Cycle Number:** 1  
**Date:** 2026-09-03  
**Reviewed By:** QA Agent  

---

## Final Verdict

**APPROVED**

---

## Validation Summary

All Architect tasks are complete, all changed code matches the plan exactly, analyzer passes at 0 issues, no off-limits files touched, no debug artifacts in the diff, and both fixes are mechanically sound.

---

## Architect Scope Review

- Plan slug `bug/add-event-drawer-no-size` matches branch `bug/add-event-drawer-no-size` and Engineer Report slug. ✅
- Two approved files listed in the plan; exactly those two files appear in `git diff --name-only`. ✅
- Off-limits files (`add_edit_event_bottom_sheet.dart`, `app_bottom_sheet.dart`) not present in the diff. ✅

---

## Completeness Check

| Architect Task | Status |
|---|---|
| Wrap `EventEditorDrawer.build()` in `LayoutBuilder` | ✅ Done |
| Replace `Container(constraints: BoxConstraints(maxHeight: H))` with `Container(width: constraints.maxWidth, height: constraints.maxHeight)` | ✅ Done |
| Remove `MediaQuery.of(context).size.height` call | ✅ Done — confirmed via grep: no `size.height` or `BoxConstraints(maxHeight` in file |
| Add `mainAxisSize: MainAxisSize.min` to root Column | ✅ Done |
| Add `heightFactor: 1.0` to `FractionallySizedBox` pill in `EventTypeSelector` | ✅ Done |
| Run `flutter analyze --no-pub` → 0 errors | ✅ Done |

No partial implementations or missing edge cases.

---

## Behavior Verification

**Method: code-path analysis**

### Root Cause A — Loose layout boundary

The old `BoxConstraints(maxHeight: H, minHeight: 0)` was a loose constraint set — Flutter only creates a relayout boundary when constraints are tight (`min == max`). With no relayout boundary, `FAutocomplete`'s `markNeedsLayout` could propagate up through `_ShiftedSheet` during pointer event processing, triggering `!_debugDuringDeviceUpdate` and follow-on "no size" crashes.

The replacement `Container(width: constraints.maxWidth, height: constraints.maxHeight)` sets both dimensions to explicit finite values (`min == max`), producing tight `BoxConstraints` on the Container's child. Flutter creates a relayout boundary here. FAutocomplete overlay layout notifications are contained below this boundary. ✅

`LayoutBuilder` placement is safe at this root level: the plan correctly identifies that the recursive-layout hazard (which affected `EventTypeSelector` in PR #232) only occurs when `LayoutBuilder` is inside a non-flex child of a Column whose `performLayout` hasn't finished. At the root of `EventEditorDrawer.build()`, the parent chain is `ShiftedSheet → Opacity → SafeArea → Align → ConstrainedBox → NotificationListener → Material` — none are a mid-`performLayout` Flex. ✅

### Root Cause B — Invisible pill indicator

`FractionallySizedBox(widthFactor: 1/N)` without `heightFactor` leaves height constraint loose `(0..38)`, causing the childless `Container` to collapse to height 0. `heightFactor: 1.0` makes the pill fill 100% of the Stack's track height (bounded, ~32px after padding), restoring the visible indicator. ✅

### `mainAxisSize: MainAxisSize.min` + tight constraints interaction

With tight constraints from the parent Container, a Column with `mainAxisSize: MainAxisSize.min` computes its desired height as min of children, but the tight `minHeight == maxHeight == H` constraint from the parent means the Column is forced to H regardless. The `Flexible(child: SingleChildScrollView)` absorbs all remaining vertical space after the sticky header, divider, and sticky footer, so the layout behaves as intended: full-height sheet with scrollable body. ✅

---

## Regression Check

| Area | Risk | Assessment |
|---|---|---|
| FAutocomplete overlay hit-testing | LOW | Relayout boundary now contains layout notifications |
| EventTypeSelector pill visibility | LOW | `heightFactor: 1.0` is a pure additive restoration |
| Drawer scroll / sticky header+footer | LOW | Column + Flexible + SingleChildScrollView structure unchanged |
| Other sheets using `app_bottom_sheet.dart` | LOW | Off-limits file not touched |
| Platform parity (iOS/Android/macOS/Web) | LOW | Pure layout widget change; no platform-conditional code |
| FocusNode / Controller disposal | LOW | No new FocusNodes or controllers introduced |
| `setState` after async gap | LOW | No new async operations introduced |

**Overall regression risk: LOW**

---

## Database Safety

N/A — UI-only change. No migrations, RPCs, or RLS changes.

---

## Analyzer Results

```
Analyzing 2 items...
No issues found! (ran in 2.2s)
```

Run against: `lib/features/events/widgets/event_editor_drawer.dart`, `lib/features/events/widgets/event_type_selector.dart`  
0 errors, 0 warnings, 0 info-level issues. ✅

---

## Test Results

No tests required per plan (Tier 1: analyzer only). No existing tests in scope. Manual verification (Tier 2) is post-deploy.

---

## Diff Safety Review

- **Secrets / API keys:** None in diff. ✅
- **`debugPrint` in diff:** Grep of newly-added lines (`git diff | grep '^+'`) — zero matches for `debugPrint`, `TODO`, `FIXME`. The `debugPrint` calls found in the file are all pre-existing, not introduced by this diff. ✅
- **Leftover test scaffolding:** None. ✅
- **Accidental deletions:** Diff removes only the old loose-constraint wrapper and its `MediaQuery` call — exactly as planned. ✅
- **Unrelated churn:** None. The reindentation in `event_editor_drawer.dart` is purely structural from the `LayoutBuilder` wrapping, not cosmetic reformatting. ✅

---

## Change Budget Review

| File | Additions | Deletions | Assessment |
|---|---|---|---|
| `event_editor_drawer.dart` | 34 | 30 | Net +4 lines; reindentation from LayoutBuilder wrapping. Expected. Within budget. |
| `event_type_selector.dart` | 1 | 0 | Single-line additive fix for a missing parameter. 0 deletions is correct — the bug was an omission, not a wrong value. Engineer Report states this explicitly. ✅ |

No new public classes, helpers, extensions, or dependencies introduced. No new files created. ✅

---

## Code Efficiency Review

- No new symbols (helpers, extensions, private widget classes) introduced. ✅
- `LayoutBuilder` is the standard Flutter primitive for this problem; no abstraction warranted for a one-off use.
- No new providers, notifiers, FutureBuilders, StreamBuilders, or hand-rolled collection operations.
- No barrel files, config flags, or "future use" enum cases.
- No single-call-site wrapper abstractions.

---

## Issues Found

**Critical:** None  
**Warnings:** None  
**Suggestions:** None
