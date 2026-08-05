# ARCHITECT PLAN — Editable Venue Address on Gigs with Optional Sync

## 1. Feature Slug

`feature/gig-venue-address-editable-sync`

---

## 2. Problem Summary

When creating or editing a gig, the user types a venue name and BandRoadie autocompletes it from the venue contact list. Once a venue is linked to a gig (`gigs.venue_id` set), the address, city, and state fields on the gig form become read-only — the user must tap "Unlink venue" to edit them at all, even when the original venue contact card never had an address entered.

Tony wants venue autocomplete/prefill to continue working, but wants the address/city/state fields on the gig to always be editable — never locked, regardless of whether a venue is linked. If the user changes these fields on a linked gig, a confirmation dialog should appear on save asking whether to also update the venue's contact card.

---

## 3. Root Cause

**Confidence Level:** HIGH

**Primary failure layer:** UI field enablement gates

**Files:**

- `lib/features/events/widgets/gig_form_fields.dart` lines ~226, ~501, ~755

**Current code pattern:**

```dart
enabled: !isSaving && !isVenueLinked,
```

**Why it fails:**
The `!isVenueLinked` condition locks out editing whenever `_selectedVenueId` is not null, regardless of whether the venue has address data or whether the user wants to improve incomplete data. This forces the user to "Unlink venue" (losing the venue association) just to edit address fields.

**Diagnosis:**

1. User selects venue from autocomplete → `_selectedVenueId` set
2. Address/city/state prefill from venue data (may be empty)
3. Three TextField widgets compute `isVenueLinked = _selectedVenueId != null`
4. Fields become read-only: `enabled: !isSaving && !isVenueLinked` evaluates to `false`
5. User cannot edit, even when venue has no address

---

## 4. Reference Docs Consulted

- `docs/reference/architecture/database_schema.md` — confirmed schema for `venues` (address/city/state) and `gigs` (venue_id, location, address, state)
- `supabase/migrations/20260802120000_sync_gig_location_from_venue.sql` — analyzed existing venue→gig sync trigger
- `lib/components/ui/confirm_action_dialog.dart` — existing confirmation dialog pattern

---

## 5. Existing System Analysis

### Current Flow (Gig Create/Edit with Venue Link)

1. **Venue autocomplete** — User types gig name in `_buildGigNameAutocomplete()` ([gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) ~560-650)
2. **Explicit selection** — User selects from suggestions → `_handleGigNameSelected()` ([event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) ~760-790) sets `_selectedVenueId`
3. **Address fields prefill** — If venue has address/city/state, controllers are populated ([event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) ~300-320)
4. **Read-only lock** — Three TextField widgets check `isVenueLinked = _selectedVenueId != null` and set `enabled: !isSaving && !isVenueLinked` ([gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) ~226, ~501, ~755)
5. **Unlink required to edit** — User must tap "Unlink venue" ([event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) ~795-804) to clear `_selectedVenueId` and enable editing
6. **Save** — `_handleSave()` builds form data and calls `updateGig()` or `createGig()` ([event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) ~1535-1800)

### Venue ↔ Gig Data Flow (Address/City/State)

**Venue → Gig (automatic, trigger-based):**

- Migration: `20260802120000_sync_gig_location_from_venue.sql`
- Trigger: `trg_sync_gig_location_from_venue` on `AFTER UPDATE` of `venues`
- When venue's address/city/state changes, all linked gigs are updated automatically

**Gig → Venue (manual, user-initiated):**

- Currently does not exist
- This feature adds user-initiated sync-back with confirmation

**Conflict analysis:**

- When user chooses "Yes" to sync gig values to venue:
  1. We update venue record with gig's address/city/state
  2. Venue trigger fires and updates all linked gigs
  3. But since we just set venue values to match the gig, the trigger's UPDATE is a no-op (values already match)
  4. **No infinite loop or conflict risk**

### Confirmation Dialog Pattern

