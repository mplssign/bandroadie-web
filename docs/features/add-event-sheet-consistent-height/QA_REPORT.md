# QA_REPORT — add-event-sheet-consistent-height

## Feature Slug
`add-event-sheet-consistent-height`

## Feature Title
Add Event sheet height should stay constant across Rehearsal/Gig/Block out tabs

## Cycle Number
1

## Final Verdict
**APPROVED**

---

## Validation Summary

All required checks passed. The implementation is a precise, minimal execution of the Architect plan with no regressions, no off-limits files touched, clean analyzer output, and all 6 tests passing.

---

## Architect Scope Review

- Branch confirmed: `bug/add-event-sheet-consistent-height` ✓
- Only file modified: `lib/features/events/widgets/event_editor_drawer.dart` ✓ (`git status` shows one `M` tracked file, no others)
- Off-limits files: none touched — confirmed via `git diff --name-only` showing exactly one file ✓
- No new files created ✓
- No migrations, edge functions, or dependency changes ✓
- Slugs match across branch, ARCHITECT_PLAN.md, and ENGINEER_REPORT.md ✓
- No prior QA_REPORT.md existed for this slug — no duplicate session ✓

---

## Completeness Check

All three Architect tasks completed in the single target method `_EventEditorDrawerState.build()`:

| Task | Status | Method |
|---|---|---|
| Replace `constraints: BoxConstraints(maxHeight: …)` with `height: MediaQuery.of(context).size.height` on outer Container | ✓ Complete | reviewed-in-code (diff) |
| Replace `Flexible` with `Expanded` around `SingleChildScrollView` | ✓ Complete | reviewed-in-code (diff) |
| Remove `mainAxisSize: MainAxisSize.min` from `Column` | ✓ Complete | reviewed-in-code (diff) |

Diff (reviewed in full):
```diff
-        constraints: BoxConstraints(
-          maxHeight: MediaQuery.of(context).size.height,
-        ),
+        height: MediaQuery.of(context).size.height,
         ...
         child: Column(
-          mainAxisSize: MainAxisSize.min,
           children: [
-            Flexible(
+            Expanded(
```

The diff is exactly three property changes and nothing else. No whitespace churn, no unrelated lines touched.

---

## Behavior Verification

**Method: code-path analysis (not runtime-exercised; Tier 2 manual visual verification is out of scope for this QA cycle)**

**Does the fix deliver a constant outer sheet height?**

Yes. Reasoning:

