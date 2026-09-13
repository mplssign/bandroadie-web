# ARCHITECT PLAN

## Feature Slug

`feature/add-setlist-to-rehearsal`

## Feature Title

Add a setlist to a rehearsal

## Problem Summary

A user editing or creating a rehearsal cannot associate a setlist with it. The
Add/Edit Event drawer only surfaces the setlist selector inside the gig-only
"Show Details" section; the rehearsal branch of the same drawer renders
Schedule → Location → Notes with no setlist control between them. Every layer
below the drawer (`rehearsals.setlist_id` column, `Rehearsal.setlistId` model
field, `EventFormData.fromRehearsal` factory, `EventsRepository.createRehearsal` /
`updateRehearsal` writes of `setlist_id: formData.setlistId`, and both
rehearsal display sites) is already wired for a setlist association. The only
missing piece is the input control in the rehearsal branch of the drawer.

## Root Cause

**Confidence: HIGH — code-confirmed at every layer.**

In [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L2908-L2977),
`_buildScrollableBody` builds its child list conditionally on `_eventType`. The
gig branch renders a `_SectionCard(title: 'Show Details', child:
_buildShowPrepSection(...))` which in turn calls
`eventFormFields.buildSetlistSelector(context, ref)`. The `else` branch that
handles `EventType.rehearsal` omits this call entirely:

```dart
} else {
  body = Column(
    children: [
      _SectionCard(title: 'Schedule', ...),
      _SectionCard(title: 'Location', ...),
      _SectionCard(title: 'Notes',    ...),
      // no setlist selector
    ],
  );
}
```