The app uses `showConfirmActionDialog()` helper from [confirm_action_dialog.dart](lib/components/ui/confirm_action_dialog.dart):

```dart
final confirmed = await showConfirmActionDialog(
  context: context,
  title: 'Update Venue?',
  message: 'Update venue contact info with these changes too?',
  confirmLabel: 'Yes',
  cancelLabel: 'No',
  isDestructive: false,
);
```

This pattern is used in 20+ places across the app for all confirmation flows.

---

## 6. Proposed Solution

### Change Summary

1. **Remove read-only gate** — In [gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart), change three `TextField.enabled` properties from `!isSaving && !isVenueLinked` to `!isSaving` (lines ~226, ~501, ~755)

2. **Add sync-back detection** — In [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) `_handleSave()` method (~1535), after validation passes but before saving the gig, check:
   - Is `_selectedVenueId` not null?
   - Fetch current venue data from `venuesProvider`
   - Compare form values (address, city, state) with venue's current values
   - If any differ, show confirmation dialog

3. **Confirmation dialog** — Use `showConfirmActionDialog()`:
   - Title: "Update [Venue Name]?"
   - Message: "Update this venue's contact info with these changes too?"
   - Buttons: "Yes" / "No"

4. **Sync back if Yes** — Before saving the gig, call:

   ```dart
   final venue = await ref.read(venuesProvider.notifier).update(
     id: _selectedVenueId!,
     bandId: widget.bandId,
     data: {
       'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
       'city': _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
       'state': _stateController.text.trim().isEmpty ? null : _stateController.text.trim().toUpperCase(),
     },
   );
   // Returns null on error (logged internally), check if sync succeeded
   ```

5. **Proceed with gig save** — Continue with existing gig save logic (whether user chose Yes or No)

### What Does Not Change

