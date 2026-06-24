# ARCHITECT PLAN

## 1. Feature Slug

`bug/potential-event-multi-date-response`

---

## 2. Problem Summary

Two critical bugs affect multi-date potential event responses on dashboard cards:

**Bug #1: Tab navigation broken**
Users cannot use keyboard (Tab key) to navigate between YES/NO response buttons on potential event dashboard cards. Only mouse/touch input works. This is an accessibility issue that affects web and macOS users.

**Bug #2: Android multi-date response persistence failure**
When a user responds "yes" to multiple dates on a potential event via the dashboard card, only the first date's response persists to the database. Subsequent date responses are lost. Closing and reopening the app confirms the data loss — only the first response is visible.

---

## 3. Root Cause

### Bug #1: Tab Navigation (Confidence: HIGH)

**Location:** `lib/features/home/widgets/potential_gig_card.dart`  
**Lines:** 505-575 (`_FullWidthAvailabilityButton`) and 433-470 (`_DateNavButton`)

**Diagnosis:**
Both button widgets use `GestureDetector` for tap handling but include zero keyboard navigation support:

- No `Focus` widget wrapper
- No `FocusNode` management
- No `onKey` or `onKeyEvent` handlers
- No `autofocus` property

Flutter's `GestureDetector` only responds to pointer events (mouse, touch). Keyboard events require explicit Focus handling. The Edit Gig screen's availability buttons work correctly because they use `AvailabilityButton` from `event_editor_helpers.dart`, which may have Focus support (not verified, but the symptom only affects dashboard cards).

**Why it fails:**
Tab key presses have no registered listener. Focus never enters the button tree. Keyboard users cannot interact with the buttons at all.

---

### Bug #2: Multi-Date Persistence Failure (Confidence: HIGH)

**Location:** `lib/features/home/home_tab_content.dart` (lines 538-545) + `lib/features/home/widgets/potential_gig_card.dart` (lines 105-111, 113-161)

**Diagnosis:**
The dashboard uses this pattern to watch response data:

```dart
final Map<String, Map<String?, String?>> gigAllDateResponses =
    ref.watch(currentUserGigAllDateResponsesProvider).when(
          data: (r) => r,
          loading: () => {},  // ← RETURNS EMPTY MAP DURING LOAD
          error: (__, _) => {},
        );
```

When a user taps YES on date #1:

1. `PotentialGigCard._handleResponse('yes')` fires
2. Optimistic update: `_localResponses[date1Id] = 'yes'` (button turns green)
3. `onRespondForDate('yes', date1Id)` calls repository `upsertResponseForDate`
4. home_tab_content invalidates `currentUserGigAllDateResponsesProvider`
5. **Provider enters loading state** → `gigAllDateResponses` becomes `{}`
6. `PotentialGigCard.didUpdateWidget` detects prop change: `{date1Id: 'yes'}` → `{}`
7. **Resets `_localResponses` to `{}`** — wiping out the optimistic update (lines 105-111)
8. Button turns back to unselected state while save is in-flight
9. User navigates to date #2, taps YES
10. Same cycle repeats, but now TWO async saves are racing
11. Provider refetch completes, but timing issues or silent errors cause only date #1 to persist

**The core failure mode:**
The `.when(loading: () => {})` fallback returns an empty map, which triggers `didUpdateWidget` to reset optimistic state prematurely. The card has no mechanism to preserve in-flight response state during provider reloads.

**Compounding factor: Silent error swallowing**
Lines 146-157 in `potential_gig_card.dart`:

```dart
try {
  await widget.onRespondForDate!(response, gigDateId);
} catch (_) {  // ← SWALLOWS ALL ERRORS
  if (mounted) {
    setState(() {
      _localResponses = {..._localResponses, gigDateId: widget.perDateUserResponses?[gigDateId]};
    });
  }
}
```

If a save fails (network error, RLS policy, constraint violation), the user never sees an error message. The button silently reverts to its previous state. This makes debugging impossible for users and masks the true failure rate.

---

## 4. Reference Docs Consulted

No reference documentation exists for the gigs/potential events domain. The following directories were checked:

- `docs/reference/` — no gigs or events subdirectory
- `docs/features/` — relevant past work found:
  - `gig-availability-multi-date-save-fix/` (fixes edit form, not dashboard)
  - `rehearsal-potential-dates-ui-parity/` (mirrors gig pattern for rehearsals)
  - `potential-rehearsal-availability/` (initial implementation)