Because the rehearsal drawer never mounts the selector, `_selectedSetlistId`
stays `null`, so [`_buildFormData()`](lib/features/events/widgets/event_editor_drawer.dart#L1242)
always emits `setlistId: null` for rehearsals, which is what
`EventsRepository.createRehearsal` and `updateRehearsal` then persist. Nothing
below the drawer is broken — everything expects a value that the UI never
lets the user provide.

Evidence the association is otherwise fully wired:

- **DB column exists.** `rehearsals.setlist_id` is documented in
  [docs/reference/architecture/database_schema.md](docs/reference/architecture/database_schema.md#L44)
  and is referenced by the `delete_setlist` RPC
  ([20260228000000_create_delete_setlist_rpc.sql](supabase/migrations/20260228000000_create_delete_setlist_rpc.sql#L53),
  [20260814120002_restore_setlist_rpc_definitions.sql](supabase/migrations/20260814120002_restore_setlist_rpc_definitions.sql#L160))
  which nulls it out on setlist deletion, and by the demo seeder RPCs
  ([20260904120003_provision_demo_session_rpc.sql](supabase/migrations/20260904120003_provision_demo_session_rpc.sql#L317),
  [20260912122827_demo_relative_date_offsets.sql](supabase/migrations/20260912122827_demo_relative_date_offsets.sql#L418),
  [20260912130000_demo_session_capacity_hardening.sql](supabase/migrations/20260912130000_demo_session_capacity_hardening.sql#L381))
  which all `INSERT INTO rehearsals (..., setlist_id, ...)`.
- **Model field exists.** [lib/app/models/rehearsal.dart](lib/app/models/rehearsal.dart#L22)
  declares `final String? setlistId;`, with
  [fromJson](lib/app/models/rehearsal.dart#L67) reading `setlist_id` and
  [toJson](lib/app/models/rehearsal.dart#L107) writing it.
- **Form-data mapping populates it.**
  [`EventFormData.fromRehearsal`](lib/features/events/models/event_form_data.dart#L658)
  passes `setlistId: rehearsal.setlistId`.
- **Repository writes it on both paths.**
  [createRehearsal](lib/features/events/events_repository.dart#L127),
  [updateRehearsal](lib/features/events/events_repository.dart#L408), and the
  recurring-series update path
  ([`_updateAndGenerateRecurringSeries`](lib/features/events/events_repository.dart#L525-L560))
  all include `'setlist_id': formData.setlistId`.
- **Drawer state already round-trips.**
  [`_selectedSetlistId`](lib/features/events/widgets/event_editor_drawer.dart#L194)
  is declared, [restored in edit mode](lib/features/events/widgets/event_editor_drawer.dart#L301-L302),
  and [emitted from `_buildFormData()`](lib/features/events/widgets/event_editor_drawer.dart#L1242)
  regardless of event type.
- **Rehearsal display sites already read it.**
  [view_rehearsal_drawer.dart](lib/features/rehearsals/widgets/view_rehearsal_drawer.dart#L252)
  looks up the setlist name from `setlistsProvider`, and
  [rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart#L665)
  renders a setlist pill when `rehearsal.setlistId != null`.

Nothing else needs to change. The fix is exclusively adding a `_SectionCard`
that hosts the existing `buildSetlistSelector` in the rehearsal branch of
`_buildScrollableBody`.

## Existing System Analysis

The Add/Edit Event drawer is the single source of truth for creating/editing
both rehearsals and gigs — every entry point (Home, Calendar, view drawers)
routes through `AddEditEventBottomSheet.show` → `EventEditorDrawer`. The
drawer draws one of three body layouts (`gig`, `blockOut`, or the fallthrough
rehearsal `else` branch) inside `_buildScrollableBody`. Section cards are
`_SectionCard` widgets — a lightweight titled container used consistently in
the gig branch (`The Gig`, `Schedule`, `Location`, `Show Details`, `Money`,
`Notes`).

The setlist selector widget itself is `EventFormFields.buildSetlistSelector`
in [event_form_fields.dart](lib/features/events/widgets/event_form_fields.dart#L531):
a horizontally scrolling row of pills sourced from
`ref.watch(setlistsProvider)`, with a leading "None" pill and a
`+ Create Setlist` shortcut when the band has no setlists yet. It is
event-type-agnostic — it takes `selectedSetlistId`, `onSetlistSelected`,
`onNavigateToCreateSetlist`, and standard theme/loading state. The gig branch
today reuses it unchanged.

The nearest product precedent is the gig branch's Show Details card. It
bundles the setlist selector with a gig-only contacts subsection (via
`gigFormFields!.buildContactsSection`), so `_buildShowPrepSection` cannot be
reused as-is for rehearsals — it would drag a non-nullable `gigFormFields`
dependency into a rehearsal build path where `gigFormFields` is `null`.

RLS for rehearsals is defined in
[20260305100000_fix_rehearsal_rls_and_trigger.sql](supabase/migrations/20260305100000_fix_rehearsal_rls_and_trigger.sql):
admins and active members can INSERT / UPDATE / DELETE rehearsals for their
own band; contributors cannot. `setlist_id` is a plain nullable column on the
row and is fully covered by these existing policies. Setting or clearing it
from the client is already allowed by the current UPDATE policy — the demo
seeder RPCs and the gig UI have relied on this for months.

## Proposed Solution

In [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L2949-L2977),
inside the rehearsal fallthrough (`else`) branch of `_buildScrollableBody`,
insert a new titled section card between the Location card and the Notes card:

```dart
_SectionCard(
  title: 'Setlist',
  child: eventFormFields!.buildSetlistSelector(context, ref),
),
const SizedBox(height: 16),
```

`eventFormFields` is already constructed non-null for all non-blockOut event
types (see [line 2887](lib/features/events/widgets/event_editor_drawer.dart#L2887)),
and the gig branch already dereferences it with `!`. Reusing
`buildSetlistSelector` unchanged guarantees the rehearsal picker looks and
behaves identically to the gig picker — same pill styling, same `None` /
`+ Create Setlist` affordances, same integration with `setlistsProvider`.

Because `_selectedSetlistId` / `_selectedSetlistName` are already declared on
the state, already restored from `data.setlistId` / `data.setlistName` in edit
mode, and already emitted from `_buildFormData()` regardless of `_eventType`,
no state, form-data, or repository changes are required. The single UI
insertion completes the round trip.

Do **not** refactor `_buildShowPrepSection`, do **not** rename any provider,
do **not** touch the gig branch, and do **not** add a new setlist provider or
repository method. Everything the selector needs is already provided.

### Section title

Use `'Setlist'` (matching the label used inside `buildSetlistSelector`).
Reusing the gig-side `'Show Details'` title would misrepresent this section
in the rehearsal context — contacts, gig pay, and expenses are not part of
the rehearsal drawer. `'Setlist'` is the smallest accurate label and matches
BandRoadie's existing sentence-case section convention.

## Database Impact

Not applicable. `rehearsals.setlist_id` column, RLS policies, and the
setlist-deletion cascade RPC (`delete_setlist`, which nulls
`rehearsals.setlist_id`) are already in place. No migration, no RPC change,
no RLS change, no policy grant. `has_function_privilege` checks unchanged.

## Flutter Architecture Changes

None. No new provider, controller, repository, model, service, or widget
file. The change is a single UI section insertion in an existing widget's
build method, reusing an existing widget-scoped builder method.

## Files to Create

None. The widget test extends an existing file — see Files to Modify.

## Files to Modify

- [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) —
  In `_buildScrollableBody`, inside the `else` branch (rehearsal layout,
  currently around [lines 2949–2977](lib/features/events/widgets/event_editor_drawer.dart#L2949-L2977)),
  insert a `_SectionCard(title: 'Setlist', child:
  eventFormFields!.buildSetlistSelector(context, ref))` (with the surrounding
  `const SizedBox(height: 16)` spacing) between the Location card and the
  Notes card. No other edits.
- [test/features/events/widgets/event_dropdown_test.dart](test/features/events/widgets/event_dropdown_test.dart) —
  Add one new top-level `group('EventEditorDrawer setlist selector
  (rehearsal)', ...)` alongside the existing `group('EventEditorDrawer
  layout', ...)` at the bottom of the file. This file already imports
  `EventEditorDrawer`, `EventType`, `AppTheme`, `FTheme`, and pumps the
  drawer under a `ProviderScope`, so the new group reuses the existing
  harness. Do **not** rename the file, do **not** move the existing groups,
  and do **not** modify the existing `EventDropdown`, `AppDropdown Form
  integration`, or `EventEditorDrawer layout` groups.

## Files Off-Limits

- Every migration under `supabase/migrations/**` — DB schema already
  supports this.
- `lib/app/models/rehearsal.dart` — model already carries `setlistId`.
- `lib/features/events/events_repository.dart` — already writes `setlist_id`
  on create, update, and recurring-series update paths.
- `lib/features/events/models/event_form_data.dart` — `EventFormData` already
  carries `setlistId` / `setlistName`; `fromRehearsal` already maps
  `rehearsal.setlistId`.
- `lib/features/events/widgets/event_form_fields.dart` — `buildSetlistSelector`
  is reused unchanged.
- `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` — the wrapper
  already forwards `existingEvent` correctly.
- `lib/features/rehearsals/**` — repository / controller / view drawer /
  rehearsal card already read `setlistId` and render the setlist name.
- `lib/features/home/**` — home tab already surfaces the rehearsal setlist
  name in `home_tab_content.dart` and `home_screen.dart`.
- `lib/features/calendar/**` — calendar edit entry points already forward
  through `EventFormData.fromCalendarEvent` → `fromRehearsal`.
- `lib/features/gigs/**` — precedent path; must not regress.
- `lib/features/setlists/**` — provider and picker are reused unchanged.
- Any `--dart-define` config, `main.dart` init order, entitlements,
  `AndroidManifest.xml`, `Podfile`, or platform-conditional code — none of
  these are involved.

## Change Budget

- Expected net line delta:
  - `lib/features/events/widgets/event_editor_drawer.dart`: +5 to +8 lines
    (a single `_SectionCard` block plus a `SizedBox`).
  - `test/features/events/widgets/event_dropdown_test.dart`: +40 to +80
    lines (one new `group` containing the setlist-section test cases plus
    any local stub notifier / helper needed to override `setlistsProvider`).
  - Net repo delta ≤ +90 lines.
- Expected new files: 0. The widget test extends an existing file.
- Expected new public classes / methods: 0. Any test-only stub (e.g. a
  `_StubSetlistsNotifier` in the pattern of `_StubMembersNotifier` in
  [test/features/events/widgets/rehearsal_form_fields_test.dart](test/features/events/widgets/rehearsal_form_fields_test.dart))
  must be a private, file-scoped class inside the test file.
- Expected new dependencies: 0.

## System Impact Map

| System         | Status     | Notes |
| -------------- | ---------- | ----- |
| Gigs           | unaffected | Gig branch of `_buildScrollableBody` is not touched; `_buildShowPrepSection` unchanged. |
| Rehearsals     | affected   | One `_SectionCard` inserted in the rehearsal branch of the Add/Edit Event drawer. |
| Setlists       | unaffected | `setlistsProvider` and `buildSetlistSelector` reused unchanged. |
| Members        | unaffected | No membership or role-gating changes. |
| Auth           | unaffected | No auth flow, PKCE, deep link, or session touch. |
| Routing        | unaffected | No route added, renamed, or reordered. |
| Notifications  | unaffected | `notify_rehearsal_created` and `notify_rehearsal_updated` do not read `setlist_id`; no notification-type change. |
| Platforms      | unaffected | Pure Flutter widget — iOS, Android, macOS, and Web render the same UI. No platform-conditional branches involved. |

## Regression Risk

**LOW.**

- Purely additive UI insertion inside an existing widget's build method.
- No touched code path is shared with auth, session, routing, init order,
  RLS, RPCs, or triggers.
- The rehearsal write path already reads `formData.setlistId` — today it just
  always receives `null` from the drawer. After the change, it receives
  either `null` (user picked "None" or didn't touch the pill row) or a valid
  setlist UUID scoped to the same `band_id` (because `setlistsProvider` is
  itself band-scoped). Both are legal values for the column today and are
  already exercised by the gig write path.
- Edit-mode prefill already round-trips `setlistId` through
  `EventFormData.fromRehearsal` and `_selectedSetlistId`.
- Rehearsal display sites already gracefully handle `setlistId == null` and
  already look up the name from `setlistsProvider` when non-null; no display
  regression is possible from this change.

## Engineer Task Breakdown

1. **Production change (single file:
   [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)).**
   Locate the `else` branch of `_buildScrollableBody` (currently around
   lines 2949–2977 — the rehearsal fallthrough that renders Schedule /
   Location / Notes). Insert immediately after the Location `_SectionCard`
   and its trailing `const SizedBox(height: 16)`, and immediately before
   the Notes `_SectionCard`:
   ```dart
   _SectionCard(
     title: 'Setlist',
     child: eventFormFields!.buildSetlistSelector(context, ref),
   ),
   const SizedBox(height: 16),
   ```
   Within this task, do not modify the gig branch, do not modify
   `_buildShowPrepSection`, do not add any new helper method, and do not
   touch any other production file. (Task 2 modifies a test file, which is
   the only other file this plan authorizes.)

2. **Widget test (single file:
   [test/features/events/widgets/event_dropdown_test.dart](test/features/events/widgets/event_dropdown_test.dart)).**
   Append a new top-level `group('EventEditorDrawer setlist selector
   (rehearsal)', ...)` after the existing `group('EventEditorDrawer
   layout', ...)`. Do not rename the file, do not move or modify the
   existing `EventDropdown`, `AppDropdown Form integration`, or
   `EventEditorDrawer layout` groups, and do not create a new test file.
   The new group must:
   1. Pump `EventEditorDrawer(initialEventType: EventType.rehearsal,
      bandId: 'test-band-id')` inside a `ProviderScope` that overrides
      `setlistsProvider` with a private, file-scoped
      `_StubSetlistsNotifier` returning exactly one non-catalog setlist
      (mirroring the `_StubMembersNotifier` pattern used in
      [test/features/events/widgets/rehearsal_form_fields_test.dart](test/features/events/widgets/rehearsal_form_fields_test.dart)).
      Any additional providers that would otherwise hit Supabase during
      the pump must be stubbed the same way, following that file's
      pattern.
   2. Assert that a widget with the literal text `'Setlist'` (the section
      title inserted in Task 1) is present in the rendered tree when the
      event type is rehearsal.
   3. Assert that tapping the pill for the stubbed setlist updates the
      selection. Verified via whichever of the following is minimally
      sufficient given the drawer's current public surface: (a) tapping
      Save with a fake `EventsRepository` and inspecting the
      `EventFormData.setlistId` it receives, or (b) an existing public
      test hook on the drawer that already exposes the selected setlist
      id. Do not add a new public hook, callback, or `@visibleForTesting`
      member solely to make this assertion possible; if neither (a) nor
      (b) is achievable without a new production surface, stop and
      report back — do not expand the production change.
   4. Assert that tapping the `'None'` pill after step 3 produces a
      selection whose `setlistId` is `null` (using the same observation
      mechanism chosen in step 3).
   Do not add golden files. Do not add integration tests. Do not touch
   any other test file.

## Verification Plan

### Tier 1 — pre-deploy (QA-executable, no running app)

1. `flutter analyze` — no new warnings or errors introduced.
2. `flutter test test/features/events/widgets/event_dropdown_test.dart` —
   the new `EventEditorDrawer setlist selector (rehearsal)` group passes:
   the `'Setlist'` section renders in the rehearsal branch, selecting the
   stubbed setlist's pill produces an `EventFormData` whose `setlistId`
   equals the stubbed setlist's id, and selecting the `'None'` pill
   produces `setlistId: null`. The pre-existing `EventDropdown`,
   `AppDropdown Form integration`, and `EventEditorDrawer layout` groups
   in this file must also still pass unchanged.
3. `flutter test` full suite — no existing test regresses. In particular,
   confirm gig-editor tests (any that assert the Show Details / setlist
   selector in the gig branch) still pass unchanged, because the gig branch
   is not modified.
4. Static SQL / migration review — none required; no migration is added.

### Tier 2 — post-deploy (not applicable)

No migration, no RPC change, no post-deploy verification step.

### Owner-run punch list (Tony, at PR-test / apply time)

QA cannot exercise a running app; hand these to Tony verbatim. Run each on at
least one native platform (macOS or iOS) plus Web to confirm platform parity.

1. Open Home → Add → Rehearsal.
   **Expected:** A "Setlist" section is visible between the Location section
   and the Notes section, showing at least a "None" pill and any existing
   band setlists as pills.
2. Fill in required rehearsal fields (location, date, time). Tap a setlist
   pill (any non-catalog setlist). Save.
   **Expected:** Save succeeds. The rehearsal card on Home shows the selected
   setlist name in the setlist pill.
3. Reopen the same rehearsal via View Rehearsal → Edit.
   **Expected:** The "Setlist" section is present and the previously chosen
   pill is highlighted as selected.
4. Tap the "None" pill. Save.
   **Expected:** Save succeeds. Reopening the rehearsal shows "None"
   selected and the setlist pill disappears from the rehearsal card.
5. In a band that has no setlists yet, open Add → Rehearsal.
   **Expected:** The "Setlist" section shows a "None" pill plus a
   `+ Create Setlist` shortcut (identical to the gig editor's behaviour).
6. Repeat step 2 on Web (bandroadie.com).
   **Expected:** Same visual layout, same save behaviour, same reload
   behaviour — confirms platform parity.
7. Confirm gigs are unchanged: open Add → Gig, verify the "Show Details"
   section still renders the setlist selector plus the contacts subsection.

## QA Regression Areas

- Gig create/edit drawer — must render Show Details section with setlist +
  contacts exactly as before. Covered by any existing gig-editor widget
  tests plus the owner-run step 7.
- Rehearsal create/edit — new setlist section must render, selection must
  round-trip on save/reopen, "None" must clear.
- BlockOut create/edit — must be untouched; the blockOut branch of
  `_buildScrollableBody` is not modified.
- Recurring rehearsal series — `_updateAndGenerateRecurringSeries` already
  writes `setlist_id` on the parent and each child; visually confirm the
  selected setlist applies to the entire generated series.
- `delete_setlist` RPC — already nulls `rehearsals.setlist_id` when the
  chosen setlist is deleted. No change here, but the owner-run list can
  optionally include: create a rehearsal with a setlist → delete the setlist
  → confirm the rehearsal remains and shows no setlist pill.

## Rollout Strategy

- Single PR against `main`.
- No feature flag — the change is a small additive UI element behind
  existing RBAC (contributors already cannot open the edit drawer for
  rehearsals per `_openEditRehearsalSheet` in `home_screen.dart`).
- No migration to apply — deploy is code-only.
- Rollback is a straightforward revert of the two changed files
  (`event_editor_drawer.dart` and the added test group in
  `event_dropdown_test.dart`). Because the underlying `rehearsals.setlist_id`
  column already exists and other paths (demo seeder, gig-side wiring,
  display sites) rely on it, no data cleanup would be needed on rollback.

## Out of Scope

- Any change to `_buildShowPrepSection` or the gig-editor section ordering.
- Any change to how the selected setlist name is looked up for display
  (`view_rehearsal_drawer.dart`, `rehearsal_card.dart`, `home_tab_content.dart`,
  `home_screen.dart`) — these already work.
- Adding a `setlist_name` denormalized column to `rehearsals` or a
  `setlistName` field to the `Rehearsal` model (gigs carry one; rehearsals
  intentionally do not — display sites resolve names via `setlistsProvider`).
- Multi-setlist per rehearsal, setlist ordering across rehearsals, or any
  "recommended setlist" logic.
- Any change to the recurring rehearsal series semantics — existing behavior
  writes the same `setlist_id` to every generated instance and is retained
  as-is.
- Any refactor, rename, dependency bump, or opportunistic cleanup in
  `event_editor_drawer.dart` beyond the single section insertion.