- Venue name autocomplete behavior (PR #118 fix remains intact — `_fetchGigNameSuggestions` is suggestion-only, `_handleGigNameSelected` is the only place that sets `_selectedVenueId`)
- "Unlink venue" action (remains available for full detachment from venue)
- `create_venue_for_gig_save` RPC flow (separate code path, not touched)
- Venue→gig sync trigger (already in place, no conflict)
- Rehearsal forms (not in scope)

---

## 7. Database Impact

**Database: affected**

### Schema (No Changes Required)

Existing columns:

- `venues`: `address`, `city`, `state`
- `gigs`: `venue_id`, `address`, `location` (stores city), `state`

### Trigger Interaction

**Existing trigger:** `sync_gig_location_from_venue` (one-way, venue → gig)

**Interaction with sync-back:**

1. User edits gig address/city/state while venue is linked
2. User saves and chooses "Yes" to sync back
3. `update()` updates venue record
4. Trigger fires: `AFTER UPDATE ON venues`
5. Trigger updates all linked gigs with venue's new values
6. Since we just set venue values to match the gig, the trigger's UPDATE is a no-op
7. **No conflict, no infinite loop**

### RLS Policies

No changes required. Operations use existing policies:

- `venues` table: user must be member of band (existing policy)
- `gigs` table: user must be member of band (existing policy)

---

## 8. Flutter Architecture Changes

### State Management

**No new providers or controllers required.**

Reuse existing:

- `venuesProvider` (Riverpod provider) — already has `update()` method
- `eventsRepositoryProvider` — unchanged, existing gig save logic

### Widget Changes

**[gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart):**

- Remove `!isVenueLinked` from three `TextField.enabled` checks
- "Unlink venue" tappable text remains visible when venue is linked (no change to that UI)

**[event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart):**

- Add `_shouldSyncVenueData()` helper method to detect if sync is needed
- Add `_syncVenueData()` helper method to perform the update
- Modify `_handleSave()` to call these helpers after validation, before gig save

---

## 9. Files to Create

**None.**

---

## 10. Files to Modify

| File                                                   | What changes                                                                                                                                                                                                                                        |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/gig_form_fields.dart`     | Remove `!isVenueLinked` from three `TextField.enabled` checks at lines ~226, ~501, ~755. Change from `enabled: !isSaving && !isVenueLinked` to `enabled: !isSaving`.                                                                                |
| `lib/features/events/widgets/event_editor_drawer.dart` | Add two helper methods: `_shouldSyncVenueData()` to detect changes, and `_syncVenueData()` to update venue. Modify `_handleSave()` to check for sync opportunity after validation passes but before saving gig. Show confirmation dialog if needed. |

---

## 11. Files Off-Limits

| File                                                     | Reason                                                              |
| -------------------------------------------------------- | ------------------------------------------------------------------- |
| `lib/features/contacts/venues_controller.dart`           | Already has `update()` method — reuse as-is, no modification needed |
| `lib/app/models/gig.dart`                                | Model structure unchanged                                           |
| `lib/app/models/venue.dart`                              | Model structure unchanged                                           |
| `supabase/migrations/*`                                  | No schema changes required                                          |
| `lib/features/events/widgets/rehearsal_form_fields.dart` | Rehearsals not in scope                                             |
| `lib/components/ui/confirm_action_dialog.dart`           | Existing helper reused as-is                                        |

---

## 12. System Impact Map

| System                                 | Impact                                                         |
| -------------------------------------- | -------------------------------------------------------------- |
| Gigs                                   | **affected** — form field enablement and save logic modified   |
| Rehearsals                             | unaffected                                                     |
| Setlists / Catalog                     | unaffected                                                     |
| Members / RBAC                         | unaffected                                                     |
| Auth / Session                         | unaffected                                                     |
| Routing                                | unaffected                                                     |
| Notifications                          | unaffected                                                     |
| Platform (iOS / Android / Web / macOS) | **affected** — shared Flutter code, no platform-specific paths |

---

## 13. Regression Risk

**Overall risk level:** **LOW**

**Rationale:**

- Only gig create/edit form affected, isolated scope
- Rehearsals, setlists, auth, routing untouched
- No database schema changes
- No new abstractions or providers
- Venue→gig trigger interaction is safe (no-op when values already match)
- Dialog pattern already proven in 20+ places in the codebase

**Specific risks mitigated:**

- **PR #118 regression:** Solution does not touch `_fetchGigNameSuggestions` or `_handleGigNameSelected` — autocomplete behavior unchanged
- **Trigger conflict:** Values sync in one direction per user action — no infinite loop risk
- **UI consistency:** Using existing `showConfirmActionDialog` pattern — no new dialog style
- **Data integrity:** Venue update uses existing `update()` method with RLS enforcement

**Known pre-existing issue (out of scope):**

- `event_editor_drawer.dart` line ~824 queries `gigs` table for `city` column, but gigs table stores city as `location`, not `city`. This is unrelated to this feature and not caused by this change. If confirmed broken, should be tracked separately.

---

## 14. Engineer Task Breakdown

Execute in strict order:

1. **Read all affected files in full** — Read [gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) lines 1-end and [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) lines 1-end to establish context.

2. **Verify PR #118 fix is intact** — Confirm that `_handleGigNameSelected()` is the only place that sets `_selectedVenueId`, and that `_fetchGigNameSuggestions()` does not set it. Do not proceed if this is not true.

3. **Remove read-only gate from address field** — In [gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) line ~226, change:

   ```dart
   enabled: !isSaving && !isVenueLinked,
   ```

   to:

   ```dart
   enabled: !isSaving,
   ```

4. **Remove read-only gate from state field** — In [gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) line ~501, change:

   ```dart
   enabled: !isSaving && !isVenueLinked,
   ```

   to:

   ```dart
   enabled: !isSaving,
   ```

5. **Remove read-only gate from city field** — In [gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) line ~755, change:

   ```dart
   enabled: !isSaving && !isVenueLinked,
   ```

   to:

   ```dart
   enabled: !isSaving,
   ```

6. **Add helper method to detect sync need** — In [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart), after `_unlinkVenue()` method (~795-804), add:

   ```dart
   /// Check if gig's venue-derived fields differ from the linked venue's current values.
   /// Returns null if no venue is linked or venue cannot be found.
   Future<Venue?> _venueNeedsUpdate() async {
     if (_selectedVenueId == null) return null;

     try {
       final venues = ref.read(venuesProvider).venues;

       final venue = venues.firstWhereOrNull((v) => v.id == _selectedVenueId);
       if (venue == null) return null;

       // Compare form values with venue's current values
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
         return venue;
       }

       return null;
     } catch (e) {
       debugPrint('[EventEditorDrawer] Error checking venue update: $e');
       return null;
     }
   }
   ```

7. **Add helper method to sync venue data** — In [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart), after `_venueNeedsUpdate()`, add:

   ```dart
   /// Update the linked venue with the gig's address/city/state values.
   /// Returns true if successful, false if update failed.
   Future<bool> _syncVenueData() async {
     if (_selectedVenueId == null) return false;

     final venue = await ref.read(venuesProvider.notifier).update(
       id: _selectedVenueId!,
       bandId: widget.bandId,
       data: {
         'address': _addressController.text.trim().isEmpty
             ? null
             : _addressController.text.trim(),
         'city': _locationController.text.trim().isEmpty
             ? null
             : _locationController.text.trim(),
         'state': _stateController.text.trim().isEmpty
             ? null
             : _stateController.text.trim().toUpperCase(),
       },
     );

     if (venue == null) {
       debugPrint('[EventEditorDrawer] Venue update returned null - sync failed');
       return false;
     }

     return true;
   }
   ```

8. **Modify \_handleSave to add sync-back confirmation** — In [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart), in the `_handleSave()` method after validation passes (after line ~1640 where block-out conflict check completes) and before `setState(() { _isSaving = true; })` (line ~1642), add:

   ```dart
   // Check if venue data should be synced back
   if (_eventType == EventType.gig) {
     final venueToUpdate = await _venueNeedsUpdate();
     if (venueToUpdate != null && mounted) {
       final shouldSync = await showConfirmActionDialog(
         context: context,
         title: 'Update ${venueToUpdate.name}?',
         message:
             'Update this venue\'s contact info with these changes too?',
         confirmLabel: 'Yes',
         cancelLabel: 'No',
         isDestructive: false,
       );

       if (shouldSync && mounted) {
         final synced = await _syncVenueData();
         if (!synced && mounted) {
           // Optional: show snackbar that venue sync failed but gig will still save
           showAppSnackBar(
             context,
             message: 'Venue update failed, but gig will still be saved.',
           );
         }
       }
     }
   }
   ```

9. **Add required imports** — At the top of [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart), add this import (Venue and venuesProvider are already imported at lines 20-21):

   ```dart
   import 'package:collection/collection.dart'; // for firstWhereOrNull
   import '../../../components/ui/confirm_action_dialog.dart';
   ```

10. **Run flutter analyze** — Confirm 0 errors in both modified files.

11. **Manual test — create gig with new venue** — Open gig form, type new venue name, verify address/city/state fields are editable. Save. No dialog should appear (no venue linked yet).

12. **Manual test — edit gig with linked venue, no changes** — Open existing gig with venue linked, leave address/city/state unchanged. Save. No dialog should appear.

13. **Manual test — edit gig with linked venue, change address** — Open existing gig with venue linked, edit address field. Save. Confirmation dialog should appear. Choose "Yes". Verify venue record updated. Verify gig saved with new address.

14. **Manual test — edit gig with linked venue, change city** — Open existing gig with venue linked, edit city field. Save. Confirmation dialog should appear. Choose "No". Verify venue record NOT updated. Verify gig saved with new city.

15. **Manual test — edit gig with linked venue, unlink before save** — Open existing gig with venue linked, tap "Unlink venue", edit address. Save. No dialog should appear (venue no longer linked).

16. **Manual test — PR #118 regression check** — Open gig form, type venue name that matches existing venue but do NOT select from dropdown. Verify address fields remain editable (no auto-lock). Save. Verify new venue is NOT created (existing venue is linked via `create_venue_for_gig_save` logic).

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (Not Applicable)

No database changes in this feature. All changes are client-side Flutter code.

### Tier 2 — Post-deployment (Manual Testing Only)

**Test 1: Address fields remain editable with linked venue**

1. Open gig form
2. Type venue name, select from autocomplete (venue is now linked)
3. Verify address, city, state fields are all editable (not grayed out)
4. Edit any field
5. Save
6. Expected: Confirmation dialog appears

**Test 2: No dialog when no venue linked**

1. Open gig form
2. Type new venue name (does not match existing venue)
3. Fill address/city/state
4. Save
5. Expected: No confirmation dialog, gig saves normally

**Test 3: No dialog when values match venue**

1. Open existing gig with venue linked
2. Leave address/city/state unchanged (match venue's values)
3. Save
4. Expected: No confirmation dialog, gig saves normally

**Test 4: Sync back on "Yes"**

1. Open existing gig with venue linked
2. Change address from "123 Main St" to "456 Oak Ave"
3. Save
4. Expected: Dialog appears with venue name in title
5. Choose "Yes"
6. Expected: Gig saves, venue record updated with new address
7. Open venue contact card, verify address updated

**Test 5: No sync on "No"**

1. Open existing gig with venue linked
2. Change city from "Chicago" to "Milwaukee"
3. Save
4. Expected: Dialog appears
5. Choose "No"
6. Expected: Gig saves with new city, venue record unchanged
7. Open venue contact card, verify city still "Chicago"

**Test 6: Unlink venue disables sync**

1. Open existing gig with venue linked
2. Tap "Unlink venue"
3. Edit address
4. Save
5. Expected: No dialog (venue no longer linked), gig saves normally

**Test 7: PR #118 regression check**

1. Open gig form
2. Type venue name matching existing venue but do NOT select from dropdown
3. Fill address/city/state
4. Save
5. Expected: Autocomplete logic matches venue, no duplicate created, no accidental lock

---

## 16. QA Regression Areas

**Primary validation:**

- Gig form address/city/state fields remain editable when venue is linked
- Confirmation dialog appears only when venue is linked AND values differ
- "Yes" updates venue record + saves gig
- "No" saves gig only, venue unchanged
- Unlink venue still works as before
- No dialog when no venue linked or values match

**Regression checks:**

- Venue autocomplete/prefill behavior (PR #118 fix must remain intact)
- Create gig with new venue (no venue linked initially)
- Create gig with existing venue selected from autocomplete
- Edit gig with no venue linked
- Edit gig with venue linked but no changes to address/city/state
- Rehearsal forms unaffected (not in scope, but verify no accidental changes)

---

## 17. Rollout / Migration Strategy

**Not applicable** — client-side change only, no database migration required.

**Deployment:**

1. Merge to main
2. Deploy web via `./tools/deploy_web.sh`
3. iOS/Android/macOS: next app release

---

## 18. Out of Scope

**Explicitly not included in this feature:**

1. **Rehearsal venue linking** — Rehearsals do not have venue_id or address fields, out of scope
2. **Venue name sync** — If user changes gig name after linking venue, no sync-back for name (only address/city/state)
3. **Bulk sync** — Updating multiple gigs when a venue is edited (already handled by existing trigger, unchanged)
4. **City column bug** — `event_editor_drawer.dart` line ~824 queries `gigs.city` but should query `gigs.location`. Pre-existing, not caused by this feature. Should be tracked separately if confirmed broken.
5. **Multi-field confirmation** — Dialog fires once on Save summarizing all changed fields together, not on individual field blur
6. **Venue contact persons** — Sync applies to venue address/city/state only, not to venue_contacts table

---

_ARCHITECT_PLAN.md complete. Ready for Engineer implementation._
