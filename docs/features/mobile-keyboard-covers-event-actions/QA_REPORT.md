# QA_REPORT — bug/mobile-keyboard-covers-event-actions

## Feature Slug

bug/mobile-keyboard-covers-event-actions

## Feature Title

Mobile Keyboard Covers Event Action Buttons

## Validation Summary

All 4 Architect tasks were implemented exactly as specified across 2 files. No files were created. No unrelated files were modified. No database, auth, routing, or state management changes were introduced. The implementation is layout-only, modifying `maxHeight` constraints and padding in two drawer widgets. Static analysis passes with zero issues.

## Architect Scope Review

The Architect plan defines 4 tasks:

1. Event editor drawer `maxHeight` fix — subtract `viewInsets.bottom` before applying 0.9 multiplier.
2. Event editor drawer bottom actions wrapper — wrap `EventEditorBottomActions` and `EventEditorViewOnlyClose` in a `Container` with horizontal page padding, top border separator, and safe area bottom padding.
3. Block out drawer `maxHeight` fix — subtract `keyboardHeight` before applying 0.9 multiplier.
4. Block out drawer bottom padding simplification — replace `keyboardHeight > 0 ? keyboardHeight : safeBottom` with `safeBottom`.

**Scope boundaries respected**: No new widgets, no state changes, no architecture changes, no database impact, no RLS/RPC changes. Out-of-scope items (file refactoring, widget internal changes, desktop/web layout, keyboard-dismiss gestures) were correctly avoided.

## Implementation Review

### Task 1 — Event editor drawer maxHeight fix
- **File**: `lib/features/events/widgets/event_editor_drawer.dart` (line 1704)
- **Change**: `maxHeight: MediaQuery.of(context).size.height * 0.9` → `maxHeight: (MediaQuery.of(context).size.height - bottomPadding) * 0.9`
- **Variable source**: `bottomPadding` = `MediaQuery.of(context).viewInsets.bottom` (line 1696)
- **Matches Architect plan**: Yes ✓

### Task 2 — Event editor drawer bottom actions wrapper
- **File**: `lib/features/events/widgets/event_editor_drawer.dart` (lines 1901–1941)
- **Change**: Wrapped both `EventEditorBottomActions` and `EventEditorViewOnlyClose` in a single `Container` using a ternary for the `child` property.
- **Container properties**:
  - `padding: EdgeInsets.only(left: Spacing.pagePadding, right: Spacing.pagePadding, top: Spacing.space12, bottom: safeBottom + Spacing.space12)` ✓
  - `decoration: BoxDecoration(color: AppColors.cardBg, border: Border(top: BorderSide(color: AppColors.borderMuted.withValues(alpha: 0.5))))` ✓
- **Matches Architect plan**: Yes ✓

### Task 3 — Block out drawer maxHeight fix
- **File**: `lib/features/calendar/widgets/add_block_out_drawer.dart` (lines 417–418)
- **Change**: `maxHeight: MediaQuery.of(context).size.height * 0.9` → `maxHeight: (MediaQuery.of(context).size.height - keyboardHeight) * 0.9`
- **Variable source**: `keyboardHeight` = `MediaQuery.of(context).viewInsets.bottom` (line 405)
- **Matches Architect plan**: Yes ✓

### Task 4 — Block out drawer bottom padding simplification
- **File**: `lib/features/calendar/widgets/add_block_out_drawer.dart` (line 756)
- **Change**: `final bottomPadding = keyboardHeight > 0 ? keyboardHeight : safeBottom;` → `final bottomPadding = safeBottom;`
- **Removed comment**: `// Use the max of safe area and keyboard height for bottom padding` (no longer accurate)
- **Matches Architect plan**: Yes ✓

## Files Verified