1. `Container(height: MediaQuery.of(context).size.height)` internally creates `BoxConstraints(minHeight: H, maxHeight: H)`. When the modal's available height is less than H (e.g. after `useSafeArea: true` subtracts status bar/notch), Flutter's constraint enforcement (`_additionalConstraints.enforce(parentConstraints)`) clamps to the modal's max — the container takes all available vertical space. No overflow occurs.
2. `Column` (now `MainAxisSize.max`, the default) fills its fixed-height parent, giving the children definite vertical space to share.
3. `Expanded(SingleChildScrollView)` receives `FlexFit.tight`, forcing it to occupy exactly `containerHeight − footerHeight` regardless of the content's intrinsic height. The scroll view absorbs any content taller than its viewport (Gig's 6 cards) and leaves empty space below shorter content (Block out's 3 fields).
4. `_buildStickyFooter(context)` retains its intrinsic height as before; it is not `Expanded` and not inside the scroll view, so it stays pinned at the bottom of the container.

**Event type switching:** `_handleTypeChanged → setState` rebuilds `_buildScrollableBody(context)`, which returns a different sub-tree. With the new layout, the outer container height is independent of that sub-tree's intrinsic size. The sheet chrome does not resize. This is the intended behavior.

**Keyboard inset:** `showModalBottomSheet` with `isScrollControlled: true` responds to `MediaQuery.viewInsets.bottom` via `Scaffold.resizeToAvoidBottomInset` / `viewInsets` propagation. The sheet shifts upward when the keyboard appears. The `height: size.height` assignment still resolves correctly against the reduced available height: the container's tight constraint is clamped to the modal's new max height (which shrinks with viewInsets). No regression expected.

**Safe area:** `useSafeArea: true` is unchanged in `AddEditEventBottomSheet.show`. The `SafeArea` wrapper applied by the modal handles top notch/Dynamic Island inset. The container's `height: size.height` preference is clamped by the SafeArea constraints, so the container fills the safe area without overlapping the notch. No regression.

**Edit mode:** `EventTypeSelector` is hidden in edit mode (unchanged). The fix produces a consistent-height edit sheet as a benign side effect — no regression.

---

## Regression Check

| System | Impact | Risk | Assessment |
|---|---|---|---|
| Add Event sheet — layout | Direct target | NONE | Fixed by this change |
| Edit Event sheet — layout | Incidental benign side-effect | LOW | Constant height in edit mode is desirable |
| Auth / session | Unaffected | NONE | No auth code touched |
| Supabase RPC / queries | Unaffected | NONE | No data layer touched |
| Riverpod providers / controllers | Unaffected | NONE | No state management touched |
| Routing / deep links | Unaffected | NONE | `showModalBottomSheet` call sites unchanged |
| Platform parity (iOS/Android/macOS/web) | Widget is platform-agnostic | LOW | No platform-conditional code changed |
| Init order | Unaffected | NONE | No changes to `main.dart` or startup |
| Notifications | Unaffected | NONE | No notification code touched |
| All 16 `AddEditEventBottomSheet.show` call sites | Unaffected | NONE | Caller interface unchanged |

**Overall regression risk: LOW** — consistent with Architect plan assessment.

---

## Database Safety
n/a — no migrations, RLS changes, or RPC signatures modified.

---

## Analyzer Results

**Method: actually-exercised**

```
flutter analyze lib/features/events/widgets/event_editor_drawer.dart
Analyzing event_editor_drawer.dart...
No issues found! (ran in 1.9s)
```

Zero errors, warnings, or info-level findings. ✓

---

## Test Results

**Method: actually-exercised**

```
flutter test test/features/events/widgets/event_dropdown_test.dart
Summary: passed=6 failed=0
```

All 6 tests pass, including `EventEditorDrawer inside bottom sheet emits no layout errors on Android (rehearsal)`. The test exercises `EventEditorDrawer` inside `showModalBottomSheet(isScrollControlled: true)` on a 390×844 logical-pixel viewport and asserts zero `BoxConstraints forces an infinite width` or `RenderBox was not laid out` layout errors. The fixed layout (`height:` + `Expanded` + default `MainAxisSize.max`) passes with no issues. ✓

---

## Diff Safety Review

| Check | Result |
|---|---|
| Secrets / API keys in diff | None found (`grep -E '^\+.*(secret\|api_key\|apiKey\|password\|token)'`) |
| `TODO` / `FIXME` / `debugPrint` in diff | None found |
| Leftover test scaffolding | None |
| Accidental deletions | None — only the three intended lines removed |
| Unrelated formatting churn | None |

---

## Change Budget Review

| Metric | Plan | Actual | Assessment |
|---|---|---|---|
| Files created | 0 | 0 | ✓ |
| Files modified | 1 | 1 | ✓ |
| Net line delta in `event_editor_drawer.dart` | −1 | −3 (2 added, 5 removed) | Within budget (≤1.5×) |
| New public classes/methods | 0 | 0 | ✓ |
| New dependencies | 0 | 0 | ✓ |
| New migrations / edge functions | 0 | 0 | ✓ |

**Note on line delta:** The plan estimated −1 based on describing the `BoxConstraints(…)` block as a single line; it was 3 source lines. Actual net is −3 (3 lines removed for the BoxConstraints block + 1 added for `height:` = −2; `mainAxisSize` removal = −1; `Flexible` → `Expanded` = 0). This is entirely deletions of boilerplate, consistent with the Engineer's explanation. No bloat.

---

## Code Efficiency Review

- No new helpers, extensions, utils, or private widget classes introduced ✓
- No new providers, notifiers, or controllers ✓
- No new `_buildX()` methods or private `_Foo` widgets ✓
- No unused imports, variables, or dead code introduced ✓
- No barrel files, enum cases, config flags, or features-for-future-use ✓
- Change is a direct, minimal property swap at the single call site — no abstraction warranted ✓

---

## Issues Found

None.

---

*QA performed by: GitHub Copilot (Claude Sonnet 4.6), 2026-09-04*
