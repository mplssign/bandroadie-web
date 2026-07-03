# QA Report

## Feature Slug
`blockout-dashboard-view-drawer`

## Feature Title
Fix Block-Out Calendar Tap to Use BlockOutDrawer Instead of Event Editor

## Final Verdict
**APPROVED**

## Validation Summary
Implementation correctly replaces the calendar's block-out tap handler to use the dedicated `BlockOutDrawer` widget with proper permission-based mode routing. Code-path analysis confirms both calendar entry points (day detail sheet and "This Month's Events" section) now open the new drawer instead of the old event editor. The fix is minimal, preserves all existing permission logic, and introduces no regressions to gig/rehearsal handling.

## Architect Scope Review
- Scope adherence: **compliant**
- Files modified: **as expected** — only `lib/features/calendar/calendar_tab_content.dart` (1 import + 1 handler replacement)
- Files off-limits: **not touched** — verified `calendar_screen.dart` (dead code), drawer widget, event editor, day detail sheet, and home screens remain unchanged

## Completeness Check
- All Architect tasks implemented: **yes**
- Missing tasks: **none**

All six Architect tasks completed:
1. ✅ Import added at line 24 (after existing widget imports)
2. ✅ Block-out handler replaced (lines 195-215) to call `BlockOutDrawer.show()` with correct parameters
3. ✅ Gig handling (lines 227-246) and rehearsal handling (lines 255-263) remain byte-identical
4. ✅ `flutter analyze` passes with 0 errors
5. ✅ Diff verified: only 1 import + 1 handler block changed (8 additions, 5 deletions)
6. ✅ Engineer report created

## Behavior Verification
- Validation method: **code-path analysis**
- Result: **matches expected**

### Call Signature Verification
Verified `BlockOutDrawer.show()` signature in `add_block_out_drawer.dart` (lines 77-85):
```dart
static Future<bool?> show(
  BuildContext context, {
  required WidgetRef ref,
  required String bandId,
  BlockOutDrawerMode mode = BlockOutDrawerMode.create,
  DateTime? initialDate,
  BlockOutSpan? existingBlockOut,
  VoidCallback? onSaved,
})
```

Implementation call (lines 207-214) passes all required parameters correctly:
- ✅ `context` (positional)
- ✅ `ref: ref`
- ✅ `bandId: activeBandId` (with null guard at line 205)
- ✅ `mode: canEdit ? BlockOutDrawerMode.edit : BlockOutDrawerMode.viewOnly`
- ✅ `existingBlockOut: event.blockOutSpan` (type `BlockOutSpan?` matches expected)
- ✅ `onSaved: _refreshCalendarData`

### Permission Mapping
- Creator check: `EventPermissionHelper.canEditEvent(event)` (unchanged from original)
- Creator → `BlockOutDrawerMode.edit` (enables update/delete)
- Non-creator → `BlockOutDrawerMode.viewOnly` (read-only, Close button only)

### Coverage
Both entry points verified to route through modified `_openEditEventSheet`:
1. **Day detail sheet** (line 172 in `calendar_tab_content.dart`): `onEventTap: (event) { ... _openEditEventSheet(event); }`
2. **This Month's Events section** (line 473): `onEventTap: _openEditEventSheet`

### Drawer Widget Review (Out of Scope for Modification)
Reviewed `add_block_out_drawer.dart` for obvious defects since this widget has never been invoked before:
- ✅ Proper `mounted` checks after all `async` gaps (lines 167, 264, 315, 445)
- ✅ Null guards on `userId` and `widget.existingBlockOut`
- ✅ Controller disposal in `dispose()` method (line 154)
- ✅ Intentional error handling for One Calendar propagation (non-blocking errors logged, don't fail primary operations)
- ✅ Edit mode supports update (delete-then-create pattern) and delete with `onSaved` callback
- ✅ ViewOnly mode is properly read-only with only Close button

**No defects found.**

## Regression Check
- Risk level: **LOW**
- Systems reviewed: Calendar event handling, gig/rehearsal tap flows, block-out creation, permissions
- Regressions found: **none**

### Verified Unchanged Systems
- **Gig handling** (lines 218-246): Byte-identical to pre-change state. Confirmed gigs still open `ViewGigDrawer` for confirmed gigs and `AddEditEventBottomSheet` for potential gigs.
- **Rehearsal handling** (lines 249-263): Byte-identical to pre-change state. Continues to use permission checks and event editor.
- **Block-out creation flow**: Grep confirms `EventType.blockOut` still used in `event_editor_drawer.dart` (lines 297, 1227, 1525, 2154) for the creation flow via "Add Event" button → type selector. This is intentional per Architect plan ("Out of Scope" confirms creation should remain unchanged).
- **No other block-out handlers**: Grep for `AddEditEventBottomSheet.show.*blockOut` returns 0 matches. Grep for `BlockOutDrawer.show` returns only the modified file and the drawer widget itself, confirming no missed call sites.

### No Cross-System Impact
- No auth/session changes
- No Supabase RPC changes (verified with `git diff supabase/` — no output)
- No database migrations
- No init order changes (main.dart untouched)
- No controller/FocusNode disposal changes
- No rebuild trigger changes

### Dead Code Verification
`calendar_screen.dart` confirmed untouched (`git diff` returns no output).

## Database Safety
**Not applicable** — no database changes.

## Analyzer Results
Command: `flutter analyze lib/features/calendar/calendar_tab_content.dart`
Result: **0 errors, 0 warnings**

Output:
```
Analyzing calendar_tab_content.dart...
No issues found! (ran in 1.5s)
```

## Test Results
**Not run** — no tests explicitly required by Architect plan. The changed area (calendar event tap handlers) has no existing test coverage.

## Diff Safety Review
- Secrets: **none found**
- Debug artifacts: **none found**
- Unrelated changes: **none found**

Verified diff contains only:
1. One import statement for `add_block_out_drawer.dart` (line 24)
2. Replacement of block-out handler block in `_openEditEventSheet` method (lines 195-215)
3. Comment update (line 195) to reflect new behavior

Total change: 8 additions, 5 deletions in 1 file.

## Issues Found
**None**

---

## QA Notes

### Type Compatibility
Verified `event.blockOutSpan` type from `calendar_event.dart`:
- Field type: `BlockOutSpan?` (lines 24-45 of `calendar_event.dart`)
- Drawer expects: `BlockOutSpan?` (line 62 of `add_block_out_drawer.dart`)
- ✅ Types match exactly

### Entry Point Coverage
Both surfaces that render block-out events in the calendar are covered:
1. Tapping a day → day detail sheet opens → tapping block-out card → calls modified handler
2. Scrolling to "This Month's Events" → tapping block-out card → calls modified handler

No home/dashboard surfaces render block-outs (Architect plan correctly identified this as non-existent based on code search).

### Permission Logic Preservation
The existing permission check using `EventPermissionHelper.canEditEvent(event)` is preserved exactly. This checks if `currentUserId == event.blockOutSpan.userId`, maintaining the creator-only edit rule for block-outs.

### Git State
- Branch: `bug/blockout-dashboard-view-drawer` ✓
- Working tree: Only `calendar_tab_content.dart` modified ✓
- Untracked: Only `docs/features/` directories ✓
- `pubspec.lock`: Clean (no diff) ✓
- No commits made ✓

---

**QA Agent:** Verified 2026-07-03
