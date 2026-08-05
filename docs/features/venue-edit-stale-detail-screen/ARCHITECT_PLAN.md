# Architect Plan — Venue Edit Stale Detail Screen Fix

## Feature Slug

`bug/venue-edit-stale-detail-screen`

---

## Problem Summary

When a user edits a venue from the Contacts screen via the venue detail screen, the changes appear not to save. The actual behavior: the write to Supabase succeeds, but the `VenueDetailScreen` the user returns to still displays pre-edit data. Re-opening the edit form from that screen pre-fills with the stale data, creating the appearance that the save failed.

**User flow exhibiting the bug:**

1. Contacts tab → tap venue card → `VenueDetailScreen` opens
2. Tap "Edit" → `VenueFormScreen` opens
3. Change address/city → tap Save
4. Return to `VenueDetailScreen` — **still shows old data**
5. Tap "Edit" again — **form pre-fills with old data**

This is a stale-UI issue, not a persistence failure. The database write succeeds, but the UI does not refresh.

---

## Root Cause

**Confidence Level:** `HIGH` (confirmed by direct code inspection)

**Primary Failure:**
`VenueDetailScreen` (lines 60–66) pushes `VenueFormScreen` without awaiting the result and without any post-navigation refresh logic:

```dart
TextButton(
  onPressed: () {
    Navigator.push(
      context,
      fadeSlideRoute(page: VenueFormScreen(venue: venue)),
    );
  },
  // ...
)
```

`VenueDetailScreen` is a `StatelessWidget` with an immutable `venue` field passed at construction time. Even if it awaited the navigation, it has no state to update and no mechanism to fetch fresh data.

**Contrast with correct pattern:**
`VenuesView._openVenueForm` (lines 62–75) already implements the correct pattern: it awaits the form result and calls `ref.read(venuesProvider.notifier).refresh(bandId)` when the result is `true`.

**Why the bug manifests:**

1. User edits venue → `VenueFormScreen._save()` calls `_repository.updateVenue()` → Supabase write succeeds
2. `VenueFormScreen` pops with `true` (line ~230 in `venue_form_screen.dart`)
3. `VenueDetailScreen` does not await this result, so it never learns that an edit occurred
4. User returns to the same `VenueDetailScreen` instance holding the original, now-stale `venue` object
5. Tapping "Edit" again passes the stale object to `VenueFormScreen`, which pre-fills from it

**Secondary observation (not a root cause):**
`VenueFormScreen` (line ~31) instantiates its own `VenuesRepository()` instance, separate from the one backing `venuesProvider`. Cache invalidation in one instance doesn't affect the other. However, this is irrelevant because `VenueDetailScreen` doesn't fetch from a repository—it displays an immutable object passed to it.

**Regression origin:**
Commit `216a2a2` ("feat(contacts): add A-Z sectioned venue list... and detail view #81") introduced `VenueDetailScreen` as an intermediary screen between the list and the edit form, but did not carry over the refresh-on-return logic that `VenuesView` already had for its own direct edit flow.

