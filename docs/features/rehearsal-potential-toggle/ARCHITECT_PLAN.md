# ARCHITECT_PLAN

## 1) Feature Slug

`feature/rehearsal-potential-toggle`

## 2) Problem Summary

Rehearsals currently cannot be marked as potential in the create/edit flow, and there is no rehearsal-side potential surfacing in the dashboard area where potential gigs appear. Gigs already implement a full `is_potential` pattern (form toggle, persistence, and dashboard surfacing), but rehearsals do not.

## 3) Root Cause

Primary root cause: the rehearsal domain does not carry a potential flag end-to-end.

- Data model gap: `Rehearsal` model has no `isPotential` field and does not parse/emit `is_potential`.
- Form gap: rehearsal create/edit UI has no potential toggle; potential toggle UI exists only in gig form widgets.
- Persistence gap: rehearsal create/update payloads in `EventsRepository` do not write `is_potential`.
- State/dashboard gap: `RehearsalState` does not split potential vs confirmed upcoming rehearsals, and home potential area renders only gig potential cards.
- Schema evidence gap: tracked SQL/migrations/docs contain no rehearsal `is_potential` column addition, and `PROJECT_CONTEXT.md` lists rehearsals without `is_potential`.

Confidence: **MEDIUM**.

Why MEDIUM (not HIGH): client/runtime code evidence is direct and strong, but live DB schema was not directly queried in this session. Repository evidence strongly indicates migration is required.

## 4) Reference Docs Consulted

Required by Architect phase sequence:

- `docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md`
- `docs/reference/notifications/notifications.md`

Note: these are notification-domain docs and are not the primary source for this feature’s rehearsal/gig UI+data behavior.

## 5) Existing System Analysis

### Current data flow (gigs, reference pattern)

- Form toggle lives in gig UI (`GigFormFields`), controlled by `EventEditorDrawer` `_isPotentialGig`.
- `EventFormData` carries `isPotentialGig`.
- `EventsRepository.createGig/updateGig` persist `'is_potential': formData.isPotentialGig`.
- `Gig` model maps `is_potential`.
- `GigController` categorizes upcoming gigs into potential vs confirmed.
- Home dashboard potential area renders potential gig cards at top.

### Current data flow (rehearsals, target)

- Rehearsal UI (`RehearsalFormFields`) has no potential toggle.
- `EventFormData.fromRehearsal()` hardcodes potential false.
- `EventsRepository.createRehearsal/updateRehearsal` do not write `is_potential`.
- `Rehearsal` model has no `is_potential` mapping.
- `RehearsalController` only computes generic upcoming/next rehearsal; no potential partition.
- Home dashboard top potential area is gig-only.

## 6) Proposed Solution

Implement rehearsal potential support by reusing the existing gig potential pattern with minimal extensions:

1. Add rehearsal DB column `is_potential boolean not null default false` via migration.
2. Extend `Rehearsal` model to include `isPotential` (JSON parse + serialization).
3. Extend event form mapping so rehearsal edit/create can carry potential state.
4. Reuse existing potential toggle UI pattern in rehearsal form (shared component extraction if needed to avoid duplication).
5. Persist rehearsal potential in `createRehearsal`, `updateRehearsal`, and recurring child insert/update payloads.
6. Extend rehearsal state categorization to produce potential upcoming rehearsals separately from confirmed upcoming rehearsals.
7. Surface potential rehearsals in the same top dashboard potential area used by potential gigs (same section/zone, no new routing or new architecture layers).
8. Keep push-notification CREATE behavior untouched.

### Must not change

- Notification trigger model (CREATE-only behavior).
- App init/routing (`main.dart`).
- Band scoping model/providers.
- Gig potential availability mechanics (member RSVP logic).

## 7) Database Impact

Database: **affected**.

- Migrations: **required** (add `rehearsals.is_potential`).
- RLS policies on `rehearsals`: **unaffected** (no policy logic currently tied to `is_potential`).
- RPC functions: **unaffected** (no signature changes required).
- Triggers: **unaffected** for this feature scope (notification trigger should continue CREATE-only behavior).