**Database schema source:** `docs/reference/architecture/database_schema.md`

---

## 5. Existing System Analysis

### Multi-Date Potential Gig Data Model

**Tables:**

- `gigs` — Primary date stored in `gigs.date`, `is_potential` flag
- `gig_dates` — Additional candidate dates (FK: `gig_id`, columns: `id`, `date`, `start_time`)
- `gig_responses` — Per-member RSVP (columns: `gig_id`, `user_id`, `response`, `gig_date_id` nullable)
  - `gig_date_id = NULL` → response for primary date
  - `gig_date_id = <uuid>` → response for a specific additional date
  - Unique constraint: `(gig_id, user_id, COALESCE(gig_date_id, '00000000-0000-0000-0000-000000000000'))`

**Repository:**

- `GigResponseRepository.upsertResponseForDate(gigId, gigDateId, userId, response)` — Inserts or updates a response for a specific date. Uses retry logic (3 attempts). Correctly handles null `gigDateId` for primary date.
- `GigResponseRepository.deleteResponseForDate(gigId, gigDateId, userId)` — Deletes a response for a specific date.
- `GigResponseRepository.fetchCurrentUserGigAllDateResponses(gigIds, userId)` — Returns `Map<gigId, Map<gigDateId?, response>>`.

**Dashboard Card Flow (Current):**

1. `home_tab_content.dart` renders `PotentialGigCard` for each potential gig
2. Passes `perDateUserResponses: gigAllDateResponses[gig.id]` from provider
3. Passes `onRespondForDate` callback that calls repository + invalidates providers
4. Card uses optimistic local state `_localResponses` initialized from `perDateUserResponses`
5. On tap, updates `_localResponses` immediately, calls `onRespondForDate`, reverts on error
6. `didUpdateWidget` syncs `_localResponses` from `perDateUserResponses` prop whenever it changes

**Why the Edit Gig screen does NOT have this bug:**

- Edit screen stores all per-date responses in local state `_perDateAvailability`
- Does NOT sync from provider during editing session
- Only writes to DB on "Save" button tap via `_savePerDateResponses()`
- No optimistic update / provider refetch race condition

---

## 6. Proposed Solution

### Bug #1 Fix: Add Keyboard Navigation Support

**Change:** Wrap interactive widgets with `Focus` and add keyboard handlers.

**Affected widgets:**

- `_FullWidthAvailabilityButton` (YES/NO buttons)
- `_DateNavButton` (left/right chevrons)

**Implementation:**

1. Add `FocusNode` parameters to both widgets (managed by parent `_PotentialGigCardState`)
2. Wrap button `GestureDetector` children with `Focus` widget
3. Add `onKey` handler to detect Enter/Space for activation, Tab for navigation
4. Add `autofocus` property to first focusable element (left chevron or NO button if single-date)
5. Use `FocusTraversalGroup` to control tab order: left nav → NO → YES → right nav

**Tab order (multi-date):** ← button → NO button → YES button → → button → (cycles)
**Tab order (single-date):** NO button → YES button → (cycles)

---

### Bug #2 Fix: Preserve Optimistic State During Provider Reload

**Change:** Prevent `didUpdateWidget` from wiping out in-flight response state.

**Implementation Strategy:**
Add a `Map<String?, bool> _savingInProgress` to track which dates have saves in-flight. Do not sync that date's response from props while its save is in-progress.

**Modified flow:**

1. User taps YES on date #1
2. Set `_savingInProgress[date1Id] = true`
3. Optimistic update: `_localResponses[date1Id] = 'yes'`
4. Call `onRespondForDate('yes', date1Id)` (async)
5. Provider invalidates, enters loading state → `perDateUserResponses` becomes `{}`
6. `didUpdateWidget` fires, but **skips syncing `date1Id`** because `_savingInProgress[date1Id] == true`
7. Optimistic update preserved! Button stays green.
8. `onRespondForDate` completes (success or error)
9. Set `_savingInProgress[date1Id] = false`
10. If error, revert `_localResponses[date1Id]` and **show error snackbar**
11. If success, leave `_localResponses[date1Id] = 'yes'` until next prop sync

**Error handling upgrade:**

- Replace `catch (_)` with `catch (e)`
- Log the error: `debugPrint('[PotentialGigCard] Save failed: $e')`
- Show user-visible error snackbar via `ScaffoldMessenger`
- Provide retry action (optional enhancement, not blocking)

---

### Additional Issues Fixed

**Issue #3: No loading indicator**