**Unrelated to prior PRs:**
This bug is independent of the two recently merged gig-venue features (PRs #122, #123). Those touch different files (`event_editor_drawer.dart`) and different code paths (gig venue linking). Current line numbers verified against `main` at commit `5d821ae`.

---

## Reference Docs Consulted

None. The `docs/reference/` directory contains no reference documentation for the Contacts/Venues domain. All analysis is based on direct code inspection of the feature implementation files.

---

## Existing System Analysis

### Current Behavior

**Navigation flow:**

```
VenuesView (list)
  ↓ tap venue card
VenueDetailScreen (read-only detail, immutable venue field)
  ↓ tap "Edit" button (no await, no refresh handling)
VenueFormScreen (edit mode)
  ↓ save → calls _repository.updateVenue() → Supabase write succeeds
  ↓ pops with `true`
VenueDetailScreen ← user returns here, still holding stale venue object
```

**Data flow on save:**

1. `VenueFormScreen._save()` (line ~145) constructs `venueData` map from text controllers
2. Calls `await _repository.updateVenue(id: widget.venue!.id, data: venueData)` (line ~165)
3. `VenuesRepository.updateVenue()` (line ~126) performs:
   ```dart
   await supabase.from('venues').update(data).eq('id', id).select('*, venue_contacts(*)').single()
   ```
4. Invalidates cache: `_invalidateCache(venue.bandId)` (line ~133)
5. Returns updated `Venue` object (not used by caller)
6. `VenueFormScreen` pops: `Navigator.of(context).pop(true)` (line ~230)
7. `VenueDetailScreen` never receives this `true` because it didn't await

**Correct pattern (for comparison):**
`VenuesView._openVenueForm` (line ~62):

```dart
Future<void> _openVenueForm({required BuildContext context, venue}) async {
  final result = await Navigator.of(context).push<bool>(
    fadeSlideRoute(page: VenueFormScreen(venue: venue)),
  );
  if (result == true) {
    final bandId = ref.read(activeBandProvider).activeBandId;
    if (bandId != null) {
      ref.read(venuesProvider.notifier).refresh(bandId);
    }
  }
}
```

This pattern:

- Awaits the form
- Checks for `true` result (signals successful save)
- Refreshes the provider's venue list

`VenueDetailScreen` has none of this.

---

## Proposed Solution

**Design Goal:**
Make `VenueDetailScreen`'s edit flow behave like `VenuesView`'s edit flow: await the form result, signal refresh to the parent when an edit succeeds.

**Approach:**

1. **VenueDetailScreen**: Convert the Edit button's `onPressed` to an async function that awaits the `VenueFormScreen` result. If the result is `true` (successful save), pop the detail screen back to `VenuesView`, passing `true` to signal that a refresh is needed.
2. **VenuesView.\_openVenueDetail**: Await the `VenueDetailScreen` result. If it returns `true`, refresh the venues list via `ref.read(venuesProvider.notifier).refresh(bandId)`.

**Why this is the minimal fix:**

- No new abstractions required
- No state management changes (VenueDetailScreen remains StatelessWidget)
- Reuses existing refresh pattern already proven in `_openVenueForm`
- Only two files modified, total change surface ~10 lines

**UX consequence:**
After a successful edit, the user returns to the venues list instead of staying on the detail screen. This is acceptable and consistent:

- The list view immediately reflects the updated venue name/city (visible in the card)
- If the user wants to see full details again, they tap the card
- This matches the flow when creating a new venue (form → list, not form → detail)

**Alternative approaches considered and rejected:**

1. **Convert VenueDetailScreen to ConsumerWidget, fetch venue from provider by ID** — Would work, but adds complexity and misuses the provider pattern (providers are for collections/shared state, not individual detail views).

2. **Convert VenueDetailScreen to StatefulWidget, re-fetch venue after edit** — Would work, but requires a repository call and makes the widget stateful unnecessarily. Also doesn't solve the cache issue (VenueDetailScreen would need its own repository instance or access to the provider).

3. **Pass a refresh callback from VenuesView to VenueDetailScreen** — Violates unidirectional data flow (children should not receive mutation callbacks from parents unless they're leaf actions). Also tightly couples the screens.

The chosen approach (await + pop on success) is the simplest and most maintainable.

---

## Database Impact

**Not applicable.**

This is purely a client-side navigation and state refresh issue. No migrations, RLS policies, RPC functions, triggers, or schema changes are involved.

The Supabase `UPDATE` operation already works correctly (`venues_repository.dart` line ~126). The bug is that the UI doesn't reflect the result.

---

## Flutter Architecture Changes

### State Management

**Unaffected.** No changes to `VenuesState`, `VenuesNotifier`, or `venuesProvider`. The existing `refresh()` method is sufficient and already used by `_openVenueForm`.

### Widgets

**Modified:**

- `VenueDetailScreen`: Edit button's `onPressed` becomes `async`, awaits form result, pops with `true` on success
- `VenuesView`: `_openVenueDetail` method awaits detail screen result, refreshes on `true`

**Unchanged:**

- `VenueFormScreen` — already pops with `true` on successful save; no changes needed
- `VenueCard` — no changes needed
- All other contacts/venues widgets

### Repositories

**Unaffected.** `VenuesRepository.updateVenue()` already works correctly and invalidates cache. No changes needed.

---

## Files to Create

**None.**

---

## Files to Modify

| File                                                     | What changes                                                                                                                                                                                                                                   |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/contacts/widgets/venue_detail_screen.dart` | Change Edit button's `onPressed` from bare `Navigator.push(...)` to an async method that awaits the `VenueFormScreen` result. If result is `true` and `context.mounted` is true, pop the detail screen with `Navigator.of(context).pop(true)`. |
| `lib/features/contacts/widgets/venues_view.dart`         | Update `_openVenueDetail` method to await the `VenueDetailScreen` result (typed as `bool?`). If result is `true`, call `ref.read(venuesProvider.notifier).refresh(bandId)` (same pattern as `_openVenueForm`).                                 |

---

## Files Off-Limits

| File                                                   | Reason                                                                 |
| ------------------------------------------------------ | ---------------------------------------------------------------------- |
| `lib/features/contacts/widgets/venue_form_screen.dart` | Already pops with `true` on success; no changes needed.                |
| `lib/features/contacts/venues_repository.dart`         | Update logic already correct; no changes needed.                       |
| `lib/features/contacts/venues_controller.dart`         | State management and refresh logic already correct; no changes needed. |
| `lib/features/contacts/models/venue.dart`              | No schema changes required.                                            |
| `lib/features/contacts/widgets/venue_card.dart`        | Navigation from card to detail screen is correct; no changes needed.   |
| `lib/main.dart`                                        | No initialization changes.                                             |
| Any test files                                         | No existing tests for VenueDetailScreen.                               |
| Any database files (`supabase/migrations/`, `sql/`)    | No database changes.                                                   |

---

## System Impact Map

| System                                 | Impact                                                                    |
| -------------------------------------- | ------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                |
| Rehearsals                             | unaffected                                                                |
| Setlists / Catalog                     | unaffected                                                                |
| Members / RBAC                         | unaffected                                                                |
| Auth / Session                         | unaffected                                                                |
| Routing                                | **affected** — VenueDetailScreen now pops early on successful edit        |
| Notifications                          | unaffected                                                                |
| Contacts / Venues                      | **affected** — navigation and refresh behavior for venue detail→edit flow |
| Platform (iOS / Android / Web / macOS) | unaffected — shared Flutter code, no platform-specific branches           |

---

## Regression Risk

**Level:** `LOW`

**Rationale:**

1. **Minimal change surface:** Only two files modified, ~10 lines total change
2. **Well-established pattern:** Copying the existing, proven `_openVenueForm` pattern
3. **No state management changes:** No new providers, no changes to existing state shape
4. **No database changes:** No migrations, no RLS, no RPC signature changes
5. **No cross-feature impact:** Gigs, rehearsals, setlists, auth, members all untouched
6. **Single navigation path affected:** Only the Contacts tab → venue card → detail → edit flow is modified
7. **No async lifecycle risk:** Uses `context.mounted` guard before popping (standard Flutter pattern)

**Potential failure modes (all low probability):**

- **Edit button doesn't pop after save:** Would be caught immediately in manual testing (user stays on detail screen with stale data, same as current bug)
- **VenuesView doesn't refresh:** Would be caught immediately in manual testing (list doesn't show updated venue)
- **Pop happens before form is dismissed:** Not possible — `await Navigator.push(...)` waits for the pushed route to complete
- **`context.mounted` check fails incorrectly:** Standard Flutter pattern, low risk

**Mitigation:**
Manual testing of the specific flow (edit venue from detail screen, verify return to list, verify list shows updated data) is sufficient. No complex state interactions, no edge cases.

---

## Engineer Task Breakdown

Execute in strict order. Do not skip. Do not reorder.

### Task 1: Modify VenueDetailScreen Edit Button

**File:** `lib/features/contacts/widgets/venue_detail_screen.dart`

**Current code (lines ~60–70):**

```dart
TextButton(
  onPressed: () {
    Navigator.push(
      context,
      fadeSlideRoute(page: VenueFormScreen(venue: venue)),
    );
  },
  child: const Text(
    'Edit',
    style: TextStyle(
      color: AppColors.primary,
      fontSize: AppFontSizes.body,
      fontWeight: FontWeight.w600,
    ),
  ),
),
```

**Change to:**

```dart
TextButton(
  onPressed: () async {
    final edited = await Navigator.push<bool>(
      context,
      fadeSlideRoute(page: VenueFormScreen(venue: venue)),
    );
    if (edited == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  },
  child: const Text(
    'Edit',
    style: TextStyle(
      color: AppColors.primary,
      fontSize: AppFontSizes.body,
      fontWeight: FontWeight.w600,
    ),
  ),
),
```

**Explanation:**

- Make `onPressed` async
- Await the `VenueFormScreen` result (typed as `bool?`)
- If result is `true` (successful save) AND the context is still mounted, pop the detail screen back to VenuesView with `true` to signal refresh is needed
- The `context.mounted` guard prevents calling `pop()` after the widget has been disposed (standard Flutter async safety pattern for StatelessWidget)

---

### Task 2: Update VenuesView.\_openVenueDetail to Handle Refresh Signal

**File:** `lib/features/contacts/widgets/venues_view.dart`

**Current code (lines ~77–84):**

```dart
Future<void> _openVenueDetail({
  required BuildContext context,
  required Venue venue,
}) async {
  await Navigator.of(context).push(
    fadeSlideRoute(page: VenueDetailScreen(venue: venue)),
  );
}
```

**Change to:**

```dart
Future<void> _openVenueDetail({
  required BuildContext context,
  required Venue venue,
}) async {
  final needsRefresh = await Navigator.of(context).push<bool>(
    fadeSlideRoute(page: VenueDetailScreen(venue: venue)),
  );
  if (needsRefresh == true) {
    final bandId = ref.read(activeBandProvider).activeBandId;
    if (bandId != null) {
      ref.read(venuesProvider.notifier).refresh(bandId);
    }
  }
}
```

**Explanation:**

- Capture the result of `Navigator.push<bool>(...)` as `needsRefresh`
- If `needsRefresh` is `true` (detail screen popped early due to successful edit), refresh the venues list
- Uses exact same refresh logic as `_openVenueForm` (lines 68–74)
- Refresh call fetches updated venue data from Supabase and rebuilds the list

---

### Task 3: Run Flutter Analyze

**Command:**

```bash
flutter analyze
```

**Expected result:** 0 errors, 0 warnings

**If errors occur:** Stop. Report to Manager. Do not proceed to Task 4.

---

### Task 4: Manual Verification (Engineer Self-Test)

**Platform:** macOS (per feature input)

**Test case:**

1. Run app: `./run.sh macos`
2. Navigate to Contacts tab
3. Tap a venue card → verify `VenueDetailScreen` opens with correct data
4. Tap "Edit" → verify `VenueFormScreen` opens with pre-filled data
5. Change the address field (e.g., change street number)
6. Change the city field (e.g., change city name)
7. Tap Save
8. **Verify:** App returns to VenuesView (the list), NOT to VenueDetailScreen
9. **Verify:** The venue card in the list shows the new city name
10. Tap the same venue card again → `VenueDetailScreen` opens
11. **Verify:** Address and city fields show the NEW values (not the old ones)
12. Tap "Edit" again → `VenueFormScreen` opens
13. **Verify:** Address and city fields are pre-filled with the NEW values (not the old ones)

**Expected result:** All verifications pass.

**If any verification fails:** Stop. Debug. Do not commit.

---

### Task 5: Generate Git Diff and ENGINEER_REPORT.md

**Generate diff:**

```bash
git diff > venue-edit-stale-detail-screen.diff
```

**Create report:**
`docs/features/venue-edit-stale-detail-screen/ENGINEER_REPORT.md`

Required sections:

- Task completion checklist (all 5 tasks)
- Files modified (2 files)
- `flutter analyze` result (paste output)
- Manual verification results (12-step test case, all pass/fail)
- Git diff summary (line counts, change description)
- Explanation of how the fix resolves the root cause

---

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable.** No database changes.

---

### Tier 2 — Post-deployment

**Not applicable.** No database changes. This is a client-only fix.

---

### Manual Testing (QA Agent)

**Platform coverage:** macOS (confirmed affected), Web (verify fix applies), iOS (verify fix applies if testable)

**Primary test case (Contacts → Detail → Edit → verify refresh):**

1. Launch app on macOS
2. Navigate to Contacts tab
3. Select a venue that has an address and city populated
4. Note the current address and city values
5. Tap the venue card → `VenueDetailScreen` opens
6. Verify the detail screen shows the correct current address and city
7. Tap "Edit" → `VenueFormScreen` opens
8. Verify the form is pre-filled with the current address and city
9. Change the address (e.g., "123 Main St" → "456 Oak Ave")
10. Change the city (e.g., "Portland" → "Seattle")
11. Tap Save
12. **Verify:** App returns to VenuesView (the list), NOT to VenueDetailScreen
13. **Verify:** The venue card shows "Seattle" (new city)
14. Tap the same venue card again
15. **Verify:** VenueDetailScreen opens and shows "456 Oak Ave, Seattle" (new values)
16. Tap "Edit" again
17. **Verify:** VenueFormScreen opens pre-filled with "456 Oak Ave" and "Seattle" (new values, not old)
18. Tap Cancel (do not save)
19. **Verify:** Returns to VenueDetailScreen (still shows new values)

**Expected result:** All steps pass. No stale data at any point.

---

**Secondary test case (verify list navigation still works):**

1. From VenuesView, tap "Add" button
2. Create a new venue (name, address, city)
3. Tap Save
4. **Verify:** Returns to VenuesView, new venue appears in list
5. Search for the new venue by name
6. **Verify:** Search filters correctly, venue appears
7. Clear search
8. Tap the new venue card → VenueDetailScreen opens
9. **Verify:** Detail screen shows correct data
10. Use back button (do not edit)
11. **Verify:** Returns to VenuesView

**Expected result:** All steps pass. List navigation unaffected.

---

**Edge case test (cancel edit, verify no pop):**

1. From VenuesView, tap a venue card → VenueDetailScreen opens
2. Tap "Edit" → VenueFormScreen opens
3. Make changes to address/city (do not save)
4. Tap Cancel or back button
5. **Verify:** Returns to VenueDetailScreen (does NOT pop to list)
6. **Verify:** Detail screen still shows original (unchanged) data

**Expected result:** Canceling an edit does not pop the detail screen. User remains on detail screen.

---

**Regression test (verify create flow unaffected):**

1. From VenuesView, tap "Add"
2. Create a new venue
3. Tap Save
4. **Verify:** Returns to VenuesView (not to a detail screen)
5. **Verify:** New venue appears in list

**Expected result:** Create flow unchanged.

---

**Platform-specific notes:**

- **macOS:** Primary test platform (confirmed affected by Tony)
- **Web:** Test the same flow if Supabase/auth permits; verify no web-specific navigation issues
- **iOS:** Test if device available; shared Flutter code should behave identically
- **Android:** Out of scope unless QA has easy access; no platform-specific code involved

---

## Completion Criteria

- [x] `ARCHITECT_PLAN.md` created and complete (all required sections present)
- [ ] Engineer implements Tasks 1–5, produces `ENGINEER_REPORT.md` and git diff
- [ ] QA verifies all test cases pass, produces `QA_REPORT.md` with verdict **APPROVED**
- [ ] Manager reviews QA verdict, authorizes commit if **APPROVED**

---

**End of Architect Plan**
