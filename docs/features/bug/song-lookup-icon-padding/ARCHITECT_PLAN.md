# ARCHITECT_PLAN.md — Song Lookup Icon Padding

**Feature Slug:** `bug/song-lookup-icon-padding`  
**Type:** bug  
**Branch:** `bug/song-lookup-icon-padding`  
**Prepared:** 2026-09-01

---

## Problem Summary

In two places, search-style `AppTextField` widgets render prefix/suffix icons (magnifying glass and clear button) flush against the field's rounded border with no padding. This violates the established design convention where icons should have 12px breathing room on all sides, creating a visual inconsistency and potentially making small touch targets harder to hit accurately.

**Affected locations:**

1. Song Lookup overlay search field (`lib/features/setlists/widgets/song_lookup_overlay.dart`, `_buildSearchField()`, ~line 495)
2. Setlist Detail inline filter field (`lib/features/setlists/setlist_detail_screen.dart`, ~line 2293)

**Evidence of correct pattern:** `lib/features/contacts/widgets/az_search_field.dart` wraps both prefix and suffix icons in `Padding(padding: EdgeInsets.all(12.0), ...)` — this is the template to follow.

---

## Root Cause

**Confidence:** HIGH (confirmed in code)

`AppTextField` (UI wrapper) passes `prefixIcon`/`suffixIcon` directly to Forui's `FTextField.prefixBuilder`/`suffixBuilder` without adding padding. **The responsibility for padding falls on the caller.**

Both buggy files pass bare `Icon` widgets and `GestureDetector(child: Icon(...))` structures without wrapping them in `Padding`, whereas the correct pattern wraps icons in:

```dart
Padding(
  padding: EdgeInsets.all(Spacing.space12),  // or EdgeInsets.all(12.0)
  child: Icon(...),
)
```

This is purely a **UI layout issue** — no logic, state, or data model changes are required.

---

## Reference Docs Consulted

Not applicable — this is a UI/styling bug, not a domain-specific feature. No notifications, auth, or business logic reference docs required.

---

## Existing System Analysis

**Current behavior:**

1. **song_lookup_overlay.dart** (`_buildSearchField`, line ~495):
   - Renders `Icon(AppIcons.search, ...)` directly as `prefixIcon`
   - Renders `GestureDetector(child: Icon(AppIcons.close, ...))` directly as `suffixIcon`
   - Result: icons touch the rounded border edges

2. **setlist_detail_screen.dart** (~line 2293):
   - Renders `Icon(AppIcons.search, ...)` directly as `prefixIcon`
   - Renders `GestureDetector(child: Icon(AppIcons.close, ...))` directly as `suffixIcon`
   - Result: icons touch the rounded border edges

3. **az_search_field.dart** (CORRECT pattern, line ~34–54):
   - Wraps `prefixIcon` in `Padding(padding: const EdgeInsets.all(12.0), child: Icon(...))`
   - Wraps `suffixIcon` in `Padding(padding: const EdgeInsets.all(12.0), child: GestureDetector(child: Icon(...)))`
   - Result: icons have consistent 12px padding on all sides

**Why:** Forui's `FTextField` does not add padding to prefix/suffix builders — it's the widget wrapper's job. The codebase already knows this (evidenced by `az_search_field.dart`), but two newer uses of `AppTextField` forgot to apply the pattern.

---

## Proposed Solution

Apply the **established design pattern** from `az_search_field.dart` to both problem locations.

**Changes:**

1. **song_lookup_overlay.dart** (`_buildSearchField`):
   - Wrap `prefixIcon` Icon in `Padding(padding: EdgeInsets.all(Spacing.space12), child: ...)`
   - Wrap `suffixIcon` Icon in `Padding(padding: EdgeInsets.all(Spacing.space12), child: ...)`

2. **setlist_detail_screen.dart** (inline filter field):
   - Wrap `prefixIcon` Icon in `Padding(padding: EdgeInsets.all(Spacing.space12), child: ...)`
   - Wrap `suffixIcon` Icon in `Padding(padding: EdgeInsets.all(Spacing.space12), child: ...)`

**Why this solution:**

- Minimal: only 4 wrapping changes (2 per file), no logic changes
- Safe: follows established pattern already proven in codebase
- Consistent: uses `Spacing.space12` token (already imported in both files)
- Isolated: affects only UI layout, no state or data mutations

---

## Database Impact

**Status:** Not applicable

This is a client-side UI layout fix. No database schemas, RLS policies, RPCs, triggers, or migrations are involved.

---

## Flutter Architecture Changes

**Status:** None

- No state changes
- No providers or controllers affected
- No repository changes
- Pure widget layout adjustment

---

## Files to Create

**Status:** None

All necessary files already exist. No new files are required.

---

## Files to Modify

