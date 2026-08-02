# ARCHITECT_PLAN

## 1. Feature Slug

`bug/venue-state-city-mixup`

## 2. Problem Summary

When creating a gig from a selected venue, the gig city field is being populated with mixed city/state content instead of city-only content. Because gig rendering appends `state` to `location` for display, this results in duplicated state abbreviation on cards (for example, city/state mixed in `location` plus `state` appended again).

Expected behavior is strict field separation:

- `location` (gig city) = venue city only
- `state` (gig state) = venue state only

## 3. Root Cause

**Confirmed root cause (HIGH confidence):**
In `EventEditorDrawer` venue auto-fill, the code concatenates venue city and venue state into the city controller (`_locationController`) during single-match venue linking.

Evidence (confirmed in code):

- `lib/features/events/widgets/event_editor_drawer.dart` in `_fetchGigNameSuggestions()` builds `cityState` with `venue.city` + `venue.state` and assigns it to `_locationController.text`.
- `lib/features/events/events_repository.dart` persists `location` from `formData.location` and `state` from `formData.state` as separate columns, so mixed city/state in `location` is saved as bad payload.
- `lib/app/models/gig.dart` `locationDisplay` appends `state` to `location`, amplifying the bug into visible duplicate state text on gig cards.

Why this happens:

- Auto-fill path writes state into the city field.
- Save path persists city and state separately (as designed), so polluted city data is retained.
- Display path appends state again, producing duplicated state output.

## 4. Existing System Analysis

Data flow for affected path:

1. User types/selects gig name in event editor.
2. `_fetchGigNameSuggestions()` links a venue when exact name match is found.
3. Current code auto-fills `_locationController` with `"<city>, <STATE>"` (incorrect for the city field).
4. `_buildFormData()` maps `_locationController` to `formData.location` and `_stateController` to `formData.state`.
5. `EventsRepository.createGig()/updateGig()` writes:
   - `gigs.location = formData.location`
   - `gigs.state = formData.state`
6. Gig cards render `gig.locationDisplay`, which appends `state` to `location`, causing duplicate state display when `location` already contains state text.

## 5. Proposed Solution (Minimal)

Make a localized fix in the venue auto-fill logic:

- In `_fetchGigNameSuggestions()` single-match branch, auto-fill city with **city only**.
- Keep state auto-fill behavior unchanged in `_stateController`.
- Do not change repository contracts, DB schema, or rendering model.

Implementation intent:

- Replace the `cityState` concatenation assignment with direct `venue.city` assignment.

Result:

- Newly created/edited gigs from venue selection store clean city/state separation.
- Gig card duplication caused by this creation path stops.

## 6. Database Impact

- **Migrations:** not required
- **RLS policies:** unaffected
- **RPC functions:** unaffected
- **DB triggers/functions:** unaffected

Reason: defect is in Flutter client field mapping before persistence, not in database logic.

## 7. Flutter Architecture Changes

- State management: no provider architecture changes
- Repository layer: no changes
- Widget changes: one localized behavior correction in existing event editor widget logic
- No new abstractions

## 8. Files to Create

- none

## 9. Files to Modify

| File                                                   | Change                                                                                                                                                             |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/events/widgets/event_editor_drawer.dart` | In `_fetchGigNameSuggestions()`, change single-match venue city auto-fill so `_locationController.text` receives only `venue.city` (not city+state concatenation). |

## 10. Files Off-Limits

| File/Area                                              | Reason                                                                                           |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| `supabase/migrations/*`                                | No schema defect; DB layer is not root cause.                                                    |
| `lib/features/events/events_repository.dart`           | Persists separate fields correctly already.                                                      |
| `lib/features/contacts/widgets/venue_form_screen.dart` | Venue city/state input binding is already correct.                                               |
| `lib/app/models/gig.dart`                              | Display behavior is consistent with normalized data model; root fix belongs in creation mapping. |
| `lib/main.dart`                                        | Guardrail: initialization order must not be touched.                                             |

## 11. System Impact Map

| System                                 | Impact                                           |
| -------------------------------------- | ------------------------------------------------ |
| Gigs                                   | affected                                         |
| Rehearsals                             | unaffected                                       |
| Setlists / Catalog                     | unaffected                                       |
| Members / RBAC                         | unaffected                                       |
| Auth / Session                         | unaffected                                       |
| Routing                                | unaffected                                       |
| Notifications                          | unaffected                                       |
| Platform (iOS / Android / Web / macOS) | affected (shared Flutter event editor code path) |

## 12. Regression Risk

**LOW**

Rationale:

- One-file, one-branch logic correction.
- No backend, schema, auth, or routing changes.
- Behavior change is constrained to gig venue auto-fill for exact single venue match.

## 13. Engineer Task Breakdown

1. Update `_fetchGigNameSuggestions()` in `event_editor_drawer.dart` single-match branch:
   - Replace city+state concatenation with city-only assignment to `_locationController`.
2. Keep existing state auto-fill to `_stateController` unchanged.
3. Confirm no other `_locationController.text = ...` paths inject state.
4. Run analyzer and verify no new warnings/errors introduced by edit.
5. Produce `ENGINEER_REPORT.md` with before/after behavior and exact diff scope.

## 14. Verification Plan

### A. Functional verification (manual)

1. Create a venue with:
   - Name: `Test Venue`
   - City: `Nashville`
   - State: `TN`
2. Open Add Gig drawer, select `Test Venue` by name.
3. Verify pre-save fields:
   - City field shows `Nashville` only.
   - State field shows `TN` only.
4. Save gig.
5. Verify gig card shows city/state correctly (no duplicated state abbreviation).

### B. Regression checks

1. Rehearsal create/edit still unaffected.
2. Gig creation without venue link still works with manual city/state entry.
3. Gig creation with multi-match venue names still requires city disambiguation behavior as before.
4. Edit existing gig and save without changing location/state to confirm no unintended mutation.

### C. Platform checks

Run the same create-flow check on:

- Web (reporter platform)
- One native target (iOS or Android) because code path is shared.

## 15. Rollout / Migration Strategy

- Standard app release only.
- No database migration or edge deployment required.
- No data backfill included in this fix.

## 16. Out of Scope

- Retrofitting previously saved gigs that already contain polluted `location` values.
- Broad normalization/cleanup of historical gig location text.
- Venue model or schema redesign.

## 17. Confidence

**HIGH** — root cause is directly visible in the current venue auto-fill assignment path and matches reported symptom pattern.
