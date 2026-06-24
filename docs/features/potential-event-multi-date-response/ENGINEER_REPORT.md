# Engineer Report

## Feature Slug

`bug/potential-event-multi-date-response`

## Feature Title

Potential Event — Multi-Date Response Bugs (Tab Navigation + Android Persistence Failure)

## Goal

Fix two critical bugs affecting multi-date potential event responses on dashboard cards:

1. **Tab navigation broken** — Users cannot use keyboard (Tab key) to navigate between YES/NO response buttons on potential event dashboard cards
2. **Android multi-date response persistence failure** — When a user responds "yes" to multiple dates on a potential event via the dashboard card, only the first date's response persists to the database

## Architect Tasks Completed

- [x] Task 1 — Add `_savingInProgress` state management
- [x] Task 2 — Guard `didUpdateWidget` against in-progress saves
- [x] Task 3 — Add user-visible error handling
- [x] Task 4 — Add saving indicator to buttons
- [x] Task 5 — Add keyboard navigation infrastructure
- [x] Task 6 — Wrap buttons with Focus + keyboard handlers
- [x] Task 7 — Audit and fix rehearsal_card.dart (same pattern, same fixes applied)
- [ ] Task 8 — Test keyboard navigation (requires running app — manual QA)
- [ ] Task 9 — Test multi-date persistence (requires running app — manual QA)
- [ ] Task 10 — Test error handling (requires running app — manual QA)

## Files Created

- `docs/features/potential-event-multi-date-response/ENGINEER_REPORT.md`

## Files Modified

- `lib/features/home/widgets/potential_gig_card.dart` — Applied all 6 fixes (state management, didUpdateWidget guard, error handling, loading indicator, keyboard nav)
- `lib/features/home/widgets/rehearsal_card.dart` — Applied identical fixes (same bug pattern confirmed and fixed)

## Analyzer Results

**Command:** `flutter analyze`  
**Result:** 0 errors, 2 info-level suggestions

```
info • The private field _savingInProgress could be 'final' •
       lib/features/home/widgets/potential_gig_card.dart:62:22 •
       prefer_final_fields
info • The private field _savingInProgress could be 'final' •
       lib/features/home/widgets/rehearsal_card.dart:72:22 •
       prefer_final_fields
```

**Assessment:** These are linting suggestions only. The `_savingInProgress` field must remain mutable because it is updated in `setState`. No action required.

## Test Results

**Not run** — All tests (Tasks 8-10) require running the app with Flutter and are designated for manual QA:

- **Task 8:** Keyboard navigation testing (web + macOS with screen reader)
- **Task 9:** Multi-date persistence testing (all platforms, verify DB writes)
- **Task 10:** Error handling testing (airplane mode / network failure scenarios)

## Verification

**Manual steps performed during implementation:**

- ✅ Verified `_savingInProgress` state is set/cleared in all code paths (unselect + normal selection)
- ✅ Verified `didUpdateWidget` skips syncing for in-progress dates
- ✅ Verified error catch blocks log and show snackbars
- ✅ Verified loading spinner shows when `isLoading` is true
- ✅ Verified focus nodes initialized (4 nodes) and disposed correctly
- ✅ Verified keyboard handler logic matches multi-date vs single-date cases
- ✅ Verified all button call sites pass `focusNode`, `onKey`, and `isLoading` parameters
- ✅ Verified rehearsal_card.dart has identical pattern and received identical fixes

**Code review observations:**

- Both potential gig cards and potential rehearsal cards share the same optimistic update pattern
- Both had the same two bugs: no keyboard navigation + premature state sync during provider reload
- Implementation preserves existing visual design and behavior — changes are purely functional fixes
- No database schema changes, no routing changes, no auth changes (as per Architect plan)

## Deviations From Architect Plan

**None.** All changes strictly follow the Architect plan sections 10-11 (files to modify, files off-limits).

## Blockers Encountered

**None.** All implementation tasks completed without blockers.

## Ready For QA

**Yes** — with conditions:

**QA must verify:**

1. **Multi-date persistence (all platforms):** Create a 3-date potential gig, respond YES to all dates via dashboard, close/reopen app, verify all 3 responses persist in UI and DB
2. **Keyboard navigation (web + macOS):** Tab through buttons, activate with Enter/Space, verify responses save correctly, test with screen reader
3. **Error handling:** Trigger network failure (airplane mode), attempt response, verify error snackbar appears and button reverts
4. **Rapid multi-date responses:** Tap YES on 5 dates rapidly without waiting, verify all 5 responses persist
5. **Potential rehearsals:** Same tests as gigs, but for rehearsals (same fixes applied)

**Platform priority:**

- **High:** Web, macOS (keyboard nav), Android (persistence bug origin)
- **Medium:** iOS (general verification)

**Known limitations (documented in Architect plan Section 18 — Out of Scope):**

- No optimistic update for response summary counts in card footer
- No retry button in error snackbar (user must tap button again manually)
- No offline queue for failed saves
- No loading state for chevron navigation buttons
- No per-date error visual indicator (red border/icon)

## Implementation Notes

### Bug #1 Fix: Keyboard Navigation

