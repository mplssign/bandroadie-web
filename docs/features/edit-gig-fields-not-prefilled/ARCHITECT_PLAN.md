# Feature Slug

bug/edit-gig-fields-not-prefilled

# Problem Summary

When editing an existing gig, the "Gig Venue / Festival / Name" field and the City field are blank even though the gig record already contains the saved venue name and city. The same gig is displayed correctly in View Gig, which shows the name, address, and city. This creates a data-loss risk because the user must retype values or can accidentally overwrite the valid saved values with empty input.

Expected behavior: in edit mode, the gig form must prefill the existing venue name, city, address, and state exactly as stored.

Actual behavior: the Name and City fields are empty when the edit drawer opens; the Address field remains correctly populated via the plain text controller and is therefore not the root of the bug. The issue is isolated to the migrated Forui autocomplete fields.

Affected platforms: unconfirmed; the issue lives in shared Flutter code, so it likely reproduces on web/iOS/Android/macOS. The feature is not platform-specific.

# Root Cause

Primary root cause: in the gig edit flow, the drawer seeds `_gigNameText` and `_gigCityText` from `widget.existingEvent` in `initState()`, but these values are never passed into the managed `FAutocomplete` controls in the form widget. The field widgets instantiate `FAutocomplete.text(...)` and `FAutocomplete.textBuilder(...)` with `FAutocompleteControl.managed(...)` and no `controller`/initial value wiring.

Confidence: HIGH

Evidence from code inspection:

