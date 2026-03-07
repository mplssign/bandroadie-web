# QA Report — Unified Add Event Workflow

**Feature Slug:** `unified-add-event-workflow`
**Feature Title:** Unified "+ Add Event" Workflow
**Branch:** `feature/unified-add-event-workflow`
**Date:** 2026-03-07

---

## Validation Summary

This feature consolidates three separate event creation entry points (Schedule Rehearsal, Create Gig, Block Out) into a single "+ Add Event" action that opens the existing Event Editor Drawer with a three-way toggle: **Rehearsal | Gig | Block Out**. Pure Flutter UI refactor — no database, RLS, or backend changes.

**All 8 Architect tasks implemented. All 10 expected files modified. No unexpected files touched.**

---

## Bug Reproduction Result

N/A — this is a feature, not a bug fix.

---

## Implementation Review

### Task-by-Task Verification

| # | Architect Task | Status | Notes |
|---|---|---|---|
| 1 | Extend `EventType` enum with `blockOut` | ✅ | `displayName` = `'Block Out'` |
| 2 | Block out form in Event Editor Drawer | ✅ | Start Date, End Date (optional), Reason (optional). RBAC toggle filtering, save/delete logic, edit mode population. +379 lines. |
| 3 | Update `AddEditEventBottomSheet` wrapper | ✅ | `existingBlockOut` parameter pass-through |
| 4 | Simplify `QuickActionsRow` | ✅ | 3 buttons → 1 `+ Add Event` + `+ Create Setlist` |
| 5 | Update `EmptyHomeState` | ✅ | Consolidated callbacks |
| 6 | Update dashboard screens | ✅ | Both `home_screen.dart` and `home_tab_content.dart` consolidated |
| 7 | Update calendar screens | ✅ | Both screens: single button, block out edit routed through event editor |
| 8 | Update tips & tricks text | ✅ | References "+ Add Event" |

### Architecture Compliance

- ✅ No initialization order changes
- ✅ No config path changes
- ✅ No new dependencies
- ✅ Feature-first structure preserved
- ✅ Riverpod patterns consistent
- ✅ `BlockOutDrawer` retained (not deleted) per Architect plan
- ✅ Existing `BlockOutRepository` reused — no new data layer

### RBAC Verification

- ✅ `_buildEventTypeToggle()` filters out `rehearsal` AND `blockOut` for contributors
- ✅ `_saveBlockOut()` has defense-in-depth contributor check
- ✅ Dashboard buttons hidden for contributors without gig permission (`onAddEvent: null`)
- ✅ Calendar buttons hidden for contributors without gig permission
- ✅ View-only mode for non-creator block out viewing (`viewOnly: !canEdit`)

### Block Out Flow Verification

- ✅ Create: delegates to `BlockOutRepository.createBlockOut()`
- ✅ Edit: uses delete-then-create pattern (matches original `BlockOutDrawer`)
- ✅ Delete: confirmation dialog → `BlockOutRepository.deleteBlockOutSpan()`
- ✅ Calendar refresh after save/delete via `calendarProvider.notifier.invalidateAndRefresh()`
- ✅ Date validation: end date cannot be before start date

---

## Files Verified

| File | Change Type | Verified |
|---|---|---|
| `lib/features/events/models/event_form_data.dart` | Enum extension | ✅ |
| `lib/features/events/widgets/event_editor_drawer.dart` | Block out form/logic | ✅ |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Parameter pass-through | ✅ |
| `lib/features/home/widgets/quick_actions_row.dart` | API simplification | ✅ |
| `lib/features/home/widgets/empty_home_state.dart` | API simplification | ✅ |
| `lib/features/home/home_screen.dart` | Handler consolidation | ✅ |
| `lib/features/home/home_tab_content.dart` | Handler consolidation | ✅ |
| `lib/features/calendar/calendar_screen.dart` | Single button, edit routing | ✅ |
| `lib/features/calendar/calendar_tab_content.dart` | Single button, edit routing | ✅ |
| `lib/components/overlays/tips_and_tricks_overlay.dart` | Tip text update | ✅ |

No files created. No files deleted. No migrations. No config changes.

---

## Regression Check

### Systems Tested

| System | Impact | Status |
|---|---|---|
| Event creation (gigs) | Direct — same drawer, toggle updated | ✅ No regression (form fields unchanged for gig type) |
| Event creation (rehearsals) | Direct — same drawer, toggle updated | ✅ No regression (form fields unchanged for rehearsal type) |
| Block out creation | Direct — moved into event editor | ✅ Same repository, same data pattern |
| Calendar display | Indirect — action buttons changed | ✅ Single button replaces two-button row |
| Dashboard quick actions | Direct — buttons consolidated | ✅ Single "+ Add Event" button |
| RBAC / permissions | Direct — toggle filtering extended | ✅ Contributors excluded from blockOut type |
| Block out editing | Direct — routed through event editor | ✅ Delete-then-create pattern preserved |
| Setlist creation | None — separate workflow | ✅ Unaffected |
| Notifications | None — not modified | ✅ Unaffected |
| Auth/session | None — not modified | ✅ Unaffected |
| Routing/deep links | None — not modified | ✅ Unaffected |

### Regression Risk Level: **LOW**

Rationale: Pure UI consolidation. No data model changes, no repository changes, no database changes, no auth changes. All event creation logic reuses existing proven code paths. Block out save/delete logic mirrors the original `BlockOutDrawer` exactly.

---

## Analyzer Results

```
flutter analyze
Analyzing bandroadie...
No issues found! (ran in 4.3s)
```

**0 errors, 0 warnings.** ✅

---

## Diff Review

- ✅ No secrets or credentials in diff
- ✅ No config file changes
- ✅ No platform-specific file changes (entitlements, manifests, etc.)
- ✅ No unrelated refactors (two minor auto-formatter whitespace changes in `event_form_data.dart` — cosmetic only)
- ✅ No new dependencies added
- ✅ +1,188 / -349 lines — reasonable for feature scope

---

## Warnings (Non-Blocking)

1. **Minor RBAC inconsistency in `home_tab_content.dart`:** The `_handleAddEvent()` method does not include the same early-return guard (`if (perms.isContributor && !perms.canCreateGigs) return;`) that exists in `home_screen.dart`. This is **not a vulnerability** because the button is already hidden for that role via `onAddEvent: (isContributor && !canCreateGig) ? null : _handleAddEvent`. However, adding the defense-in-depth check would be consistent. **Optional fix — not blocking.**

2. **Two auto-formatter changes in `event_form_data.dart`:** Lines 167 and 523 have whitespace-only reformatting not related to the feature. These are harmless but add noise to the diff.

---

## Final Verdict

# ✅ APPROVED

All Architect tasks implemented correctly. Architecture preserved. RBAC enforced at multiple levels. No regressions detected. Analyzer clean. Diff clean. Safe to commit.