Justification for migration requirement:

- No tracked migration adds `is_potential` to rehearsals.
- Rehearsal schema documentation (`PROJECT_CONTEXT.md`) lacks this column.
- Client currently lacks mapping/persistence and cannot safely assume live schema drift.

## 8) Flutter Architecture Changes

No new architecture layers.

- Existing `EventsRepository`, `EventEditorDrawer`, and feature-first structure remain.
- Existing state providers remain; only extend `RehearsalState` shape and categorization fields.
- Reuse existing potential toggle UI pattern; shared widget extraction is allowed only as a local UI reuse refactor.

## 9) Files to Create

- `supabase/migrations/<timestamp>_add_rehearsal_is_potential.sql`
  - Adds `is_potential BOOLEAN NOT NULL DEFAULT FALSE` on `public.rehearsals`.

Potentially (only if needed to avoid duplication while reusing same toggle UI):

- `lib/features/events/widgets/potential_toggle_card.dart`
  - Shared potential toggle container used by gig and rehearsal form sections.

## 10) Files to Modify

- `lib/app/models/rehearsal.dart`
  - Add `isPotential` field and JSON mapping for `is_potential`.

- `lib/features/events/models/event_form_data.dart`
  - Map rehearsal potential in `fromRehearsal()`.
  - Ensure form payload carries potential flag for rehearsal create/edit.

- `lib/features/events/events_repository.dart`
  - Include `'is_potential'` in rehearsal create/update payloads, including recurring parent/child paths.

- `lib/features/events/widgets/event_editor_drawer.dart`
  - Wire rehearsal potential toggle state in create/edit initialization and save path.

- `lib/features/events/widgets/rehearsal_form_fields.dart`
  - Add potential toggle UI (reusing gig pattern/component).

- `lib/features/events/widgets/gig_form_fields.dart`
  - If shared toggle extraction is used, switch gig form to shared component.

- `lib/features/rehearsals/rehearsal_controller.dart`
  - Add potential/confirmed partitioning for upcoming rehearsals and expose next confirmed rehearsal for existing card.

- `lib/features/home/home_tab_content.dart`
  - Surface potential rehearsals in same top potential area as potential gigs.

- `lib/features/home/home_screen.dart`
  - Apply the same potential-area behavior for parity if this screen path is still active.

- `lib/features/home/widgets/rehearsal_card.dart`
  - Minimal prop/style adjustment only if needed to render a potential rehearsal card variant in the top potential area.

- `lib/features/settings/data_backup_service.dart` (**assessment only; modify only if needed**)
  - Verify export/import compatibility remains intact with new rehearsal column.

## 11) Files Off-Limits

- `lib/main.dart`
  - Routing/init order must not change.

- Any notification edge function files and notification SQL triggers
  - Push CREATE behavior must remain unchanged.

- `lib/features/gigs/gig_response_repository.dart`, `lib/features/gigs/potential_gig_prompt_service.dart`
  - Potential gig RSVP/prompt flow is out of scope.

- Any changes introducing `_lastLoadedBandId` + `Future.microtask` pattern or silent `catch (e) { return []; }`
  - Explicitly forbidden by feature constraints.

## 12) System Impact Map

| System                                 | Impact     |
| -------------------------------------- | ---------- |
| Gigs                                   | unaffected |
| Rehearsals                             | affected   |
| Setlists / Catalog                     | unaffected |
| Members / RBAC                         | unaffected |
| Auth / Session                         | unaffected |
| Routing                                | unaffected |
| Notifications                          | unaffected |
| Platform (iOS / Android / Web / macOS) | affected   |

## 13) Regression Risk

**MEDIUM**.

Rationale:

- Cross-layer change (DB + model + form + state + home dashboard).
- Touches frequently used event editor and home surfaces.
- No auth/routing/init changes, and no new architecture, which keeps risk bounded.

## 14) Engineer Task Breakdown

