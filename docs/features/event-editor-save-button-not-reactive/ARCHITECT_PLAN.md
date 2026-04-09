# Architect Plan

## Feature Slug

bug/event-editor-save-button-not-reactive

## Feature Title

Event Editor Save Button Does Not Enable Reactively in Create Mode

## Problem Summary

When creating a new gig in the Event Editor drawer, the "Add Gig" button remains disabled after the user has filled in both required fields (name and city). The button only enables after the user taps outside the active text field (defocuses), or interacts with a non-text widget (e.g., setlist selector) that triggers an unrelated `setState()`. This makes the form feel broken — users believe they must select a setlist or perform another action before they can save.

## Root Cause

**Confidence: HIGH** — confirmed via direct code inspection.

The text controller listeners for `_nameController` and `_locationController` call `_markDirty()` on every text change. However, `_markDirty()` only calls `setState()` in **edit mode**:

```dart
// event_editor_drawer.dart, line ~203
void _markDirty() {
  if (widget.mode == EventEditorMode.edit && !_isDirty) {
    setState(() => _isDirty = true);
  }
}
```

In **create mode**, this method is a no-op. No `setState()` is called, so the widget never rebuilds. The button's `canSave` condition depends on `_isFormValid`, which is a getter recomputed on each build:

```dart
canSave: !_isSaving && !_isDeleting && _isFormValid &&
         (widget.mode == EventEditorMode.create || _isDirty),
```

Since no rebuild occurs, `_isFormValid` is never re-evaluated, and the button remains disabled until some other interaction triggers a rebuild (focus change, setlist selection, etc.).

## Reference Docs Consulted

Not applicable — this is a UI validation bug, not a notifications issue.

## Existing System Analysis

1. User opens Event Editor in create mode for a gig
2. User types gig name → `_nameController` listener fires → `_markDirty()` → no-op in create mode → **no rebuild**
3. User types city → `_locationController` listener fires → `_markDirty()` → no-op in create mode → **no rebuild**
4. Button widget still holds stale `canSave: false` from initial build when both fields were empty
5. User taps setlist selector → `onSetlistSelected` callback calls `setState()` directly → rebuild → `_isFormValid` re-evaluates → button enables
6. Alternatively, user taps outside text field → focus change triggers rebuild → button enables

## Proposed Solution

Add a separate listener method for text controllers that triggers a rebuild in **create mode** when form validity changes. This avoids modifying `_markDirty()` (which serves a different purpose — tracking edit-mode dirty state) and keeps the two concerns separate.

Add a new method:

```dart
void _onFormFieldChanged() {
  if (widget.mode == EventEditorMode.create) {
    setState(() {});  // Trigger rebuild to re-evaluate _isFormValid
  }
}
```

Register this listener alongside `_markDirty` on the name and location controllers. Both listeners fire on text change: `_markDirty` handles edit-mode dirty tracking, `_onFormFieldChanged` handles create-mode validation reactivity.

**Why not modify `_markDirty()`?** The `_markDirty()` method has a specific contract: it sets `_isDirty = true` once in edit mode. Adding create-mode `setState()` to it would cause unnecessary rebuilds on every keystroke in edit mode (since `_markDirty` early-returns after turning dirty once, but a combined method would need to always call `setState` in create mode). Keeping them separate preserves the existing behavior exactly and makes the fix minimal.

## Database Impact

Not applicable — pure client-side UI fix.

## Flutter Architecture Changes

- No new controllers, providers, or repositories
- No state management changes
- Single method addition + two listener registrations in `event_editor_drawer.dart`

## Files to Create

None.

## Files to Modify

| File | What Changes |
|------|-------------|
| `lib/features/events/widgets/event_editor_drawer.dart` | Add `_onFormFieldChanged()` method; register as additional listener on `_nameController` and `_locationController` in `initState()` |

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/main.dart` | Init order must not change |
| `lib/features/events/events_repository.dart` | No data layer changes needed |
| `lib/features/events/models/event_form_data.dart` | Validation model is correct |
| `lib/features/events/widgets/event_editor_actions.dart` | Button widget receives `canSave` correctly |
| `lib/features/events/widgets/gig_form_fields.dart` | Autocomplete widgets work correctly |
| `lib/features/events/widgets/event_form_fields.dart` | Form fields work correctly |
| Any migration or edge function | Not applicable |

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | affected — gig creation form reactivity |
| Rehearsals | unaffected — rehearsals have no required text fields, `_isFormValid` returns `true` |
| Block Outs | unaffected — block outs have no required text fields |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | all equally affected — this is shared Flutter code |

## Regression Risk

**LOW**

- Single file changed
- No state management or data flow changes
- No database or backend changes
- The added `setState(() {})` only fires in create mode and only triggers a rebuild — it does not modify any state variables
- Edit mode behavior is completely unaffected (the new listener is gated on create mode)

## Engineer Task Breakdown

1. **Add `_onFormFieldChanged()` method** to `_EventEditorDrawerState` — place it immediately after `_markDirty()` for grouping:
   ```dart
   /// Trigger rebuild in create mode so _isFormValid is re-evaluated
   /// as the user types in required fields.
   void _onFormFieldChanged() {
     if (widget.mode == EventEditorMode.create) {
       setState(() {});
     }
   }
   ```

2. **Register the listener** in `initState()` — add to the existing controller listener block (after line ~355):
   ```dart
   _nameController.addListener(_onFormFieldChanged);
   _locationController.addListener(_onFormFieldChanged);
   ```

3. **Test on web** — create a new gig:
   - Type gig name → button should remain disabled (location still empty)
   - Type city → button should enable immediately after first character
   - Clear city → button should disable immediately
   - Clear name → button should disable immediately

4. **Test edit mode** — open an existing gig and confirm:
   - Button starts disabled (no changes made)
   - Typing in any field enables the button (existing `_markDirty` behavior preserved)

## Verification Plan

### Tier 1 — Pre-deployment

Not applicable — no database changes.

### Tier 2 — Post-deployment

Manual verification on web (primary) and iOS (secondary):

1. Create mode — gig: type name + city → button enables reactively
2. Create mode — gig: clear either field → button disables reactively
3. Create mode — rehearsal: button enabled immediately (no required text fields)
4. Create mode — block out: button enabled immediately (no required text fields)
5. Edit mode — gig: button disabled until a change is made → typing enables it
6. Create mode — full save flow: create and save a gig without touching setlist selector

## QA Regression Areas

- Gig creation flow (primary — button reactivity)
- Rehearsal creation flow (confirm no regression)
- Block out creation flow (confirm no regression)
- Gig edit flow (confirm dirty-flag behavior preserved)
- Event deletion (confirm no regression)

## Rollout / Migration Strategy

Not applicable — client-only change. Deploy via normal app build.

## Out of Scope

- Push notification delivery issues (separate bug)
- Realtime data sync between band members (separate feature)
- Dashboard end-time filtering for same-day gigs (separate bug)
- Notification preference NULL-row handling (separate bug)