- [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L246-L271): in edit mode, the form state is initialized with `data.name` and `data.location` in `_gigNameText` and `_gigCityText` respectively. The address controller is also seeded via `_addressController.text = data.address ?? ''`, and the state controller is also seeded from `data.state`.
- [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart#L476-L561): both autocomplete widgets are created with `FAutocompleteControl.managed(...)` and no initial controller or text value is supplied. The widgets therefore render with no internal value, even though the parent drawer state already has the saved data.
- [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart#L180-L214): the Address field is a plain `AppTextField` and is correctly seeded from the text controller in the parent. This matches the expected correct behavior and explains why the issue was reported as "name and city blank" rather than "address blank".
- [docs/features/forui-autocomplete-migration/ARCHITECT_PLAN.md](docs/features/forui-autocomplete-migration/ARCHITECT_PLAN.md) documents the pattern: `FAutocompleteControl.managed()` accepts an optional `controller: FAutocompleteController?` parameter, and this was not wired up in the migration. That direct omission is the root cause.
- [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart#L174-L201): the rehearsal location field follows the same pattern and likely has the same gap in edit mode. It is not the current bug report but shares the same root cause pattern and must be reviewed for parity.

This is a direct state-binding bug in the shared Flutter form layer rather than a backend or data persistence problem.

# Reference Docs Consulted

The following reference docs were read in full as required for notification domain context even though this feature is not a notification bug:

- [docs/reference/notifications/NOTIFICATION_SYSTEM.md](docs/reference/notifications/NOTIFICATION_SYSTEM.md)
- [docs/reference/notifications/notifications.md](docs/reference/notifications/notifications.md)
- [docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md](docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md)

These docs are not directly relevant to the form-prefill bug, but they were reviewed and did not conflict with the observed code behavior. No notification-specific requirements alter the fix.

# Existing System Analysis

Current behavior, create/edit flow for gig fields:

1. The user opens an existing gig in the event editor drawer.
2. [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L214-L271) receives `widget.existingEvent` and seeds all relevant backing fields:
   - `_gigNameText = data.name`
   - `_gigCityText = data.location`
   - `_addressController.text = data.address ?? ''`
   - `_stateController.text = data.state ?? ...`
3. These values are tracked in the drawer state and hint controllers are initialized using `hasInitialValue` checks.
4. The actual rendering layer is [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart#L476-L561), which builds the visual controls.
5. The Name and City widgets are constructed with managed `FAutocompleteControl` objects that do not receive an external controller, and therefore render empty even though the parent state has the correct value.
6. The Address field is a standard `AppTextField` with a text controller already seeded in the drawer, so it correctly displays the existing address. This explains why the report mentions "venue / name and city" while the address is expected to be correct.
7. The same bug pattern exists for rehearsal location autocomplete in [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart#L174-L201). The underlying state is loaded in the drawer for rehearsal edit mode, but the managed autocomplete does not receive that initial value.

Key invariant preserved by the fix:

- Create flow behavior must remain unchanged; only edit mode should seed the initial value for existing records.
- recent Forui label/hint fixes must remain intact; no label or hint behavior is being modified.

# Proposed Solution

Implement the minimal fix by supplying an external `FAutocompleteController` for the Name and City autocompletes, initialized with the existing values from edit-mode state when present, while leaving create-mode behavior unchanged.

What changes:

- In edit mode, when the drawer has an existing event, create a managed `FAutocompleteController` seeded with `data.name` for the gig name field and `data.location` for the city field.
- Pass that controller into the relevant `FAutocomplete` widget via `FAutocompleteControl.managed(controller: ...)`.
- Keep the existing `onChange` callback flow and update semantics intact.
- Ensure the controller is only populated in edit mode and only when the value is non-empty.
- Keep the Address field and State field as-is, because they already bind correctly to their controllers.
- Review the rehearsal location autocomplete in the same pattern and apply the equivalent minimal fix if the same missing controller binding is present.

What must not change:

- No changes to backend persistence, Supabase, migrations, RLS, or RPC logic.
- No changes to field labels, hint text, or recent Forui wrapper behavior from PR #194.
- No changes to create-flow logic for blank forms.
- No extra architectural abstraction; this remains a controller-binding fix local to the form widgets.

Any new files required: none.

# Database Impact

Database: not applicable.

This bug is entirely in client-side widget state and managed autocomplete control binding. No database writes, triggers, RLS, or RPCs are involved.

- Migrations: not required
- Edge function deploy: not required
- RLS: unaffected
- RPCs: unaffected
- Triggers: unaffected

# Flutter Architecture Changes

State: no new provider or state container needed; the existing edit-mode state in the drawer is already the source of truth. Only the binding between that state and the widgets must be restored.

Widgets: the affected widgets are [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) and, if parity is required, [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart).

Repositories: unaffected.

Routing/init order: unaffected.

# Files to Create

none.

# Files to Modify

| File                                                                                                             | What changes                                                                                                                                                                                |
| ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart)             | Seed the `FAutocomplete` controlled text for the gig name and city fields from the existing edit-mode values, without altering create-mode defaults or the label/hint behavior.             |
| [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart) | Apply the same controller-binding fix if the rehearsal location autocomplete is also missing an initial value in edit mode.                                                                 |
| [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)     | May require a minimal value pass-through or controller creation to support the initial text binding in edit mode, if the form API does not already expose a compatible controller property. |

# Files Off-Limits

| File                                                                                               | Reason                                                                  |
| -------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| [lib/main.dart](lib/main.dart)                                                                     | Initialization order must not change.                                   |
| [lib/features/events/events_repository.dart](lib/features/events/events_repository.dart)           | Bug is in UI prefilling, not persistence.                               |
| [lib/features/events/models/event_form_data.dart](lib/features/events/models/event_form_data.dart) | Existing data model is already correct; no schema changes are required. |
| [supabase/](supabase/)                                                                             | No backend change is involved.                                          |
| [sql/](sql/)                                                                                       | No SQL change is involved.                                              |
| Any migration file under [supabase/migrations](supabase/migrations)                                | Not required.                                                           |

Migration policy: not required
Edge function deploy: not required
New dependencies: not allowed
New files: none

# System Impact Map

| System                                 | Impact                                                |
| -------------------------------------- | ----------------------------------------------------- |
| Gigs                                   | affected                                              |
| Rehearsals                             | affected (parity check for same autocomplete pattern) |
| Setlists / Catalog                     | unaffected                                            |
| Members / RBAC                         | unaffected                                            |
| Auth / Session                         | unaffected                                            |
| Routing                                | unaffected                                            |
| Notifications                          | unaffected                                            |
| Platform (iOS / Android / Web / macOS) | affected (shared form code)                           |

# Regression Risk

Regression risk: LOW

Rationale:

- The fix is narrowly scoped to initial-value binding for managed autocomplete controls.
- It does not change persistence, auth, routing, or backend logic.
- The create flow remains untouched, and the recent label/hint fix is preserved.
- The main risk is a parity gap in similar autocomplete fields (rehearsal location), which is addressed by the same minimal pattern.

# Engineer Task Breakdown

1. Inspect the exact managed `FAutocomplete` widgets in [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart) and verify no external controller is supplied.
2. Trace the edit-mode state seeding in [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L214-L271) to confirm the saved values exist before render.
3. Add a minimal controller binding in the gig name autocomplete so edit mode pre-populates the existing venue name.
4. Add a minimal controller binding in the city autocomplete so edit mode pre-populates the existing city.
5. Validate the Address and State fields still retain correct data with no extra changes.
6. Inspect [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart#L174-L201) for the same missing controller pattern and fix it if the same root cause is present.
7. Confirm no label, hint, or create-flow behavior regressed.
8. Produce a final diff review to ensure the fix is limited to the controller wiring and not broader form behavior.

# Verification Plan

## Tier 1 — Pre-deployment (must pass before `supabase db push`):

This bug is client-only; there is no database schema change. Pre-deploy validation is limited to Flutter widget behavior and code review.

- `-- PRE-DEPLOY TEST 1:` Confirm the saved gig name is present in `widget.existingEvent` state before widget build, by code review of [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L214-L271).
- `-- PRE-DEPLOY TEST 2:` Confirm the managed `FAutocomplete` widget receives an initial controller value in edit mode, not just a `managed(onChange: ...)` callback.
- `-- PRE-DEPLOY TEST 3:` Validate create-mode behavior remains unchanged by checking the widget still renders an empty autocomplete when no existing event is provided.
- `-- PRE-DEPLOY TEST 4:` Manually open an existing gig in edit mode and verify the Name field and City field are prefilled; verify Address remains correct and State is also populated if set.
- `-- PRE-DEPLOY TEST 5:` Repeat the same check on a rehearsal edit form if the rehearsal location field is fixed for the same root cause.

## Tier 2 — Post-deployment (run after `supabase db push` succeeds):

This feature does not require `supabase db push`, but the post-deploy verification should confirm the fix in the shipped app.

- `-- POST-DEPLOY TEST 1:` Open an existing gig with saved venue name and city and confirm the edit form shows the correct values without retyping.
- `-- POST-DEPLOY TEST 2:` Confirm the user can save without clearing the existing values and that the update path preserves the saved values.
- `-- POST-DEPLOY TEST 3:` Validate rehearsal edit mode still shows the prefilled location if the same controller-binding fix was applied there.
- `-- POST-DEPLOY TEST 4:` Confirm no regressions in label/hint rendering or create-mode blank fields on the event editor.

# QA Regression Areas

QA must specifically test:

- Edit mode on an existing gig with a venue name and city: the Name and City fields must be prefilled without retyping.
- Address field: still correct in edit mode and does not regress.
- State field: still correct and synchronized with the existing gig data.
- Create mode: blank fields remain blank for a new gig; no stale data from previous edits is reused.
- Rehearsal location edit fields: confirm the same bug pattern is not present if the rehearsal field shares the same controller issue.
- Forui label/hint behavior: the labels and hint text still render correctly after the fix, matching the prior PR #194 fix.

# Rollout / Migration Strategy

Not applicable. This is a client-side form fix without database or backend changes.

# Out of Scope

- Any change to storage, APIs, or Supabase schema.
- Any refactor unrelated to the managed autocomplete controller binding.
- Any work on notification delivery, since this bug is not in the notifications domain.
- Any broad “Forui cleanup” beyond the affected fields needed to fix the root cause.