- **Change:** Show a small spinner on the button during save
- **Implementation:** Pass `_savingInProgress[_currentGigDateId] ?? false` to button widget, render spinner overlay if true

**Issue #4: Silent error masking**

- **Change:** Remove error swallowing, add user-visible error messages
- **Implementation:** Show snackbar with actionable error message

---

## 7. Database Impact

**Assessment:** Not applicable.

- No schema changes required
- No migrations needed
- RLS policies on `gig_responses` already support multi-date writes (verified by working Edit Gig screen)
- No RPC changes
- Unique constraint `gig_responses_gig_user_date_unique` correctly handles per-date responses

**Tables affected by reads/writes:** `gig_responses` (no structural changes)

---

## 8. Flutter Architecture Changes

### State Management

**File:** `lib/features/home/widgets/potential_gig_card.dart`

**New state fields:**

- `Map<String?, bool> _savingInProgress` — Tracks in-flight saves per date (gigDateId → bool)
- `List<FocusNode> _focusNodes` — Focus management for keyboard navigation (4 nodes: left nav, NO, YES, right nav)

**Modified methods:**

- `didUpdateWidget` — Add guard: skip syncing responses for dates with `_savingInProgress[dateId] == true`
- `_handleResponse` — Set/clear `_savingInProgress`, show error snackbar on failure
- `initState` — Initialize `_focusNodes`
- `dispose` — Dispose `_focusNodes`

**New widgets:**

- `_FocusableButton` (or inline Focus wrapper) — Wraps `GestureDetector` with `Focus` + `onKey`

---

### Provider Changes

**File:** `lib/features/home/home_tab_content.dart`

**No changes to provider structure.** The `.when(loading: () => {})` pattern is acceptable once the card correctly handles empty prop during saves.

**Alternative considered and rejected:**
Change `.when(loading: () => {})` to `.when(loading: () => gigAllDateResponses)` (preserve previous data). **Rejected** because:

1. Riverpod `AsyncValue` doesn't have `keepPreviousData` — would require manual state caching
2. Increases complexity for all consumers of this provider
3. Localized card fix is simpler and safer

---

## 9. Files to Create

None.

---

## 10. Files to Modify

