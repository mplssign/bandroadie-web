# Architect Plan — Rehearsal Form Save Button and Validation

## Feature Slug

`bug/rehearsal-form-save-button-and-validation`

## Problem Summary

The rehearsal/gig event editor form has two reported issues:

1. **Button state concern:** User reports that the Save/Update button is incorrectly disabled until a setlist is selected, despite setlist_id being nullable.

2. **Missing validation feedback:** When Save/Update is tapped with incomplete required fields, validation runs but only displays a generic error banner at the top of the form. There is no scroll-to-error, no inline error message below the failing field, and no visual indicator (red outline) on the invalid field.

## Root Cause

### Issue 1 — Button State

**Confidence: HIGH**

**Diagnosis:** The Save/Update button is incorrectly gated on form field validation via `_isFormValid`.

The Save/Update button is controlled by the `canSave` condition in `event_editor_drawer.dart` (line ~1987):

```dart
canSave: !_isSaving &&
    !_isDeleting &&
    _isFormValid &&
    (widget.mode == EventEditorMode.create || _isDirty)
```

For rehearsals, `_isFormValid` (lines 845-856) checks:

```dart
return _locationController.text.trim().isNotEmpty;
```

For gigs, `_isFormValid` checks:

```dart
final hasName = _nameController.text.trim().isNotEmpty;
final hasLocation = _locationController.text.trim().isNotEmpty;
return hasName && hasLocation;
```

The `EventFormData.validate()` method (lines 380-408) validates:

- Gigs: name and location required
- Rehearsals: location required (but only via `_isFormValid` check, not in `validate()`)
- **Setlist is never validated** — it is correctly treated as optional

**Root cause:** The requirement is that the Save/Update button must never be disabled based on form field state. Validation should happen on tap only, not as a pre-condition for enabling the button. The inline scroll-to-error flow (Issue 2 fix) replaces the disabled state entirely.

**Conclusion:** Button is NOT gated on setlist_id (correct), but IS incorrectly gated on location/name via `_isFormValid`. This check must be removed from `canSave` and moved into the `_handleSave()` validation path.

### Issue 2 — Missing Validation Feedback

**Confidence: HIGH**

**Diagnosis:** Validation feedback is incomplete.

Current flow when Save/Update is tapped:

1. `_handleSave()` calls `formData.validate()`
2. If errors exist, `_errorMessage` is set to `errors.first`
3. Error banner displays at top of form (line ~1916)
4. **No scroll to failing field**
5. **No inline error text below field**
6. **No red error border on field**

The form defines `_fieldErrors` map (line 187) but never populates it. Infrastructure for field-level errors exists but is unused.

Required fields by event type:

- **Rehearsals:** location only
- **Gigs:** name and location

**Root cause:** Validation system stops at first error and displays a banner. Field-level indicators are not implemented.

## Reference Docs Consulted

No domain-specific reference docs exist for form validation patterns in `docs/reference/`.

Consulted:

- `docs/agents/ARCHITECT.md` — Architect phase protocol
- `docs/agents/GUARDRAILS.md` — Code change discipline, file size targets
- `docs/agents/OPERATING_MODEL.md` — Pipeline gates, minimal diff surface

## Existing System Analysis

### Current Validation Flow

1. User taps Save/Update button
2. `_handleSave()` → `_buildFormData()` → `formData.validate()`
3. `EventFormData.validate()` returns `List<String>` of error messages
4. If `errors.isNotEmpty`, first error is assigned to `_errorMessage`
5. Banner displays error at top of scrollable form
6. Form does not scroll or highlight the failing field

### Form Structure

- Parent: `EventEditorDrawer` (stateful widget)
- Scrollable: `SingleChildScrollView` (no ScrollController currently)
- Child widgets:
  - `RehearsalFormFields` — location autocomplete for rehearsals
  - `GigFormFields` — name/location autocomplete for gigs
  - `EventFormFields` — shared fields (date, time, notes, setlist)

