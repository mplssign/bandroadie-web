# Feature Slug

bug/gig-address-field-uneditable

# Problem Summary

On the Add/Edit Gig drawer, the address field can become non-editable even when the user has not intentionally linked the gig to a venue. The reported behavior is that taps/typing are rejected and editability sometimes returns only after multiple app restarts. Expected behavior is that address remains editable unless the user deliberately links to an existing venue.

# Root Cause

Primary cause (confirmed): `event_editor_drawer.dart` auto-links `_selectedVenueId` during free typing in the gig name field (exact/single-name match path), not only on explicit venue selection. `gig_form_fields.dart` then disables address/city/state fields whenever `isVenueLinked` is true via `enabled: !isSaving && !isVenueLinked`.

Why this causes the symptom:

- Auto-link is a side effect of typing, so users can be locked out of address editing without deliberate intent.
- The lock state appears "finicky" because it depends on runtime matching conditions (venue list contents/timing, typed value/city disambiguation), which can vary between sessions.

Confidence: HIGH (direct code-path observation in current implementation).

# Reference Docs Consulted

- `docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md`
- `docs/reference/notifications/notifications.md`

Note: These were read to satisfy the Architect phase requirement, but they are not the governing domain for this gigs-form UI bug.

# Existing System Analysis

Current Add/Edit Gig flow relevant to this bug:

1. `EventEditorDrawer` owns `_selectedVenueId` and passes `isVenueLinked: _selectedVenueId != null` into `GigFormFields`.
2. `GigFormFields` disables address/city/state inputs when `isVenueLinked` is true.
3. `_fetchGigNameSuggestions(query)` runs while typing (`RawAutocomplete.optionsBuilder` path), and performs venue matching.
4. In matching branches (single exact name match, or city-disambiguated multi-match), `_selectedVenueId` is set automatically and city/address/state may be auto-filled.
5. Once `_selectedVenueId` is set, the UI treats the gig as linked and disables address editing.

Observed mismatch with expected UX:

- "Linked venue" state is currently inferred from fuzzy/exact typing match, not from an explicit user intent action (selection/link command), so the disable behavior can trigger unexpectedly.

# Proposed Solution

Implement the minimal intent-safe fix:

1. Separate "suggestion/match discovery" from "explicit venue linking".
2. Do not set `_selectedVenueId` from passive typing paths.
3. Only set `_selectedVenueId` when user intent is explicit, such as:
   - Selecting a venue from autocomplete options.
   - Entering edit mode with an already linked `venueId`.
   - Save-time existing/new venue resolution already present in `_handleSave`.
4. Keep address/city/state locking behavior tied to true linked state (explicitly linked venue), preserving current protection against editing linked venue metadata inadvertently.

What must not change:

- Save-time venue deduplication/creation behavior in `_handleSave`.
- Existing validation rules for gig name/city.
- The ability to unlink a deliberately linked venue.

# Database Impact

- Migrations: unaffected
- RLS policies: unaffected
- RPC functions/signatures: unaffected
- Triggers: unaffected

Database: not applicable (UI/state-management fix only).

# Flutter Architecture Changes

- State ownership remains in `EventEditorDrawer` (no new providers/controllers).
- `GigFormFields` remains a presentational/widget-composition layer receiving link state from parent.
- Change scope is limited to venue-link state transitions and callback wiring for gig name interactions.

# Files to Create

none

# Files to Modify