| File                                                | What Changes                                                                                                                                                                                                                                                           |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/home/widgets/potential_gig_card.dart` | Add `_savingInProgress` map; add `_focusNodes` list; modify `didUpdateWidget` to skip syncing in-progress saves; modify `_handleResponse` to manage save state + show errors; wrap buttons with `Focus` + `onKey`; add loading spinner to buttons; dispose focus nodes |
| `lib/features/home/widgets/rehearsal_card.dart`     | **Audit only** — Same pattern exists for potential rehearsals. Apply identical fixes if confirmed affected (likely yes, but verify during implementation)                                                                                                              |

---

## 11. Files Off-Limits

| File                                                   | Reason                                                                             |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| `lib/main.dart`                                        | Initialization order must not change                                               |
| `lib/features/gigs/gig_response_repository.dart`       | Repository logic is correct; no changes needed                                     |
| `lib/features/home/home_tab_content.dart`              | Provider consumption pattern is acceptable once card handles empty props correctly |
| `lib/features/events/widgets/event_editor_drawer.dart` | Edit form flow works correctly; do not touch                                       |
| `lib/features/events/widgets/gig_form_fields.dart`     | Edit form availability buttons work correctly; do not touch                        |
| `supabase/migrations/*`                                | No schema changes required                                                         |

---

## 12. System Impact Map

| System                                 | Impact                   | Notes                                                                            |
| -------------------------------------- | ------------------------ | -------------------------------------------------------------------------------- |
| Gigs                                   | **Affected**             | Potential gig dashboard card response handling fixed                             |
| Rehearsals                             | **Potentially Affected** | Same `PotentialRehearsalCard` pattern likely has identical bugs — audit required |
| Setlists / Catalog                     | Unaffected               | No interaction with multi-date responses                                         |
| Members / RBAC                         | Unaffected               | No permission changes                                                            |
| Auth / Session                         | Unaffected               | No auth flow changes                                                             |
| Routing                                | Unaffected               | No routing changes                                                               |
| Notifications                          | Unaffected               | Response submission triggers are unchanged                                       |
| Platform (iOS / Android / Web / macOS) | **Affected**             | Keyboard nav benefits web+macOS; persistence fix benefits all platforms          |

---

## 13. Regression Risk

**Level:** MEDIUM

**Rationale:**

- **Isolated change:** Only touches dashboard card widget, not repository or provider logic
- **Rehearsal mirror risk:** If `rehearsal_card.dart` has the same bugs but is NOT fixed, creates inconsistency
- **Focus management risk:** Adding keyboard navigation could introduce focus trap or unexpected tab order if not tested thoroughly
- **State timing risk:** `_savingInProgress` logic must correctly cover all edge cases (rapid taps, network errors, app backgrounding)
- **No auth/routing/DB changes:** Core systems untouched

**Mitigation:**

- Audit `rehearsal_card.dart` before closing ticket — apply same fixes if affected
- Test keyboard navigation on web and macOS with screen reader
- Test rapid multi-date taps to verify no race conditions
- Test airplane mode to verify error handling

---

## 14. Engineer Task Breakdown

Execute in order. Each task is atomic and verifiable.

### Task 1: Add `_savingInProgress` state management

- [ ] Add `Map<String?, bool> _savingInProgress = {};` field to `_PotentialGigCardState`
- [ ] In `_handleResponse`, set `_savingInProgress[gigDateId] = true` before calling `onRespondForDate`
- [ ] In `_handleResponse` finally block, set `_savingInProgress[gigDateId] = false`
- [ ] Verify: Saving state is tracked per date

### Task 2: Guard `didUpdateWidget` against in-progress saves

- [ ] Modify `didUpdateWidget` to iterate `widget.perDateUserResponses` entries
- [ ] For each entry, check `if (_savingInProgress[dateId] == true)` → skip syncing that entry
- [ ] Only sync dates NOT currently saving
- [ ] Verify: Optimistic updates preserved during provider reload

### Task 3: Add user-visible error handling

- [ ] Replace `catch (_)` with `catch (e)` in `_handleResponse`
- [ ] Log error: `debugPrint('[PotentialGigCard] Response save failed for date $gigDateId: $e')`
- [ ] Show snackbar: `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save response — please try again.')))`
- [ ] On error, revert `_localResponses[gigDateId]` to `widget.perDateUserResponses?[gigDateId]`
- [ ] Verify: Errors visible to user, optimistic update reverts

### Task 4: Add saving indicator to buttons

- [ ] Add `bool isLoading` parameter to `_FullWidthAvailabilityButton`
- [ ] Pass `_savingInProgress[_currentGigDateId] ?? false` when creating button
- [ ] If `isLoading` or `isSubmitting`, show spinner overlay (use `CircularProgressIndicator` 16x16 in button center)
- [ ] Disable button interaction during loading (`onTap: isSubmitting || isLoading ? null : onTap`)
- [ ] Verify: Spinner visible during save, button disabled

### Task 5: Add keyboard navigation infrastructure

- [ ] Add `List<FocusNode> _focusNodes = [];` field to `_PotentialGigCardState`
- [ ] In `initState`, initialize 4 focus nodes: `_focusNodes = List.generate(4, (_) => FocusNode());`
- [ ] In `dispose`, dispose all focus nodes: `for (var node in _focusNodes) { node.dispose(); }`
- [ ] Assign nodes: `[0] = left nav, [1] = NO button, [2] = YES button, [3] = right nav`
- [ ] Verify: Focus nodes created and disposed correctly

### Task 6: Wrap buttons with Focus + keyboard handlers

- [ ] Wrap `_DateNavButton` (left) `GestureDetector` child with `Focus(focusNode: _focusNodes[0], onKey: _handleKeyEvent, child: ...)`
- [ ] Wrap `_FullWidthAvailabilityButton` (NO) `GestureDetector` child with `Focus(focusNode: _focusNodes[1], onKey: _handleKeyEvent, child: ...)`
- [ ] Wrap `_FullWidthAvailabilityButton` (YES) `GestureDetector` child with `Focus(focusNode: _focusNodes[2], onKey: _handleKeyEvent, child: ...)`
- [ ] Wrap `_DateNavButton` (right) `GestureDetector` child with `Focus(focusNode: _focusNodes[3], onKey: _handleKeyEvent, child: ...)`
- [ ] Implement `KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event)`:
  - If Enter or Space pressed, call corresponding button action
  - Return `KeyEventResult.handled` if handled, `KeyEventResult.ignored` otherwise
- [ ] Verify: Buttons gain visible focus indicator, Enter/Space activates

### Task 7: Audit `rehearsal_card.dart`

- [ ] Read `lib/features/home/widgets/rehearsal_card.dart` fully
- [ ] Check if it uses same optimistic update pattern as `potential_gig_card.dart`
- [ ] Check if buttons use `GestureDetector` without Focus
- [ ] If affected, apply Tasks 1-6 with rehearsal-specific naming (`_savingInProgress`, `rehearsalDateId`, etc.)
- [ ] Verify: Consistency between gig and rehearsal cards

### Task 8: Test keyboard navigation

- [ ] Run on web (`flutter run -d chrome`)
- [ ] Open dashboard with multi-date potential gig
- [ ] Press Tab repeatedly → verify focus moves: left nav → NO → YES → right nav → (cycles)
- [ ] Press Enter on NO button → verify response saves
- [ ] Press Space on YES button → verify response saves
- [ ] Press Enter on right nav → verify date advances
- [ ] Verify: Full keyboard control

### Task 9: Test multi-date persistence

- [ ] Run on any platform
- [ ] Create a 3-date potential gig
- [ ] On dashboard card, tap YES on date 1 → wait for save → verify button stays green
- [ ] Tap right nav to date 2 → tap YES → wait → verify button stays green
- [ ] Tap right nav to date 3 → tap YES → wait → verify button stays green
- [ ] Close app, reopen
- [ ] Verify: All 3 dates show YES response in DB and on card
- [ ] Repeat with rapid taps (no waiting) → verify all saves complete

### Task 10: Test error handling

- [ ] Enable airplane mode
- [ ] Tap YES on a date → verify snackbar appears with error message
- [ ] Verify button reverts to unselected
- [ ] Disable airplane mode, tap YES again → verify save succeeds
- [ ] Verify: Graceful error recovery

---

## 15. Verification Plan

### Tier 1 — Pre-Deployment (Flutter-only, no DB changes)

These tests verify the Flutter client logic without requiring database migrations.

**PRE-DEPLOY TEST 1: Optimistic state preservation**

```
1. Instrument code: Add debugPrint in didUpdateWidget to log when sync is skipped
2. Run app with potential gig
3. Tap YES on date 1 → immediately observe logs
4. Expected: "Skipping sync for date X because save in progress"
5. Wait for save → observe logs
6. Expected: "Syncing date X now that save completed"
```

**PRE-DEPLOY TEST 2: Keyboard navigation**

```
1. Run flutter run -d chrome
2. Navigate to dashboard with multi-date gig
3. Press Tab key repeatedly
4. Expected: Focus visible on left nav → NO → YES → right nav (cycling)
5. Focus NO button, press Enter
6. Expected: Response submitted, same as clicking with mouse
```

**PRE-DEPLOY TEST 3: Error snackbar display**

```
1. Modify code temporarily: Throw exception in onRespondForDate callback
2. Run app, tap YES on any date
3. Expected: Snackbar appears with error message
4. Expected: Button reverts to unselected state
5. Revert code change
```

---

### Tier 2 — Post-Deployment (Full Integration)

These tests verify end-to-end behavior with real database writes.

**POST-DEPLOY TEST 1: Multi-date persistence**

```sql
-- Setup: Create a 3-date potential gig
INSERT INTO gigs (id, band_id, name, date, start_time, end_time, location, is_potential)
VALUES (gen_random_uuid(), '<test_band_id>', 'Test Gig', '2026-07-01', '8:00 PM', '11:00 PM', 'Venue', true);

-- Create additional dates
INSERT INTO gig_dates (gig_id, date) VALUES ('<gig_id_from_above>', '2026-07-02');
INSERT INTO gig_dates (gig_id, date) VALUES ('<gig_id_from_above>', '2026-07-03');

-- Test: User responds YES to all 3 dates via dashboard
-- (Manual app interaction)

-- Verify: All 3 responses saved
SELECT gig_id, gig_date_id, response FROM gig_responses WHERE gig_id = '<gig_id>' AND user_id = '<test_user_id>';
-- Expected rows:
-- (gig_id, NULL, 'yes')           -- primary date
-- (gig_id, date2_id, 'yes')       -- date 2
-- (gig_id, date3_id, 'yes')       -- date 3

-- Cleanup
DELETE FROM gig_responses WHERE gig_id = '<gig_id>';
DELETE FROM gig_dates WHERE gig_id = '<gig_id>';
DELETE FROM gigs WHERE id = '<gig_id>';
```

**POST-DEPLOY TEST 2: Rapid-fire multi-date responses**

```
1. Open dashboard with 5-date potential gig
2. Tap YES on date 1 → IMMEDIATELY navigate to date 2 → tap YES → date 3 → tap YES (rapid, no waiting)
3. Continue for all 5 dates
4. Wait 5 seconds for all saves to settle
5. Close app, reopen
6. Query DB: SELECT COUNT(*) FROM gig_responses WHERE gig_id = '<gig_id>' AND user_id = '<user_id>';
7. Expected: 5 responses (all dates saved)
```

**POST-DEPLOY TEST 3: Keyboard navigation accessibility**

```
1. Enable screen reader (VoiceOver on macOS, NVDA on Windows)
2. Run app in browser
3. Navigate to dashboard with Tab key
4. Verify: Screen reader announces each button ("NO button", "YES button", etc.)
5. Activate YES button with Enter key
6. Verify: Response saved, screen reader announces success
```

**POST-DEPLOY TEST 4: Error recovery**

```
1. Simulate RLS policy block (temporarily revoke INSERT on gig_responses for test user)
2. Tap YES on date 1
3. Expected: Error snackbar appears
4. Restore RLS policy
5. Tap YES again
6. Expected: Save succeeds, button stays green
```

---

## 16. QA Regression Areas

QA must specifically test:

### Primary Test Cases (Blocking)

1. **Multi-date response persistence (all platforms):**
   - Respond YES to all dates on a 3-date potential gig
   - Close app, reopen
   - Verify all responses visible in UI and DB

2. **Keyboard navigation (web + macOS):**
   - Tab through all buttons on potential gig card
   - Activate buttons with Enter/Space keys
   - Verify responses save correctly
   - Test with screen reader enabled

3. **Rapid multi-date responses:**
   - Tap YES on 5 dates rapidly without waiting for saves
   - Verify all 5 responses persist

4. **Error handling:**
   - Trigger network error (airplane mode or Supabase outage)
   - Attempt to respond
   - Verify error snackbar appears
   - Restore network, retry
   - Verify response saves

### Secondary Test Cases (Non-blocking but important)

5. **Potential rehearsals multi-date** (if `rehearsal_card.dart` is modified):
   - Same tests as gigs, but for rehearsals

6. **Single-date potential gigs:**
   - Verify keyboard nav works (NO → YES, no chevrons)
   - Verify response saves

7. **Response deletion:**
   - Respond YES, then tap YES again (unselect)
   - Verify response deleted from DB

8. **Provider refetch edge case:**
   - Respond YES on date 1 while another band member simultaneously responds
   - Verify both responses visible after refetch

---

## 17. Rollout / Migration Strategy

**Not applicable.** No database changes, no backend deployment, no feature flag required.

**Rollout plan:**

1. Merge to `main` after QA APPROVED
2. Deploy web via `./tools/deploy_web.sh`
3. Post-deploy smoke test: Verify keyboard nav + multi-date save on production
4. Monitor Sentry/logs for 24 hours for client-side errors
5. If issues detected, rollback via `git revert` + redeploy

**No user data migration needed.**

---

## 18. Out of Scope

Explicitly NOT included in this fix:

1. **Refactoring PotentialGigCard** — File is 600 lines; changes are localized, no cleanup needed
2. **Unified button component** — `_FullWidthAvailabilityButton` and Edit Gig's `AvailabilityButton` have different visual styles; unifying them is a separate design task
3. **Optimistic update for response summary counts** — Dashboard shows "3 Yes, 2 No, 1 Not Responded" footer; this count does not update optimistically (only after provider refetch). Fixing this requires additional state management and is low priority.
4. **Retry button in error snackbar** — Error snackbar shows message but no "Retry" action. User must tap button again manually. Enhancement for future work.
5. **Loading state for chevron navigation** — Left/right nav buttons do not show loading indicator while fetching next date's response. Current behavior is acceptable (instant local state update).
6. **Per-date error state** — If date 2 fails to save, date 2 button reverts but no visual indicator marks it as "error" (just unselected). Future enhancement: red border or error icon.
7. **Bulk response submission** — No "Respond YES to all dates" quick action. Future feature.
8. **Notification on response failure** — If save fails while app is backgrounded, no push notification alerts user. Out of scope for this fix.
9. **Offline queue** — Responses do not queue for retry when offline. Future enhancement for offline-first architecture.
10. **Testing infrastructure** — No unit/widget tests created (project has minimal test coverage). Tests should be added in a dedicated testing initiative, not mixed with bug fixes.

---

## End of Plan
