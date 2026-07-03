# QA Report

## Feature Slug
bug/blockout-creator-view-first

## Feature Title
Block-out view-first interaction — Revision 2

## Final Verdict
**APPROVED**

## Validation Summary
Verified that ViewBlockOutDrawer matches the established view-drawer pattern (stateless, no title bar, drag handle → date header, detail rows, Done + Edit footer). Confirmed complete removal of viewOnly artifacts from BlockOutDrawer (enum now has only create/edit, no canEdit parameter, no _isReadOnly, no banner, no disabled fields, no viewOnly footer). Both call sites correctly open ViewBlockOutDrawer first with onEdit callback that opens BlockOutDrawer in edit mode. Analyzer passes with 0 errors. All edge cases handled correctly.

## Architect Scope Review
- Scope adherence: **compliant**
- Files modified: **as expected** (3 modified, 1 created, all in approved list)
- Files off-limits: **not touched** (verified via git diff --name-only)

## Completeness Check
- All Architect tasks implemented: **yes**
- Missing tasks: **none**

All 5 tasks from Architect plan completed:
- Task 1: Created ViewBlockOutDrawer widget (lib/features/calendar/widgets/view_block_out_drawer.dart)
- Task 2: Updated call site in calendar_tab_content.dart (line 209)
- Task 3: Updated call site in calendar_screen.dart (line 229)
- Task 4: Removed viewOnly mode from BlockOutDrawer completely
- Task 5: Verified complete v1 artifact removal

## Behavior Verification
- Validation method: **code-path analysis** (runtime testing is post-deployment per Architect plan Tier 2)
- Result: **matches expected**

### ViewBlockOutDrawer Template Parity

Verified against view_rehearsal_drawer.dart and view_gig_drawer.dart:

**Stateless widget**: view_block_out_drawer.dart:8 - `class ViewBlockOutDrawer extends StatelessWidget`

**NO title bar**: view_block_out_drawer.dart:88-98 - Drag handle goes directly to scrollable body with no title bar between them, matching ViewRehearsalDrawer:161-171 and ViewGigDrawer pattern.

**Drag handle → large date header**: 
- view_block_out_drawer.dart:109-138 - Header block with date in headlineMedium style
- Matches ViewRehearsalDrawer:182-228 and ViewGigDrawer:279-329 pattern

**Multi-day format**: 
- view_block_out_drawer.dart:117-135 - Single day shows full date only; multi-day shows start date (headlineMedium) + "Through [end date]" subtitle (title3)
- Conditional on `existingBlockOut.isMultiDay` at line 127

**_DetailRow for reason**:
- view_block_out_drawer.dart:144-148 - Detail row with label "Reason", value shows reason text
- Omitted when empty: line 144 checks `if (existingBlockOut.reason.isNotEmpty)`
- _DetailRow implementation at lines 194-238 matches reference pattern (68px label width, expanded value, divider below)
- Matches ViewGigDrawer:451-511 structure

**Done + Edit footer**:
- view_block_out_drawer.dart:157-187 - BrandActionButton 'Done' + TextButton 'Edit' (if canEdit)
- Structure/spacing/styles match ViewRehearsalDrawer:267-298 and ViewGigDrawer:407-438 exactly
- Edit button only shown if canEdit == true (line 170)

**_handleEdit pops then calls onEdit()**:
- view_block_out_drawer.dart:38-41 - Pops drawer (line 39), then calls onEdit() callback (line 40)
- Matches ViewRehearsalDrawer:48-50 and ViewGigDrawer:208-210 pattern

### Complete viewOnly Removal from BlockOutDrawer

Verified all v1 viewOnly artifacts removed from add_block_out_drawer.dart:

**Enum**: git diff line 48 - `enum BlockOutDrawerMode { create, edit }` (viewOnly removed)

**canEdit parameter**: git diff shows removal from lines 65, 76, 88 (constructor and static method signatures). Grep verification: `grep -n "canEdit" lib/features/calendar/widgets/add_block_out_drawer.dart` returns no matches.

**_isReadOnly getter**: git diff lines 116-117 show removal. Grep verification: `grep -n "_isReadOnly" lib/features/calendar/widgets/add_block_out_drawer.dart` returns no matches.

**_handleEdit method**: git diff shows removal from BlockOutDrawer (lines 164-175 per Architect plan). ViewBlockOutDrawer has its own at view_block_out_drawer.dart:38-41.

**Banner**: git diff lines 615-654 removed entire "Only the creator can edit or delete this block out" banner block.

**viewOnly footer**: git diff lines 856-896 removed entire viewOnly footer branch from _buildBottomButtons.

**Disabled field logic**: 
- Date field: git diff lines 761-776 removed `|| _isReadOnly` from onTap check, removed _isReadOnly ternaries for fillColor/textColor, removed `if (!_isReadOnly)` guard around calendar icon
- Text field: git diff lines 815-826 removed `&& !_isReadOnly` from enabled check, removed _isReadOnly ternaries for textColor and fillColor

**Stale comments**: Engineer Report Post-Implementation Corrections section confirms removal of three stale comments referencing viewOnly mode (lines 26, 55, 129).