### Required Field Validation

**Rehearsals:**

- Location: required (validated in `_isFormValid`)

**Gigs:**

- Name: required (validated in `EventFormData.validate()`)
- Location (City): required (validated in `EventFormData.validate()`)

**Both:**

- Setlist: optional (never validated)
- Notes: optional
- Recurrence fields: conditional validation when recurring is enabled

## Proposed Solution

### Issue 1 — Remove \_isFormValid from canSave

**Change required:** Remove `_isFormValid` from the `canSave` condition.

**Implementation:**

- Update `canSave` to: `!_isSaving && !_isDeleting && (widget.mode == EventEditorMode.create || _isDirty)`
- Move location validation (currently in `_isFormValid`) into the `_handleSave()` validation path
- For rehearsals: if location is empty, populate `_fieldErrors['location']` and trigger scroll-to-error
- For gigs: location validation already exists in `EventFormData.validate()` — ensure it populates `_fieldErrors`

**Rationale:** Validation happens on tap only. The button is always enabled (except when saving/deleting or no changes in edit mode). Field-level errors guide the user, not a disabled button.

### Issue 2 — Add Field-Level Validation Feedback

**Minimal implementation:**

1. **Add GlobalKeys for validated fields** (`event_editor_drawer.dart` `_EventEditorDrawerState`):

   ```dart
   final _locationKey = GlobalKey();  // Rehearsal location
   final _gigNameKey = GlobalKey();   // Gig name
   final _gigLocationKey = GlobalKey(); // Gig city
   ```

2. **Add ScrollController** to the existing `SingleChildScrollView`:

   ```dart
   final _scrollController = ScrollController();
   ```

   - Dispose in `dispose()`
   - Assign to `controller` param of `SingleChildScrollView`

3. **Enhance `_handleSave()` validation logic**:
   - When `formData.validate()` returns errors, parse error strings into `_fieldErrors` map
   - Map known error messages to field keys:
     - "Gig name is required" → `'gigName'`
     - "City is required" → `'gigLocation'`
     - Any error mentioning "location" (for rehearsals) → `'location'`
   - Scroll to first failing field using its GlobalKey:
     ```dart
     final context = _firstFailingFieldKey.currentContext;
     if (context != null) {
       Scrollable.ensureVisible(context, duration: Duration(milliseconds: 300));
     }
     ```

4. **Pass GlobalKeys and fieldErrors to child widgets**:
   - `RehearsalFormFields`: add `locationKey` and `fieldErrors` params
   - `GigFormFields`: add `gigNameKey`, `gigLocationKey`, and `fieldErrors` params

5. **Update child widgets to display inline errors**:
   - Check `fieldErrors[keyName]` for error message
   - If error exists:
     - Wrap field with `Key(globalKey)`
     - Apply `errorBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.error))`
     - Display error text below field: `Text(errorMessage, style: errorStyle)`
   - Follow Material `InputDecoration` conventions for error styling

6. **Clear field errors when user edits**:
   - Add listeners to text controllers
   - On text change, remove that field's key from `_fieldErrors` map

## Database Impact

**Not applicable.** This is a client-side UI validation issue only.

## Flutter Architecture Changes

### State Management

- Add GlobalKeys and ScrollController to `_EventEditorDrawerState`
- Populate existing `_fieldErrors` map during validation
- Pass error state down to child widgets

### Widgets Modified

| Widget                | Change                                                                        |
| --------------------- | ----------------------------------------------------------------------------- |
| `EventEditorDrawer`   | Add GlobalKeys, ScrollController, enhance `_handleSave()` logic               |
| `RehearsalFormFields` | Accept `locationKey` and `fieldErrors`, apply error styling to location field |
| `GigFormFields`       | Accept `gigNameKey`, `gigLocationKey`, and `fieldErrors`, apply error styling |

### Repositories / Controllers

None. This is purely a UI change.