- Added `List<FocusNode> _focusNodes` (4 nodes: left nav, NO, YES, right nav)
- Added `_handleKeyEvent` method to handle Enter/Space key presses
- Updated `_DateNavButton` and `_FullWidthAvailabilityButton` to accept optional `focusNode` and `onKey` parameters
- Widgets wrap inner `GestureDetector` with `Focus` when focus parameters are provided
- Single-date cards use focus nodes [1] and [2] only (NO and YES buttons)
- Multi-date cards use all 4 focus nodes for full tab navigation

### Bug #2 Fix: Multi-Date Persistence

- Added `Map<String?, bool> _savingInProgress` to track in-flight saves per date
- Set `_savingInProgress[dateId] = true` before calling `onRespondForDate`
- Clear `_savingInProgress[dateId] = false` in finally block after save completes
- Modified `didUpdateWidget` to skip syncing responses for dates with `_savingInProgress[dateId] == true`
- This preserves optimistic updates during provider reload (when provider enters loading state and returns empty map)

### Error Handling Enhancement

- Replaced `catch (_)` with `catch (e)` in both unselect and normal selection flows
- Added `debugPrint` to log errors for debugging
- Added `ScaffoldMessenger.of(context).showSnackBar` to show user-visible error messages
- Error message: "Could not save response — please try again."
- On error, optimistic update reverts to previous value from props

### Loading Indicator Enhancement

- Added `isLoading` parameter to `_FullWidthAvailabilityButton`
- Pass `_savingInProgress[_currentGigDateId] ?? false` from button call sites
- Show `CircularProgressIndicator` (16x16, white) in button center when loading
- Disable button interaction when `isSubmitting || isLoading`

### Code Consistency

- Both `potential_gig_card.dart` and `rehearsal_card.dart` received identical fixes
- Button widget patterns preserved: `_DateNavButton` (gig) vs `_RehearsalDateNavButton` (rehearsal)
- Same parameter names: `gigDateId` vs `rehearsalDateId`
- Same debug log prefixes: `[PotentialGigCard]` vs `[RehearsalCard]`

### Technical Details

- Focus nodes initialized in `initState`, disposed in `dispose`
- Keyboard handler checks `event is KeyDownEvent` to prevent double-firing on key up
- Focus wrapping is conditional: only applied when `focusNode != null && onKey != null`
- This preserves backward compatibility if widgets are used elsewhere without focus support
- Loading indicator uses `AlwaysStoppedAnimation<Color>(Colors.white)` for consistent white spinner on all button background colors

---

## QA Regression — Rehearsal Card Date Display

**Reported:** 2026-06-24  
**Platform:** iPhone (all mobile platforms affected)  
**Status:** FIXED

### Bug Description

On iPhone, tapping the chevron button on a potential rehearsal dashboard card advanced the internal state (`_currentDateIndex`) but the displayed date label remained stuck on the first date. The chevron disable logic worked correctly (right chevron correctly disabled on the last date), confirming that state was updating, but the UI never re-rendered the date text.

The potential gig card did NOT have this issue — chevron navigation worked correctly there.

### Root Cause

During the initial implementation, the Engineer applied keyboard navigation and multi-date persistence fixes to both `potential_gig_card.dart` and `rehearsal_card.dart`. However, the rehearsal card was missing a critical getter that the gig card had:

**Missing getter in rehearsal_card.dart:**

```dart
DateTime get _currentDate => _sortedDates[_currentDateIndex].$1;
```

This getter exists in [potential_gig_card.dart](../../lib/features/home/widgets/potential_gig_card.dart#L84) but was omitted from [rehearsal_card.dart](../../lib/features/home/widgets/rehearsal_card.dart).

**Consequence:**
The `_formatDateWithRecurrence()` method in rehearsal_card.dart always used `widget.rehearsal.date` (the primary/first date) instead of `_currentDate` (the currently displayed date based on `_currentDateIndex`). When the user tapped the chevron, `_currentDateIndex` incremented correctly and triggered a rebuild via `setState()`, but the date label always displayed the same value because `widget.rehearsal.date` never changes.

### Fix Applied

**File modified:** `lib/features/home/widgets/rehearsal_card.dart`

**Change 1:** Added missing `_currentDate` getter (line 94)

```dart
DateTime get _currentDate => _sortedDates[_currentDateIndex].$1;
```

**Change 2:** Updated `_formatDateWithRecurrence()` method to use `_currentDate` instead of `widget.rehearsal.date` (lines 710, 717)

```dart
// Before:
return '$frequencyText starting ${_formatFullDate(widget.rehearsal.date)}';
return _formatFullDate(widget.rehearsal.date);

// After:
return '$frequencyText starting ${_formatFullDate(_currentDate)}';
return _formatFullDate(_currentDate);
```

This aligns rehearsal_card.dart with the pattern already working correctly in potential_gig_card.dart.

### Verification

- ✅ `flutter analyze` — 0 errors (same 2 info-level linting suggestions as before)
- ✅ Code review — Confirmed rehearsal_card.dart now matches potential_gig_card.dart date display pattern
- ⏸️ Manual QA required — Tap chevron buttons on multi-date potential rehearsal, verify date label updates visually

### Impact

**Severity:** High (UI completely non-functional for multi-date rehearsal navigation)  
**Scope:** All platforms (iOS, Android, web, macOS)  
**User-facing:** Yes (users could not see which date they were responding to)

---

**Implementation complete. Ready for manual QA and post-deploy verification.**