**Mode enum verification**: Grep verification: `grep -n "BlockOutDrawerMode.viewOnly" lib/features/calendar/widgets/add_block_out_drawer.dart` returns no matches.

### Call Sites

**calendar_tab_content.dart**:
- Line 209: Calls `ViewBlockOutDrawer.show()` (not BlockOutDrawer)
- Line 211: Passes `existingBlockOut: event.blockOutSpan!`
- Line 212: Passes `canEdit: canEdit`
- Lines 213-222: onEdit callback opens BlockOutDrawer in edit mode with ref, activeBandId, BlockOutDrawerMode.edit, existingBlockOut, onSaved
- Null-safety: Line 199 guards with `if (event.isBlockOut && event.blockOutSpan != null)`, making the `!` safe at line 211

**calendar_screen.dart**:
- Line 229: Calls `ViewBlockOutDrawer.show()` (not BlockOutDrawer)
- Line 231: Passes `existingBlockOut: event.blockOutSpan!`
- Line 232: Passes `canEdit: canEdit`
- Lines 233-242: onEdit callback opens BlockOutDrawer in edit mode with ref, activeBandId, BlockOutDrawerMode.edit, existingBlockOut, onSaved
- Null-safety: Line 219 guards with `if (event.isBlockOut && event.blockOutSpan != null)`, making the `!` safe at line 231

### Edge Cases

**Single-day vs multi-day header**:
- view_block_out_drawer.dart:127-135 - Conditional rendering based on `existingBlockOut.isMultiDay`
- Single day: Shows only start date in headlineMedium (line 117-125)
- Multi-day: Shows start date + "Through [end date]" subtitle (lines 127-135)

**Empty reason handling**:
- view_block_out_drawer.dart:144 - Detail row omitted entirely when `existingBlockOut.reason.isNotEmpty` is false
- No crash or empty row rendered when reason is empty

## Regression Check
- Risk level: **LOW**
- Systems reviewed: Gigs, Rehearsals, Setlists/Catalog, Members/RBAC, Auth/Session, Routing, Notifications, Platform
- Regressions found: **none**

Rationale:
- Changes localized to block-out view flow only
- No changes to block-out creation, deletion, or data persistence
- Gig and rehearsal view/edit flows unchanged (verified files off-limits)
- RBAC permission checks unchanged (reuses existing EventPermissionHelper.canEditEvent())
- Pattern matches established view-first UX exactly
- No database, RLS, or RPC changes
- BlockOutDrawer edit mode unchanged (only viewOnly mode removed)

## Database Safety
**Not applicable** (no database changes in this feature)

## Analyzer Results
Command: `flutter analyze lib/`

Result: **0 errors** / 4 warnings (all pre-existing setlists deprecation warnings)

Warnings (all pre-existing, unrelated to block-out changes):
1. lib/features/setlists/new_setlist_screen.dart:984:13 - onReorder deprecated
2. lib/features/setlists/setlist_detail_screen.dart:1716:29 - axisAlignment deprecated
3. lib/features/setlists/setlist_detail_screen.dart:2295:23 - onReorder deprecated
4. lib/features/setlists/setlists_tab_content.dart:511:25 - onReorder deprecated

These match the 4 known warnings mentioned in Engineer Report and Architect plan.

## Test Results
**Not run** (per Architect plan Verification Plan, all testing is manual UI testing post-deployment in Tier 2)

## Diff Safety Review
- Secrets: **none found**
- Debug artifacts: **none found** (one debug print removed in calendar_tab_content.dart line 196)
- Unrelated changes: **none found**

Verified:
- No secrets or API keys in diff
- No environment variables outside approved scope
- No test scaffolding in production code
- No accidental file deletions
- No unrelated formatting churn
- Known untracked directories (macos/swiftpm, docs/features/band-data-isolation-audit) excluded per Manager instruction

## Issues Found
**None**

## QA Verification Commands Executed

```bash
# Branch verification
git branch --show-current
# Result: bug/blockout-creator-view-first ✓

# Analyzer verification
flutter analyze lib/
# Result: 0 errors, 4 pre-existing setlists warnings ✓

# Off-limits files verification
git diff --name-only lib/main.dart lib/features/calendar/widgets/day_detail_bottom_sheet.dart lib/features/calendar/calendar_controller.dart lib/features/calendar/block_out_repository.dart lib/features/events/widgets/add_edit_event_bottom_sheet.dart lib/features/gigs/widgets/view_gig_drawer.dart lib/features/rehearsals/widgets/view_rehearsal_drawer.dart
# Result: no output (no off-limits files modified) ✓

# Removed artifacts verification
grep -n "_isReadOnly\|BlockOutDrawerMode.viewOnly\|canEdit" lib/features/calendar/widgets/add_block_out_drawer.dart
# Result: no matches (complete removal confirmed) ✓
```

## Summary

Implementation correctly replaces the disabled form-field body in BlockOutDrawer viewOnly mode with a dedicated ViewBlockOutDrawer widget that presents block-out data using proper read-only detail rows, matching the established view-drawer pattern from gigs and rehearsals exactly. All viewOnly artifacts completely removed from BlockOutDrawer. Both call sites correctly implement view-first flow with Edit transition. No regressions introduced. Safe to commit.