## Files to Create

None.

## Files to Modify

| File                                                     | Changes                                                                                                                                                                                                                                                                                                                                               |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart`   | Remove `_isFormValid` from `canSave` condition, remove `_isFormValid` getter, add GlobalKeys (3), ScrollController (1), enhance `_handleSave()` validation to include location check for rehearsals and populate `_fieldErrors` map, scroll to first error, pass keys/errors to child widgets, add controller listeners to clear field errors on edit |
| `lib/features/events/widgets/rehearsal_form_fields.dart` | Accept `locationKey` and `fieldErrors` params, wrap location field with key, apply error border and text when error exists                                                                                                                                                                                                                            |
| `lib/features/events/widgets/gig_form_fields.dart`       | Accept `gigNameKey`, `gigLocationKey`, and `fieldErrors` params, wrap name/location fields with keys, apply error borders and text when errors exist                                                                                                                                                                                                  |

## Files Off-Limits

| File                                              | Reason                                                               |
| ------------------------------------------------- | -------------------------------------------------------------------- |
| `lib/main.dart`                                   | Init order must not change                                           |
| `lib/features/events/models/event_form_data.dart` | Validation logic is correct; do not change which fields are required |
| `lib/features/events/events_repository.dart`      | No repository changes needed                                         |
| All migration files                               | No database changes                                                  |

## System Impact Map

| System                                 | Impact                                                        |
| -------------------------------------- | ------------------------------------------------------------- |
| Gigs                                   | affected — gig form will show inline errors for name/location |
| Rehearsals                             | affected — rehearsal form will show inline error for location |
| Setlists / Catalog                     | unaffected                                                    |
| Members / RBAC                         | unaffected                                                    |
| Auth / Session                         | unaffected                                                    |
| Routing                                | unaffected                                                    |
| Notifications                          | unaffected                                                    |
| Platform (iOS / Android / Web / macOS) | affected — UI behavior change across all platforms            |

## Regression Risk

**LOW**

**Rationale:**

- Changes are isolated to event editor drawer UI only
- No state management changes (using existing `_fieldErrors` map)
- No repository or database changes
- No changes to validation rules (only presentation of errors)
- Scroll-to-error is additive, does not break existing flow
- Impact limited to create/edit event drawer on all platforms

**Risk areas:**

- GlobalKey usage: ensure keys are properly assigned to correct widgets
- ScrollController: ensure disposal, no memory leaks
- Field error clearing: ensure listeners do not cause rebuild loops

## Engineer Task Breakdown

1. **Add GlobalKeys and ScrollController to `_EventEditorDrawerState`**
   - Declare 3 GlobalKeys: `_locationKey`, `_gigNameKey`, `_gigLocationKey`
   - Declare `_scrollController`
   - Assign `_scrollController` to `SingleChildScrollView.controller`
   - Dispose `_scrollController` in `dispose()`

2. **Update `canSave` condition and enhance `_handleSave()` validation logic**
   - Remove `_isFormValid` from `canSave` condition (button now only disabled for `_isSaving`, `_isDeleting`, or in edit mode `!_isDirty`)
   - Remove the `_isFormValid` getter entirely
   - In `_handleSave()`, before calling `formData.validate()`, add client-side check for rehearsal location:
     - If event type is rehearsal and location is empty, add error to `_fieldErrors['location'] = 'Location is required'`
   - When `formData.validate()` returns errors, iterate and populate `_fieldErrors` map
   - Map error messages to field keys using string matching ("Gig name is required" → `gigName`, "City is required" → `gigLocation`)
   - Determine first failing field based on event type and error map
   - Call `Scrollable.ensureVisible()` with first failing field's GlobalKey context
   - Set state to trigger error display

3. **Add field error clearing logic**
   - In text controller listeners, check if field has an error in `_fieldErrors`
   - If error exists, remove that key from map and call `setState()`

4. **Update `RehearsalFormFields` widget**
   - Add `locationKey` (GlobalKey) and `fieldErrors` (Map<String, String>) params
   - Wrap location TextField with `key: locationKey`
   - Check `fieldErrors['location']` — if exists, apply error styling
   - Add `errorBorder` to `InputDecoration` using `AppColors.error`
   - Display error text below field if error exists

5. **Update `GigFormFields` widget**
   - Add `gigNameKey`, `gigLocationKey` (GlobalKey), and `fieldErrors` params
   - Wrap name and location TextFields with their respective keys
   - Check `fieldErrors['gigName']` and `fieldErrors['gigLocation']`
   - Apply error styling (border + text) to fields with errors

6. **Test all event types**
   - Create rehearsal with empty location → should scroll to location, show inline error
   - Create gig with empty name → should scroll to name, show inline error
   - Create gig with empty city → should scroll to city, show inline error
   - Edit rehearsal with valid data, clear location, tap Update → should show error
   - Verify button enable/disable logic unchanged

## Verification Plan

**Tier 1 — Pre-deployment:** Not applicable (client-only changes).

**Tier 2 — Post-deployment:**

Not applicable. This is a client-side UI change; no database or edge function deployment required.

**Manual Testing Checklist:**

1. **Create Rehearsal — Empty Location**
   - Open Add Event drawer
   - Select Rehearsal
   - Leave location empty
   - Tap "Add Rehearsal"
   - Expected: Form scrolls to location field, red border appears, inline error displays below field

2. **Create Gig — Empty Name**
   - Open Add Event drawer
   - Select Gig
   - Enter city, leave name empty
   - Tap "Add Gig"
   - Expected: Form scrolls to name field, red border, inline error

3. **Create Gig — Empty City**
   - Open Add Event drawer
   - Select Gig
   - Enter name, leave city empty
   - Tap "Add Gig"
   - Expected: Form scrolls to city field, red border, inline error

4. **Error Clearing**
   - Trigger validation error (e.g., empty location)
   - Start typing in the field
   - Expected: Red border and error text disappear immediately

5. **Button State (Regression Check)**
   - Create rehearsal with empty location → button should be **enabled**
   - Tap "Add Rehearsal" with empty location → form scrolls to location, shows inline error
   - Create rehearsal with empty setlist → button should be enabled (setlist is optional)
   - Edit rehearsal without making changes → button should be disabled (intentional)
   - Edit rehearsal, change location → button should be enabled
   - Create gig with empty name → button should be **enabled**, tapping triggers scroll-to-error
   - Create gig with empty city → button should be **enabled**, tapping triggers scroll-to-error

6. **Cross-Platform**
   - Test on iOS, Android, macOS, Web
   - Verify scroll-to-error works on all platforms
   - Verify error styling renders correctly on all platforms

## QA Regression Areas

**Primary focus:**

- Event creation/editing for rehearsals and gigs
- Validation feedback for required fields
- Button enable/disable state consistency

**Regression testing:**

- Gig creation with all fields filled → should save normally
- Rehearsal creation with all fields filled → should save normally
- Potential gig creation (member selection required) → verify member validation still works
- Recurring rehearsal creation → verify day selection validation still works
- Edit mode for existing events → no unintended behavior changes
- Setlist selection (optional) → does not affect button state

## Rollout / Migration Strategy

Not applicable. This is a client-side UI change only. No database migration, no backend deploy.

**Deployment:**

- Flutter build and deploy to web (Vercel)
- Flutter release for iOS/Android/macOS (standard app release process)

## Out of Scope

- Changing which fields are required (location for rehearsals, name+location for gigs)
- Adding validation for optional fields (setlist, notes, gig pay)
- Changing button enable/disable logic beyond what's necessary for validation feedback
- Refactoring event editor drawer architecture
- Adding validation for other forms in the app (e.g., setlist editor, member editor)
- Adding client-side validation before form submission (current design validates on save tap only)