1. Add DB migration to introduce `public.rehearsals.is_potential BOOLEAN NOT NULL DEFAULT FALSE`.
2. Extend `Rehearsal` model parse/serialize for `is_potential`.
3. Extend form model mapping (`EventFormData`) so rehearsal edit/create carries potential state.
4. Add/reuse potential toggle UI in rehearsal form, matching gig toggle behavior and visuals.
5. Wire toggle state in `EventEditorDrawer` for rehearsal create/edit initialization and save payload generation.
6. Update `EventsRepository` rehearsal create/update + recurring insert/update paths to persist `is_potential`.
7. Extend rehearsal controller state to partition upcoming rehearsals into potential vs confirmed and expose next confirmed rehearsal for existing “Next Rehearsal” card behavior.
8. Update home dashboard potential area to show potential rehearsals alongside potential gigs (same top area/section).
9. Apply parity to `home_screen.dart` if still an active path.
10. Verify backup export/import path behavior; only patch if `is_potential` requires explicit handling.
11. Add/adjust targeted tests (unit/widget where feasible) for rehearsal potential mapping and dashboard surfacing.

## 15) Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

- `-- PRE-DEPLOY TEST 1:` Run Flutter static checks/lints for touched files only (no DB schema dependency).
- `-- PRE-DEPLOY TEST 2:` Unit test `Rehearsal.fromJson/toJson` with synthetic map including `is_potential` (pure Dart).
- `-- PRE-DEPLOY TEST 3:` Widget-level check for rehearsal create/edit form: potential toggle renders and toggles local state.
- `-- PRE-DEPLOY TEST 4:` Verify no notification code paths changed (`git diff` inspection for notification files should be empty).

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

- `-- POST-DEPLOY TEST 1:` Schema verification query confirms column exists:
  - `select column_name, data_type, is_nullable, column_default from information_schema.columns where table_schema='public' and table_name='rehearsals' and column_name='is_potential';`
- `-- POST-DEPLOY TEST 2:` Create rehearsal with toggle ON from app; verify persisted row has `is_potential = true`.
- `-- POST-DEPLOY TEST 3:` Edit same rehearsal and toggle OFF; verify persisted row has `is_potential = false`.
- `-- POST-DEPLOY TEST 4:` Dashboard integration: potential rehearsal appears in top potential area with potential gigs; confirmed rehearsal remains in next-rehearsal lane.
- `-- POST-DEPLOY TEST 5:` Cross-platform smoke on Web/iOS/Android/macOS for create/edit/save/display parity.
- `-- POST-DEPLOY TEST 6:` Production verification query for bad data:
  - `select count(*) from rehearsals where is_potential is null;` expected `0`.

SQL test authoring rules:

- Use transactional rollback for inserted test rows or explicit cleanup deletes in same script.
- If updating existing rows, snapshot and restore original values in all code paths.
- Avoid hardcoded production UUIDs; use generated values unless real FK dependency is required.
- Any test requiring real FK relationships belongs in Tier 2 and must document dependency.

## 16) QA Regression Areas

- Rehearsal create flow: potential toggle visibility, default state, and persistence.
- Rehearsal edit flow: toggle reflects stored value and can be turned off/on.
- Dashboard top potential area: potential rehearsals surface alongside potential gigs.
- Existing next rehearsal card: still shows confirmed rehearsal behavior without duplication conflicts.
- Potential gig behavior unchanged (cards, response summaries, prompt logic).
- Notification behavior unchanged: CREATE-only triggers remain intact for gigs/rehearsals.
- Backup export/import for rehearsals with and without `is_potential` present.
- Platform parity: Web, iOS, Android, macOS.

## 17) Rollout / Migration Strategy

1. Merge migration + app changes together in one release unit.
2. Run Tier 1 before database push.
3. Apply migration via normal Supabase deployment flow.
4. Run Tier 2 verification immediately after push.
5. If migration succeeds but UI issues appear, rollback app release while keeping backward-compatible DB column (safe additive schema).

## 18) Out of Scope

- New notification types/copy for potential rehearsals.
- Any change to gig RSVP semantics or member-availability model.
- Any routing or app initialization changes.
- Broad UI redesign of home cards outside required potential rehearsal surfacing.