| File | Status |
|---|---|
| `lib/features/events/widgets/event_editor_drawer.dart` | Modified — 2 changes as expected |
| `lib/features/calendar/widgets/add_block_out_drawer.dart` | Modified — 2 changes as expected |
| `docs/features/mobile-keyboard-covers-event-actions/ARCHITECT_PLAN.md` | New — expected |
| `docs/features/mobile-keyboard-covers-event-actions/ENGINEER_REPORT.md` | New — expected |

No unexpected files created, modified, or deleted.

## Bug Reproduction Result

**Code-path verification only** (no device/simulator runtime validation performed):

- **Pre-fix path**: `maxHeight = screenHeight * 0.9`. With keyboard open (e.g., ~346px on iPhone 14), the 760px container exceeds the ~498px visible viewport. Bottom action buttons render behind the keyboard. Bug confirmed via code analysis.
- **Post-fix path**: `maxHeight = (screenHeight - keyboardHeight) * 0.9`. With same keyboard, container is ~448px — fits within visible viewport. Bottom actions are within the constrained container and visible above the keyboard.
- **No-keyboard path**: `keyboardHeight = 0` → formula reduces to `screenHeight * 0.9`. Identical to pre-fix behavior. No regression.
- **Desktop/web path**: `viewInsets.bottom` is typically 0. No behavioral change.

**Limitation**: Full visual and interactive validation requires running on a mobile device or simulator. This QA validates the correctness of the code logic, not the rendered UI.

## Completeness Check

| Architect Task | Implemented | Verified |
|---|---|---|
| 1. Event editor maxHeight fix | ✓ | ✓ |
| 2. Event editor bottom actions wrapper | ✓ | ✓ |
| 3. Block out drawer maxHeight fix | ✓ | ✓ |
| 4. Block out drawer bottom padding simplification | ✓ | ✓ |

All tasks complete. No skipped requirements. No partial implementation.

## Regression Check

| System | Impact | Risk |
|---|---|---|
| Gig creation/editing drawers | Layout change only. No-keyboard path unchanged. | None |
| Rehearsal creation/editing drawers | Same drawer widget. Same analysis. | None |
| Block out creation (standalone) | maxHeight fix + simplified padding. No-keyboard path unchanged. | None |
| Block out creation (via event editor) | Uses EventEditorDrawer path. | None |
| Setlists / Song catalog | Not touched | None |
| Notifications | Not touched | None |
| Auth / Session | Not touched | None |
| Routing / Deep links | Not touched | None |
| Database reads/writes | Not touched | None |
| Desktop / Web layout | viewInsets.bottom = 0 → formula unchanged | None |
| Init order | Not touched | None |
| Config paths | Not touched | None |

## Regression Risk Level

**LOW**

Changes are pure layout constraints and padding in 2 files. When no keyboard is present, both formulas are mathematically identical to pre-fix behavior. No state, data, routing, auth, or business logic is affected.

## Database Safety Review

Not Applicable. No database changes in this bug fix.

## Analyzer Results

- Command: `flutter analyze`
- Result: **No issues found** (0 errors, 0 warnings)

## Test Results

Not Run. The Architect plan does not require tests. No existing tests cover these layout-only changes. This is consistent with Architect scope.

## Diff Safety Review

| Check | Result |
|---|---|
| Secrets / credentials | None ✓ |
| Config drift | None ✓ |
| Unrelated refactors | None ✓ |
| Formatting-only churn | None ✓ |
| Accidental file deletions | None ✓ |
| Debug artifacts / console spam | None ✓ |
| Temporary flags / test scaffolding | None ✓ |
| Init order changes | None ✓ |
| Platform behavior regressions | None (desktop/web unaffected) ✓ |
| Security violations | None ✓ |

## Issues Found

None.

## Final Verdict

**APPROVED**

Implementation matches the Architect plan exactly across all 4 tasks. Only the 2 expected files were modified with minimal, focused changes. No scope creep, no architecture violations, no security concerns, no database impact, no regressions identified. Static analysis passes clean. The code logic is correct and the fix properly addresses the root cause of keyboard-obscured action buttons on mobile.
