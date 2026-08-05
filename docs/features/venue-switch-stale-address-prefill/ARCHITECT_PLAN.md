# ARCHITECT PLAN — Fix Stale Address When Switching Between Linked Venues

## 1. Feature Slug

`bug/venue-switch-stale-address-prefill`

---

## 2. Problem Summary

When a gig is linked to Venue A (with address fields populated), and the user switches to a different venue (Venue B) via the autocomplete dropdown, the `_selectedVenueId` correctly updates to Venue B's ID, but the address/city/state fields retain Venue A's stale data. This occurs because the prefill logic only fills fields that are currently empty, to avoid clobbering manually-entered values. On save, the new sync-back dialog (added in PR #122) compares Venue A's stale address (in the form fields) against Venue B's actual address, finds a mismatch, and offers to "update" Venue B — which would incorrectly overwrite Venue B's contact card with Venue A's address.

This bug predates the `feature/gig-venue-address-editable-sync` work but was not exploitable as a data-corruption path until that feature made the sync-back dialog available. Previously it was cosmetic-only.

---

## 3. Root Cause

**Confidence Level:** HIGH

**Primary failure layer:** UI prefill logic in venue selection handler

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Method:** `_handleGigNameSelected()` (lines 746–793)

**Current code pattern:**

```dart
void _handleGigNameSelected(String selection) {
  // ... venue lookup and disambiguation ...

  if (mounted) {
    setState(() {
      _selectedVenueId = selectedVenue.id;  // Line 770

      // Only fill empty fields to avoid clobbering user-entered values.
      if (selectedVenue.city != null &&
          selectedVenue.city!.isNotEmpty &&
          _locationController.text.trim().isEmpty) {
        _locationController.text = selectedVenue.city!;
      }

      if (selectedVenue.address != null &&
          selectedVenue.address!.isNotEmpty &&
          _addressController.text.trim().isEmpty) {
        _addressController.text = selectedVenue.address!;
      }

      if (selectedVenue.state != null &&
          selectedVenue.state!.isNotEmpty &&
          _stateController.text.trim().isEmpty) {
        _stateController.text = selectedVenue.state!.toUpperCase();
      }
    });
  }
}
```

**Why it fails:**

The "only fill if empty" logic (lines 775, 781, 787) was designed for the **initial venue link** scenario:

1. User types a gig name (no venue linked yet)
2. User manually enters an address
3. User then selects a venue from autocomplete
4. The manual address should NOT be overwritten

However, this same logic also applies when **switching between two already-linked venues**:

1. Gig is linked to Venue A → address fields contain Venue A's data
2. User clears gig name, types new name, selects Venue B
3. `_selectedVenueId` updates to Venue B (line 770)
4. Address fields are NOT empty, so the prefill logic skips them
5. Fields still show Venue A's stale data while `_selectedVenueId` points to Venue B

**Consequence:**

On save, `_venueNeedsUpdate()` (lines 795–831) compares the form field values against the newly linked venue's actual stored values. It finds Venue A's stale address doesn't match Venue B's real address, shows the "Update Venue" dialog, and if the user confirms without noticing, Venue B's contact card gets overwritten with Venue A's leftover address.

---

## 4. Reference Docs Consulted

- `docs/features/gig-venue-address-editable-sync/ARCHITECT_PLAN.md` — confirmed the new sync-back dialog flow and `_venueNeedsUpdate()` / `_syncVenueData()` implementation
- `lib/features/contacts/models/venue.dart` — confirmed Venue model fields: `address`, `city`, `state` (all nullable)

No venue-specific reference docs found under `docs/reference/` — this is expected, as venue management is primarily UI-driven.

---

## 5. Existing System Analysis

### Current Behavior: Venue Selection and Address Prefill

**Flow when user selects a venue from autocomplete:**

1. **Autocomplete trigger** — User types in the gig name field, `_fetchGigNameSuggestions()` queries past gig names and venue names (lines 722–745)
2. **User selection** — User picks a suggestion, `_handleGigNameSelected()` is called (lines 746–793)
3. **Venue lookup** — Method finds matching venue(s) from `venuesProvider`, disambiguates by city if multiple matches
4. **State update** — Sets `_selectedVenueId = selectedVenue.id` (line 770)
5. **Address prefill** — For each field (city, address, state):
   - Check if venue has a non-empty value
   - Check if form field is currently empty
   - If both true, fill the field
   - If either false, skip
6. **Mark dirty** — Calls `_markDirty()` to enable save button (line 793)

**Current empty-check logic (lines 771–789):**

```dart
// Only fill empty fields to avoid clobbering user-entered values.
if (selectedVenue.city != null &&
    selectedVenue.city!.isNotEmpty &&
    _locationController.text.trim().isEmpty) {
  _locationController.text = selectedVenue.city!;
}
// Same pattern for address and state
```

**Comment at line 771:** "Only fill empty fields to avoid clobbering user-entered values."

This was intentionally designed to protect manually-typed addresses when a venue is linked AFTER the user has already entered address data. However, it does not distinguish between:

- **Initial link scenario** — no venue previously linked, user may have manually typed address
- **Venue switch scenario** — venue already linked, fields contain auto-filled data from previous venue

### Interaction with Sync-Back Dialog (PR #122)

**Save-time check** — `_venueNeedsUpdate()` (lines 795–831):

```dart
Future<Venue?> _venueNeedsUpdate() async {
  if (_selectedVenueId == null) return null;

  // Fetch current venue data
  final venue = venues.firstWhere((v) => v.id == _selectedVenueId);

  // Compare form values with venue's stored values
  final formAddress = _addressController.text.trim();
  final formCity = _locationController.text.trim();
  final formState = _stateController.text.trim().toUpperCase();

  final venueAddress = venue.address ?? '';
  final venueCity = venue.city ?? '';
  final venueState = venue.state ?? '';

  final addressChanged = formAddress != venueAddress;
  final cityChanged = formCity != venueCity;
  final stateChanged = formState != venueState;

  if (addressChanged || cityChanged || stateChanged) {
    return venue;  // Mismatch detected, show dialog
  }

  return null;
}
```

**Sync-back execution** — `_syncVenueData()` (lines 833–863):

```dart
Future<bool> _syncVenueData() async {
  // Update venue's address/city/state with form field values
  final venue = await ref.read(venuesProvider.notifier).update(
    id: _selectedVenueId!,
    bandId: widget.bandId,
    data: {
      'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      'city': _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
      'state': _stateController.text.trim().isEmpty ? null : _stateController.text.trim().toUpperCase(),
    },
  );

  return venue != null;
}
```

**In the bug scenario:**

1. Fields contain Venue A's data, `_selectedVenueId` points to Venue B
2. `_venueNeedsUpdate()` compares Venue A's stale data (in fields) against Venue B's real data
3. Finds mismatch, returns Venue B object
4. Dialog shown: "Update [Venue B Name]?"
5. If user taps "Yes", `_syncVenueData()` writes Venue A's stale address to Venue B's contact card

---

## 6. Proposed Solution

### Design Approach

**Distinguish two scenarios in `_handleGigNameSelected()`:**

1. **Initial venue link** — `_selectedVenueId` was null, user is linking a venue for the first time
   - Preserve existing "only fill if empty" logic
   - Protects manually-typed addresses

2. **Venue switch** — `_selectedVenueId` was not null, user is switching from one venue to another
   - Always update address/city/state fields to match the newly selected venue
   - Even if fields are not empty
   - Even if new venue's field is empty (clear stale data)

**Implementation:**

Capture the previous venue ID before `setState`, detect if we're switching venues, then use two distinct code paths for prefill logic.

```dart
void _handleGigNameSelected(String selection) {
  // ... existing venue lookup and disambiguation ...

  // Capture previous venue ID before setState
  final previousVenueId = _selectedVenueId;
  final isSwitchingVenues = previousVenueId != null && previousVenueId != selectedVenue.id;

  if (mounted) {
    setState(() {
      _selectedVenueId = selectedVenue.id;

      if (isSwitchingVenues) {
        // Switching from one venue to another — always sync to new venue's values
        _locationController.text = selectedVenue.city ?? '';
        _addressController.text = selectedVenue.address ?? '';
        _stateController.text = selectedVenue.state?.toUpperCase() ?? '';
      } else {
        // Initial link — only fill empty fields to preserve user-entered values
        if (selectedVenue.city != null &&
            selectedVenue.city!.isNotEmpty &&
            _locationController.text.trim().isEmpty) {
          _locationController.text = selectedVenue.city!;
        }

        if (selectedVenue.address != null &&
            selectedVenue.address!.isNotEmpty &&
            _addressController.text.trim().isEmpty) {
          _addressController.text = selectedVenue.address!;
        }

        if (selectedVenue.state != null &&
            selectedVenue.state!.isNotEmpty &&
            _stateController.text.trim().isEmpty) {
          _stateController.text = selectedVenue.state!.toUpperCase();
        }
      }
    });
  }

  _markDirty();
}
```

**Key differences in venue-switch path:**

- Unconditionally assigns venue values to controllers
- Uses `?? ''` to clear fields if venue's field is empty/null
- No empty-check on form fields — we're replacing stale data with fresh data

### Scenario Validation

| Scenario                                        | Previous `_selectedVenueId` | Selected Venue | Branch Taken | Outcome                                 |
| ----------------------------------------------- | --------------------------- | -------------- | ------------ | --------------------------------------- |
| Initial link, no manual address                 | null                        | Venue A        | Initial link | Venue A's address fills empty fields ✓  |
| Initial link, manual address entered            | null                        | Venue A        | Initial link | Manual address preserved (not empty) ✓  |
| Switch from Venue A to Venue B                  | Venue A ID                  | Venue B        | Venue switch | Fields update to Venue B's data ✓       |
| Reselect same venue                             | Venue A ID                  | Venue A        | Initial link | No-op (same ID, fields already match) ✓ |
| Edit mode, venue already linked, no name change | Venue A ID                  | —              | (not called) | Fields unchanged ✓                      |

**Edge case: new venue has empty field, old venue had value**

Example: Venue A has address "123 Main St", Venue B has address null

- Switch from A to B
- `isSwitchingVenues` is true
- `_addressController.text = selectedVenue.address ?? ''` → clears to empty string
- This is correct — fields should reflect the newly linked venue's data, even if that means clearing

---

## 7. Database Impact

**Database: not applicable**

This is pure client-side UI logic. No database schema, RLS policies, triggers, or RPC functions are affected.

---

## 8. Flutter Architecture Changes

**State Management:** No new providers, controllers, or repositories required.

**Widget Changes:** None. Modification is isolated to a single method in `EventEditorDrawer` state class.

**New State Variables:** None. Solution uses the existing `_selectedVenueId` field to detect venue switches.

---

## 9. Files to Create

**None.** This is a single-method fix in an existing file.

---

## 10. Files to Modify

| File                                                   | Lines   | What Changes                                                                                                                              |
| ------------------------------------------------------ | ------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart` | 746–793 | Modify `_handleGigNameSelected()` to capture previous venue ID, detect venue switch vs. initial link, and apply appropriate prefill logic |

**Detailed change specification:**

**Before line 770** (before `setState`):

- Add local variable: `final previousVenueId = _selectedVenueId;`
- Add condition check: `final isSwitchingVenues = previousVenueId != null && previousVenueId != selectedVenue.id;`

**Inside `setState` (lines 770–789):**

- Replace the existing "only fill if empty" logic block (lines 771–789) with a conditional:
  - If `isSwitchingVenues`: unconditionally assign venue values (with `?? ''` for nulls)
  - Else: preserve existing "only fill if empty" logic

**Comment update:**

- Current comment at line 771: "Only fill empty fields to avoid clobbering user-entered values."
- Update to: "When switching venues, always sync to new venue's values. When initially linking, only fill empty fields to avoid clobbering user-entered values."

---

## 11. Files Off-Limits

| File                                                   | Reason                                                                                              |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart` | Lines outside 746–793 must not be modified — only the `_handleGigNameSelected()` method is in scope |
| `lib/features/events/widgets/gig_form_fields.dart`     | Address field enablement logic was fixed in PR #122, no changes needed                              |
| `lib/features/contacts/venues_controller.dart`         | Venue update logic is unchanged                                                                     |
| `lib/features/contacts/venues_repository.dart`         | Repository layer is unchanged                                                                       |
| `supabase/migrations/*`                                | No database changes required                                                                        |

---

## 12. System Impact Map

| System                                 | Impact                                                              |
| -------------------------------------- | ------------------------------------------------------------------- |
| Gigs                                   | **affected** — venue switch prefill behavior changes                |
| Rehearsals                             | unaffected — separate form, does not use venue linking              |
| Setlists / Catalog                     | unaffected — no interaction with gig venue logic                    |
| Members / RBAC                         | unaffected — no permission changes                                  |
| Auth / Session                         | unaffected                                                          |
| Routing                                | unaffected                                                          |
| Notifications                          | unaffected                                                          |
| Contacts (Venues)                      | indirectly affected (prevents incorrect sync-back), no code changes |
| Platform (iOS / Android / Web / macOS) | unaffected — shared Flutter code, no platform-specific paths        |

---

## 13. Regression Risk

**Overall Risk:** LOW

**Rationale:**

- **Isolated change:** Single method in event editor, no ripple effects
- **No new state:** Uses existing `_selectedVenueId` to detect switches
- **Preserves original intent:** Initial-link scenario keeps "only fill if empty" protection
- **No database changes:** Pure client-side logic
- **No cross-feature impact:** Venue switching only affects gig forms, not rehearsals, setlists, or other systems
- **Well-defined scenarios:** All four scenarios (initial link with/without manual address, venue switch, reselect same) have clear expected outcomes

**Potential risk areas:**

- **Initial link with manual address** — LOW: The "only fill if empty" path is preserved exactly
- **Venue autocomplete disambiguation** — LOW: Disambiguation logic (lines 752–767) is untouched
- **Edit mode with existing venue** — LOW: If user doesn't touch the venue name, `_handleGigNameSelected()` is never called

---

## 14. Engineer Task Breakdown

Execute tasks in order. Each task must be completed and verified before proceeding to the next.

### Task 1: Locate and Read Target Method

- [ ] Open `lib/features/events/widgets/event_editor_drawer.dart`
- [ ] Navigate to `_handleGigNameSelected()` method (lines 746–793)
- [ ] Read entire method to understand current flow
- [ ] Confirm line numbers match (may have shifted since analysis — adjust if needed)

### Task 2: Implement Venue-Switch Detection

**Before the `if (mounted)` block (before line 769):**

- [ ] Add local variable to capture previous venue ID:
  ```dart
  final previousVenueId = _selectedVenueId;
  ```
- [ ] Add condition check to detect venue switch:
  ```dart
  final isSwitchingVenues = previousVenueId != null && previousVenueId != selectedVenue.id;
  ```

### Task 3: Replace Prefill Logic with Conditional Paths

**Inside the `setState` block (replacing lines 771–789):**

- [ ] Update the comment to reflect both scenarios
- [ ] Add `if (isSwitchingVenues)` branch:
  - Unconditionally assign: `_locationController.text = selectedVenue.city ?? '';`
  - Unconditionally assign: `_addressController.text = selectedVenue.address ?? '';`
  - Unconditionally assign: `_stateController.text = selectedVenue.state?.toUpperCase() ?? '';`
- [ ] Add `else` branch:
  - Preserve existing "only fill if empty" logic for city (lines ~775–777)
  - Preserve existing "only fill if empty" logic for address (lines ~781–783)
  - Preserve existing "only fill if empty" logic for state (lines ~787–789)

**Example target code:**

```dart
if (isSwitchingVenues) {
  // Switching from one venue to another — always sync to new venue's values
  _locationController.text = selectedVenue.city ?? '';
  _addressController.text = selectedVenue.address ?? '';
  _stateController.text = selectedVenue.state?.toUpperCase() ?? '';
} else {
  // Initial link — only fill empty fields to preserve user-entered values
  if (selectedVenue.city != null &&
      selectedVenue.city!.isNotEmpty &&
      _locationController.text.trim().isEmpty) {
    _locationController.text = selectedVenue.city!;
  }

  if (selectedVenue.address != null &&
      selectedVenue.address!.isNotEmpty &&
      _addressController.text.trim().isEmpty) {
    _addressController.text = selectedVenue.address!;
  }

  if (selectedVenue.state != null &&
      selectedVenue.state!.isNotEmpty &&
      _stateController.text.trim().isEmpty) {
    _stateController.text = selectedVenue.state!.toUpperCase();
  }
}
```

### Task 4: Verify Syntax and Analyze

- [ ] Run `flutter analyze` — must pass with 0 errors
- [ ] Confirm no new warnings introduced in modified method
- [ ] Confirm `_markDirty()` call remains at end of method (line 793)

### Task 5: Generate Diff

- [ ] Run `git diff lib/features/events/widgets/event_editor_drawer.dart > engineer_diff.txt`
- [ ] Confirm diff shows:
  - Two new variables added before `setState`
  - Prefill logic wrapped in `if/else` with two branches
  - No other lines modified
- [ ] Include diff in `ENGINEER_REPORT.md`

---

## 15. Verification Plan

This feature requires only **Tier 2 — Manual UI Testing** (no database changes to deploy).

### Manual UI Testing (Post-Implementation)

Run on macOS or Web (shared Flutter code, platform-agnostic).

#### Test 1: Initial Link with Manual Address (Protection Preserved)

**Goal:** Confirm manually-typed address is NOT overwritten when venue is linked afterward.

**Steps:**

1. Open create gig drawer
2. Type address manually: "999 Test St"
3. Type city manually: "Test City"
4. Type state manually: "CA"
5. Type gig name: "The Bluebird Cafe" (a known venue with different address)
6. Select "The Bluebird Cafe" from autocomplete dropdown
7. **Expected:** Address fields retain "999 Test St", "Test City", "CA" (manual values preserved)
8. **Verify:** `_selectedVenueId` is set (gig name field shows venue name) but address fields unchanged

#### Test 2: Initial Link with No Manual Address (Prefill Works)

**Goal:** Confirm venue's address prefills empty fields on initial link.

**Steps:**

1. Open create gig drawer
2. Do NOT type any address/city/state
3. Type gig name: "The Bluebird Cafe"
4. Select from autocomplete
5. **Expected:** Address/city/state fields prefill with venue's stored values
6. Save gig
7. **Verify:** Gig saved with venue's address, no sync-back dialog shown

#### Test 3: Venue Switch (Bug Fix — Primary Test)

**Goal:** Confirm switching from Venue A to Venue B updates all address fields.

**Steps:**

1. Create or edit a gig
2. Type gig name: "The Bluebird Cafe" (Venue A)
3. Select from autocomplete
4. **Observe:** Address fields prefill with Venue A's address (e.g., "123 Main St, Nashville, TN")
5. Clear gig name field completely
6. Type a different venue name: "3rd and Lindsley" (Venue B with different address)
7. Select from autocomplete
8. **Expected (FIX BEHAVIOR):** Address fields immediately update to Venue B's address (e.g., "456 Oak Ave, Nashville, TN")
9. **Previous (BUG BEHAVIOR):** Fields would still show "123 Main St" (Venue A's stale data)
10. Save gig
11. **Expected:** If Venue B's address matches the form fields, no sync-back dialog shown
12. **Previous (BUG BEHAVIOR):** Sync-back dialog would appear offering to "update" Venue B with stale Venue A data

#### Test 4: Venue Switch to Empty Address

**Goal:** Confirm switching to a venue with no address clears stale fields.

**Steps:**

1. Create gig, select "The Bluebird Cafe" (has address)
2. **Observe:** Address fields prefill
3. Clear gig name, type a venue name that exists but has no address stored
4. Select from autocomplete
5. **Expected:** Address/city/state fields clear to empty (no stale data retained)
6. Save gig
7. **Verify:** Gig saves with empty address fields, no sync-back dialog

#### Test 5: Reselect Same Venue (No-Op)

**Goal:** Confirm reselecting the same venue doesn't cause unnecessary updates.

**Steps:**

1. Create gig, select "The Bluebird Cafe"
2. Address fields prefill
3. Clear gig name field
4. Type "The Bluebird Cafe" again, select from autocomplete
5. **Expected:** Address fields unchanged (already have correct data)
6. **Verify:** No flicker, no re-assignment (silent no-op)

#### Test 6: Edit Mode with Venue Already Linked

**Goal:** Confirm edit mode doesn't trigger unexpected prefill changes.

**Steps:**

1. Create and save a gig with "The Bluebird Cafe" (address: "123 Main St")
2. Close drawer
3. Tap gig to reopen in edit mode
4. **Observe:** Venue name and address fields pre-populated from saved gig
5. Do NOT touch the gig name field
6. Modify time or notes field
7. Save
8. **Expected:** Address fields unchanged, no venue switch detected
9. **Verify:** `_handleGigNameSelected()` was never called (no autocomplete selection)

---

## 16. QA Regression Areas

QA must test these areas after Engineer implementation and verification:

### Primary — Venue Switch Prefill (Bug Fix)

- [ ] **Test 3** (venue switch A→B) passes on all platforms: Web, iOS, Android, macOS
- [ ] Address/city/state fields update immediately on venue selection
- [ ] No stale data retained from previous venue
- [ ] Save completes without incorrect sync-back dialog

### Secondary — Initial Link Scenarios

- [ ] **Test 1** (manual address preserved) passes
- [ ] **Test 2** (prefill empty fields) passes
- [ ] Gig creation with venue autocomplete works as before

### Edge Cases

- [ ] **Test 4** (switch to venue with no address) clears fields correctly
- [ ] **Test 5** (reselect same venue) is silent no-op
- [ ] **Test 6** (edit mode, no name change) doesn't trigger prefill

### Sync-Back Dialog (PR #122 Integration)

- [ ] When user manually edits address after venue is linked, sync-back dialog still appears correctly
- [ ] When user switches venues and addresses now match, sync-back dialog does NOT appear
- [ ] Sync-back "Yes" still writes form values to venue contact card correctly

### Cross-Platform

- [ ] All tests pass on Web (Chrome)
- [ ] All tests pass on iOS (physical device or simulator)
- [ ] All tests pass on Android (physical device or emulator)
- [ ] All tests pass on macOS

---

## 17. Rollout / Migration Strategy

**Not applicable.** No database migration, no backend deployment, no feature flag required.

Changes are client-side only and deploy with the next app release.

---

## 18. Out of Scope

**Explicitly NOT included in this fix:**

- **Rehearsal form venue linking** — Rehearsals do not use venue autocomplete, not affected by this bug
- **Venue detail screen editing** — Separate bug (`bug/venue-edit-stale-detail-screen`), different root cause, different files
- **Venue autocomplete suggestion logic** — PR #118 fix remains unchanged, no changes to `_fetchGigNameSuggestions`
- **Unlink venue action** — No changes to unlink behavior
- **Create venue for gig save** — RPC path for auto-creating venues is separate, not touched
- **Multi-date potential gig forms** — Venue linking logic is the same, fix applies to all gig forms uniformly
- **Gig pay, expenses, setlist linking** — Unrelated gig form features

---

**END OF ARCHITECT PLAN**