| File                                                   | Description of change                                                                                                                                                               |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart` | Restrict `_selectedVenueId` assignment to explicit link actions; keep typing path for suggestions and optional non-locking autofill only if consistent with explicit intent policy. |
| `lib/features/events/widgets/gig_form_fields.dart`     | Adjust gig-name callback wiring as needed so typing and explicit selection are distinguishable to parent logic without changing overall form structure.                             |

# Files Off-Limits

| File                            | Reason                                                               |
| ------------------------------- | -------------------------------------------------------------------- |
| `lib/main.dart`                 | App initialization order is guardrailed and unrelated to this bug.   |
| `lib/features/notifications/**` | Notification domain is unrelated to address field editability issue. |
| `supabase/migrations/**`        | No schema or backend behavior changes required.                      |
| `supabase/functions/**`         | No edge function changes required for this UI bug.                   |

# System Impact Map

| System                                 | Impact                                                                |
| -------------------------------------- | --------------------------------------------------------------------- |
| Gigs                                   | affected                                                              |
| Rehearsals                             | unaffected                                                            |
| Setlists / Catalog                     | unaffected                                                            |
| Members / RBAC                         | unaffected                                                            |
| Auth / Session                         | unaffected                                                            |
| Routing                                | unaffected                                                            |
| Notifications                          | unaffected                                                            |
| Platform (iOS / Android / Web / macOS) | affected (behavioral fix applies cross-platform; bug reported on iOS) |

# Regression Risk

MEDIUM

Rationale:

- Change touches a central gig form interaction path and venue-link state transitions.
- Scope is still local to two event widget files with no backend/database/auth changes.
- Potential regression area is venue linking UX (especially explicit selection vs typed freeform save behavior).

# Engineer Task Breakdown

1. In `event_editor_drawer.dart`, split gig-name handling into two intent paths:
   - Typing path: suggestions/match hints only.
   - Explicit selection path: assign `_selectedVenueId` and apply linked autofill behavior.
2. Ensure typing path no longer puts the form into linked/locked state.
3. Update `gig_form_fields.dart` callback contract minimally so parent can identify explicit selection.
4. Preserve existing save-time venue dedupe/create logic in `_handleSave` unchanged.
5. Verify `Unlink venue` still appears only when actually linked and still unlocks fields.
6. Add/adjust tests if existing test coverage in this area exists; otherwise keep change minimal and rely on targeted manual verification.

# Verification Plan

## Tier 1 — Pre-deployment (must pass before `supabase db push`)

No database deployment is expected for this fix. Execute local/manual Flutter verification before any release packaging:

- PRE-DEPLOY TEST 1:
  - Open Add Gig drawer.
  - Type a gig name that exactly matches an existing venue name.
  - Expected: suggestions appear, but address remains tappable/editable unless user explicitly selects a venue option.

- PRE-DEPLOY TEST 2:
  - In Add Gig, explicitly tap an autocomplete venue option.
  - Expected: venue links, address/city/state lock behavior applies as designed.

- PRE-DEPLOY TEST 3:
  - Tap `Unlink venue` after explicit link.
  - Expected: `_selectedVenueId` clears and address/city/state become editable immediately.

- PRE-DEPLOY TEST 4:
  - Enter freeform gig name + freeform address/city/state and save.
  - Expected: save succeeds; save-time dedupe/create logic still links/creates venue as before.

- PRE-DEPLOY TEST 5:
  - Edit existing gig with linked venue.
  - Expected: starts linked/locked as before; unlinking restores editability.

## Tier 2 — Post-deployment (run after `supabase db push` succeeds)

No `supabase db push` is required for this UI-only fix; run release-candidate verification in deployed app builds instead:

- POST-DEPLOY TEST 1:
  - On iOS build, reproduce reporter flow in Add/Edit Gig with common venue names.
  - Expected: address field does not become non-editable from typing alone.

- POST-DEPLOY TEST 2:
  - Cold start app, then immediately open Add Gig and type matching/non-matching venue names.
  - Expected: no intermittent "stuck" address lock; behavior is deterministic by explicit link actions.

- POST-DEPLOY TEST 3:
  - Confirm existing linked-venue protection still works after explicit selection and during edit mode.

- POST-DEPLOY TEST 4:
  - Production verification query (data sanity):
  - Ensure recently created gigs still persist address values and venue links normally.
  - Example query:

```sql
select id, name, venue_id, address, location, state, created_at
from gigs
where created_at > now() - interval '24 hours'
order by created_at desc
limit 50;
```

SQL authoring rule compliance note:

- This feature introduces no SQL migration/tests. If any ad-hoc SQL tests are added later, follow transaction rollback/cleanup and no hardcoded production UUID rules from Architect guidance.

# QA Regression Areas

- Event creation/editing address entry in Add/Edit Gig drawer (primary).
- Venue autocomplete behavior:
  - Typing only does not lock address.
  - Explicit selection does lock while linked.
  - Unlink restores editability.
- Multi-platform sanity (iOS first, then Android/Web quick checks for parity).
- Potential gig path still saves correctly with address/state data.
- Confirm no regression in save-time venue dedupe/create behavior.

# Rollout / Migration Strategy

- No database migration.
- No edge function deploy.
- Ship as standard app release with focused iOS verification due reported platform.

# Out of Scope

- Refactoring autocomplete architecture beyond intent-safe linking behavior.
- Changing venue deduplication rules or matching algorithms beyond what is required to prevent unintended locking.
- Any notifications, auth/session, routing, or initialization-order changes.