| File                                                     | Change                                                                                                                                                |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_lookup_overlay.dart` | Wrap `prefixIcon` and `suffixIcon` in `Padding(padding: EdgeInsets.all(Spacing.space12), child: ...)` in `_buildSearchField()` method (line ~495–510) |
| `lib/features/setlists/setlist_detail_screen.dart`       | Wrap `prefixIcon` and `suffixIcon` in `Padding(padding: EdgeInsets.all(Spacing.space12), child: ...)` in the inline filter field (line ~2293–2310)    |

---

## Files Off-Limits

| File                                                 | Reason                                                                                                                                           |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/components/ui/app_text_field.dart`              | Do not modify the wrapper — the pattern is correct; padding is caller's responsibility (evidence: `az_search_field.dart` uses pattern correctly) |
| `lib/features/contacts/widgets/az_search_field.dart` | Already correct; do not change                                                                                                                   |
| `lib/main.dart`                                      | No changes to init or config                                                                                                                     |
| Any database file                                    | No database changes                                                                                                                              |

---

## System Impact Map

| System                                 | Impact                                                    |
| -------------------------------------- | --------------------------------------------------------- |
| Gigs                                   | unaffected                                                |
| Rehearsals                             | unaffected                                                |
| Setlists / Catalog                     | unaffected (UI layout only, no data changes)              |
| Members / RBAC                         | unaffected                                                |
| Auth / Session                         | unaffected                                                |
| Routing                                | unaffected                                                |
| Notifications                          | unaffected                                                |
| Platform (iOS / Android / Web / macOS) | affected (visual layout consistency across all platforms) |

---

## Regression Risk

**Level:** LOW

**Rationale:**

- Pure UI styling change (padding adjustment)
- No logic, state, or data mutations
- No changes to event handlers, controllers, or repositories
- Follows established pattern already used elsewhere
- Isolated to 2 locations, 4 icon wrappers total
- No async operations, no lifecycle changes
- No interaction with auth, session, routing, or initialization

---

## Engineer Task Breakdown

The Engineer must execute these tasks in order:

### Task 1: Modify song_lookup_overlay.dart

- Open `lib/features/setlists/widgets/song_lookup_overlay.dart`
- Locate `_buildSearchField()` method (around line 495)
- Wrap the `prefixIcon` Icon widget in `Padding(padding: EdgeInsets.all(Spacing.space12), child: Icon(...))`
- Wrap the `suffixIcon` GestureDetector+Icon widget in `Padding(padding: EdgeInsets.all(Spacing.space12), child: GestureDetector(...))`
- Verify `Spacing` is imported (it should be from line 6: `import '../../../app/theme/design_tokens.dart'`)
- Commit: `git add lib/features/setlists/widgets/song_lookup_overlay.dart`

### Task 2: Modify setlist_detail_screen.dart

- Open `lib/features/setlists/setlist_detail_screen.dart`
- Locate the inline "Filter songs..." field (around line 2293)
- Wrap the `prefixIcon` Icon widget in `Padding(padding: EdgeInsets.all(Spacing.space12), child: Icon(...))`
- Wrap the `suffixIcon` GestureDetector+Icon widget in `Padding(padding: EdgeInsets.all(Spacing.space12), child: GestureDetector(...))`
- Verify `Spacing` is imported (it should be from line 11: `import 'package:bandroadie/app/theme/design_tokens.dart'`)
- Commit: `git add lib/features/setlists/setlist_detail_screen.dart`

### Task 3: Verify and Prepare for QA

- Run `flutter analyze` and confirm 0 errors
- Generate git diff: `git diff HEAD~2 HEAD`
- Write `ENGINEER_REPORT.md` documenting what was changed and why
- All tasks must be marked complete before handing to QA

---

## Verification Plan

### Tier 1 — Pre-deployment (Visual Inspection Only)

No pre-deployment testing is required for this change. It is a pure client-side UI layout adjustment with no backend dependencies, database queries, or async state changes. The code cannot be verified in isolation without rendering.

### Tier 2 — Post-deployment (Manual Visual Validation)

After deploying to development/staging, QA must verify on all platforms:

**Test Case 1: Song Lookup Overlay (ios, android, web, macos)**

1. Open any setlist
2. Tap "Add Songs" to open Song Lookup overlay
3. Observe the search field at the top
4. **Verify:** The magnifying glass icon on the left has 12px padding away from the field's left border
5. **Verify:** The clear (X) button on the right has 12px padding away from the field's right border
6. Type some text into the search field
7. **Verify:** Both icons maintain consistent 12px padding at all times

**Test Case 2: Setlist Detail Filter Field (ios, android, web, macos)**

1. Open any setlist
2. Scroll to the inline "Filter songs..." search bar
3. Observe the search field
4. **Verify:** The magnifying glass icon on the left has 12px padding away from the field's left border
5. **Verify:** The clear (X) button on the right has 12px padding away from the field's right border (appears when text is entered)
6. Type some text into the filter field
7. **Verify:** Both icons maintain consistent 12px padding at all times
8. Clear the field (tap the X button)
9. **Verify:** The X button disappears and the search field resets

**Test Case 3: Consistency Check**

1. Navigate to a Contacts list with the A–Z search field
2. Observe the search field's icon padding
3. **Verify:** The Song Lookup overlay and Setlist Detail filter field icons match the padding of the A–Z search field exactly (all 12px on all sides)

**Expected result:** All icons have uniform 12px padding on all sides across all three search fields. No icons should touch the field borders.

---

## Sign-Off

- [ ] Architect: Ready for Engineer implementation
- [ ] Manager: Architecture approved (optional; depends on team process)
- [ ] Engineer: Implementation complete
- [ ] QA: Verification passed
