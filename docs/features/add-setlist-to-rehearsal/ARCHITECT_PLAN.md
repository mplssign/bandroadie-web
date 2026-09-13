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

---

## Cycle 4 Addendum — Dashboard "No Setlist Selected" Badge

### Cycle 4 Feature Input (verbatim)

> add to this: if no setlist is selected, a badge with the label "No Setlist
> Selected" on the rehearsal and gig cards on the dashboard

### Cycle 4 Problem Summary

Dashboard rehearsal and gig cards render no visual cue when an event has no
selected setlist. The confirmed-rehearsal card renders a rose-outlined
selected-setlist pill only when both `rehearsal.setlistId` and `setlistName`
(looked up at the call site from `setlistsProvider`) are non-null; otherwise
that Column slot is empty. The confirmed-gig card, potential-rehearsal card,
and potential-gig card render no setlist-related UI at all. A user glancing
at Home cannot tell whether an event is missing a setlist versus simply not
surfacing one yet, so the "you should pick a setlist" reminder never fires
on any dashboard card.

Cycle 4 adds an outlined "No Setlist Selected" pill to **all four**
dashboard card variants (confirmed rehearsal, potential rehearsal, confirmed
gig, potential gig) when their authoritative setlist association is absent.
The pill matches the visual language of the confirmed rehearsal card's
existing selected pill (same 32px height, same `Spacing.chipRadius`, same
`AppTextStyles.footnote` w600 typography) in a muted white-alpha color
scheme so "empty" reads as distinct from "actively selected". Confirmed
variants render the pill left-aligned via `IntrinsicWidth` +
`Alignment.centerLeft`; potential variants render it centered (via a
`Center` wrapper) to match their surrounding centered content layout.

### Cycle 4 Root Cause

**Confidence: HIGH — code-confirmed at all four render sites.**

- [lib/features/home/widgets/rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart#L665-L694)
  (`_buildConfirmedCard`) gates the existing selected-setlist pill on
  `widget.rehearsal.setlistId != null && widget.setlistName != null` inside
  a spread with no `else` branch. When the gate fails for any reason, that
  Column slot renders nothing.
- [lib/features/home/widgets/rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart#L314-L482)
  (`_buildPotentialCard`) renders chip → date → time → location → `Spacer()`
  → button row and never references `widget.rehearsal.setlistId` or
  `widget.setlistName`. No setlist-related child exists.
- [lib/features/home/widgets/confirmed_gig_card.dart](lib/features/home/widgets/confirmed_gig_card.dart#L52-L125)
  ends its Column with the Time widget — no setlist-related child at all.
- [lib/features/home/widgets/potential_gig_card.dart](lib/features/home/widgets/potential_gig_card.dart#L300-L462)
  (`PotentialGigCard.build`) renders chip → date → time → venue+city →
  `Spacer()` → button row and never references `widget.gig.setlistId` or
  `widget.gig.setlistName`. No setlist-related child exists.

All four are pure rendering omissions in dashboard widgets. Every input
required to make the "no setlist" decision is already present in each card's
props: both `RehearsalCard` branches receive `rehearsal` (whose `setlistId`
is authoritative) and the caller-resolved `setlistName`; both gig cards
receive `gig` (whose `setlistId` is authoritative and whose `setlistName` is
denormalized in the same row). No repository, provider, controller, or
model change is required for any variant.

**Authoritative no-selection signal (per model/variant):**

- `RehearsalCard._buildConfirmedCard`: `widget.rehearsal.setlistId == null`.
  Rehearsal has no denormalized name column; the id is the only source of
  truth. The `setlistName` prop is a caller-resolved provider lookup and
  can be `null` while its provider is still loading even when a setlist is
  in fact selected — gating on `setlistName == null` would produce a
  false-negative "No Setlist Selected" badge during that race.
- `RehearsalCard._buildPotentialCard`: same — `widget.rehearsal.setlistId
  == null`. Both call sites
  ([home_screen.dart:837](lib/features/home/home_screen.dart#L837),
  [home_tab_content.dart:1141](lib/features/home/home_tab_content.dart#L1141))
  resolve `setlistName` from `setlistsProvider` and pass it into the same
  `RehearsalCard`, so the identical loading-race concern applies to the
  potential branch even though the potential branch does not render the
  name today.
- `ConfirmedGigCard`: `widget.gig.setlistId == null`. `Gig.setlistName` is
  denormalized on the row and loaded with the gig, so there is no
  loading-race concern; however `delete_setlist`
  ([20260228000000_create_delete_setlist_rpc.sql:49-51](supabase/migrations/20260228000000_create_delete_setlist_rpc.sql#L49-L51))
  nulls `gigs.setlist_id` without touching `gigs.setlist_name`, so
  `setlistName` can be a stale non-null string when `setlistId` is
  authoritatively `null` — the id is the correct signal.
- `PotentialGigCard`: same — `widget.gig.setlistId == null`. The stale-name
  cascade behavior applies identically; the id is authoritative.

### Cycle 4 Design Decision — Scope

Cycle 4 applies to **all four dashboard card variants** — both confirmed
and both potential rehearsal/gig cards on the Home dashboard:

- `RehearsalCard._buildConfirmedCard` (near
  [rehearsal_card.dart:583](lib/features/home/widgets/rehearsal_card.dart#L583)).
- `RehearsalCard._buildPotentialCard` (near
  [rehearsal_card.dart:314](lib/features/home/widgets/rehearsal_card.dart#L314)).
- `ConfirmedGigCard`
  ([confirmed_gig_card.dart](lib/features/home/widgets/confirmed_gig_card.dart)).
- `PotentialGigCard`
  ([potential_gig_card.dart](lib/features/home/widgets/potential_gig_card.dart)).

Tony's Cycle 4 wording — "a badge with the label 'No Setlist Selected' on
the rehearsal and gig cards on the dashboard" — reads literally: potential
rehearsals and potential gigs *are* rehearsal/gig cards on the dashboard.
Narrowing to confirmed-only is unsupported by that wording, so every
dashboard rehearsal/gig card variant shows the identical `No Setlist
Selected` badge when — and only when — its authoritative setlist
association is absent.

This addendum treats "dashboard" strictly as the Home surface
(`home_screen.dart` / `home_tab_content.dart`). Non-dashboard surfaces
(view drawers, editor drawer, calendar views) remain out of scope.

### Cycle 4 Existing System Analysis

**Confirmed rehearsal card, existing selected pill** (the "existing badge"
the request retains) —
[rehearsal_card.dart:665-694](lib/features/home/widgets/rehearsal_card.dart#L665-L694):

- Container: 32px height, transparent background, `Spacing.chipRadius` (16px)
  corners, `AppColors.primary` (rose `#FF2056`) 1.5px border, `IntrinsicWidth`,
  `Alignment.centerLeft`.
- Padding: `EdgeInsets.symmetric(horizontal: 12)`.
- Text: `AppTextStyles.footnote.copyWith(color: Colors.white, fontWeight:
  FontWeight.w600)`, `maxLines: 1`, `overflow: TextOverflow.ellipsis`.
- Positioned in the bottom Location + Setlist Column, gated on both
  `widget.rehearsal.setlistId != null` and `widget.setlistName != null`.

**Potential rehearsal card structure** —
[rehearsal_card.dart:314-482](lib/features/home/widgets/rehearsal_card.dart#L314-L482)
(`_buildPotentialCard`):

- Outer `Padding(all: 16)` → `Column(mainAxisSize: MainAxisSize.min)` with
  children in order: full-width chip label ("POTENTIAL REHEARSAL"),
  `SizedBox(height: 16)`, `AnimatedDateLabel` (date), `SizedBox(height: 8)`,
  `AnimatedDateLabel` (time), `SizedBox(height: 12)`, centered Location
  `Text`, `Spacer()`, then the availability button row (with optional
  left/right date-navigation chevrons for multi-date).
- Content is centered (Location `Text` uses `textAlign: TextAlign.center`;
  date/time animated labels are visually centered by their parent). The
  `Spacer()` pushes the button row to the bottom of a `minHeight:
  Spacing.potentialGigCardHeight` box.
- Reads only `widget.rehearsal.*` and `widget.additionalDates`; does not
  read `widget.setlistName` today, but the prop is still passed in by
  both call sites
  ([home_screen.dart:837](lib/features/home/home_screen.dart#L837),
  [home_tab_content.dart:1141](lib/features/home/home_tab_content.dart#L1141))
  via the shared `RehearsalCard` constructor.

**Confirmed gig card structure** —
[confirmed_gig_card.dart:52-125](lib/features/home/widgets/confirmed_gig_card.dart#L52-L125):

- `AppCard` → `Container` (min 200, max 400 width) → `Column`
  (`crossAxisAlignment: start`, `mainAxisSize: min`).
- Children, in order: Title (`AppTextStyles.title3`), Location, Date, Time.
- No existing setlist child. `Spacing`, `AppTextStyles`, `AppFontSizes`, and
  `IntrinsicWidth` are already imported through the existing imports of
  `design_tokens.dart` and Flutter Material.

**Potential gig card structure** —
[potential_gig_card.dart:300-462](lib/features/home/widgets/potential_gig_card.dart#L300-L462)
(`PotentialGigCard.build`):

- Outer `Padding(all: 16)` → `Column(mainAxisSize: MainAxisSize.min)` with
  children in order: full-width chip label ("POTENTIAL GIG"),
  `SizedBox(height: 16)`, `AnimatedDateLabel` (date), `SizedBox(height: 8)`,
  `AnimatedDateLabel` (time), `SizedBox(height: 12)`, centered venue+city
  `Row(mainAxisAlignment: center)`, `Spacer()`, then the availability
  button row (with optional left/right date-navigation chevrons for
  multi-date).
- Content is centered; layout mirrors `RehearsalCard._buildPotentialCard`
  aside from potential-gig-specific chip text and venue+city
  presentation. `Spacing`, `AppTextStyles`, `AppFontSizes`, and
  `IntrinsicWidth` are already imported.
- Reads `widget.gig.setlistId` and `widget.gig.setlistName` are both
  available on the model even though the current build method references
  neither.

**Setlist-name resolution paths** (already present, unchanged by Cycle 4):

- Rehearsal cards (both variants): callers
  ([home_screen.dart:827-836](lib/features/home/home_screen.dart#L827-L836),
  [home_tab_content.dart:1132-1136](lib/features/home/home_tab_content.dart#L1132-L1136),
  [home_tab_content.dart:1248-1253](lib/features/home/home_tab_content.dart#L1248-L1253))
  look up `setlistName` from `setlistsProvider` state and pass it in as a
  prop. When `setlistId != null` but the setlist row isn't in provider
  state yet (initial cold load, permission-filtered out, or a deletion
  cascade race), `setlistName` stays `null`. This loading-race concern
  applies identically to the potential rehearsal branch even though it
  never renders the name today.
- Gig cards (both variants): `Gig.setlistName` is denormalized in the
  `gigs` row
  ([gig.dart:31](lib/app/models/gig.dart#L31)). On write,
  [events_repository.dart:711](lib/features/events/events_repository.dart#L711)
  persists `setlist_id` and `setlist_name` together. On setlist deletion,
  the `delete_setlist` RPC
  ([20260228000000_create_delete_setlist_rpc.sql:49-51](supabase/migrations/20260228000000_create_delete_setlist_rpc.sql#L49-L51))
  nulls `gigs.setlist_id` but does **not** null `gigs.setlist_name`, so
  after deletion a gig can carry `setlistId: null` with a stale
  `setlistName`. That pre-existing data-drift is not fixed by Cycle 4 and
  informs the gate choice below (id-only).

**Nearest widget-test coverage**: none. There are zero existing tests
targeting `RehearsalCard`, `ConfirmedGigCard`, or `PotentialGigCard` — a
codebase-wide grep for these class names returned only their source and
usage sites, no test files under `test/features/home/`. Cycle 4 introduces
the first `test/features/home/widgets/` test file, extended in this
addendum revision to cover the two potential variants as well.

### Cycle 4 Proposed Solution

Insert a muted "No Setlist Selected" pill in each of the four dashboard
card variants when — and only when — the variant's authoritative setlist
id is `null`. The pill's *visual* definition is byte-identical across all
four variants (same 32px height, `Spacing.chipRadius`, 1.5px white
40%-alpha border, transparent background, `AppTextStyles.footnote` w600 at
75% white alpha, 12px horizontal padding, `maxLines: 1` + ellipsis).
Alignment differs per variant to fit the surrounding Column: confirmed
cards render the pill left-aligned via `IntrinsicWidth` +
`Alignment.centerLeft` inside their `crossAxisAlignment: start` Columns;
potential cards render the pill centered via a `Center` wrapper inside
their default-aligned Columns to match the existing centered chip / date /
time / location content above the `Spacer()`.

**Confirmed rehearsal card** — inside `_buildConfirmedCard`
([rehearsal_card.dart:596](lib/features/home/widgets/rehearsal_card.dart#L596)),
extend the existing selected-pill spread at
[lines 665-694](lib/features/home/widgets/rehearsal_card.dart#L665-L694)
with an `else if` for the "no selection" case. The `else if` gate is
deliberately narrower than a plain `else`:

```dart
if (widget.rehearsal.setlistId != null &&
    widget.setlistName != null) ...[
  // existing rose selected-setlist pill — UNCHANGED
] else if (widget.rehearsal.setlistId == null) ...[
  const SizedBox(height: 8),
  IntrinsicWidth(
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Spacing.chipRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        'No Setlist Selected',
        style: AppTextStyles.footnote.copyWith(
          color: Colors.white.withValues(alpha: 0.75),
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ),
],
```

The `else if (widget.rehearsal.setlistId == null)` gate is intentional:
when `setlistId != null && setlistName == null` (setlists provider still
loading, setlist deleted from another band-scoped path, or setlist
filtered out of local state), neither branch renders — preserving today's
"hide during load" behavior so no user is ever falsely told a
present-setlist event has no setlist.

**Potential rehearsal card** — inside `_buildPotentialCard`
([rehearsal_card.dart:314-482](lib/features/home/widgets/rehearsal_card.dart#L314-L482)),
insert a new `if (widget.rehearsal.setlistId == null) ...[]` spread
between the centered Location `Text` and the `Spacer()` that anchors the
button row. The spread must render the muted pill wrapped in `Center` so
it visually centers within the potential-card Column like the other
content above the `Spacer()`:

```dart
Text( // existing centered Location text, unchanged
  widget.rehearsal.location.isNotEmpty
      ? widget.rehearsal.location
      : 'No location specified',
  textAlign: TextAlign.center,
  // ...
),

if (widget.rehearsal.setlistId == null) ...[
  const SizedBox(height: 12),
  Center(
    child: IntrinsicWidth(
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(Spacing.chipRadius),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          'No Setlist Selected',
          style: AppTextStyles.footnote.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  ),
],

const Spacer(), // unchanged
```

Gate strictly on `widget.rehearsal.setlistId == null` — never on
`widget.setlistName == null`. Reason: the potential branch's `setlistName`
prop is subject to the identical `setlistsProvider` loading race as the
confirmed branch (both call sites resolve the same way). Gating on the id
suppresses the badge whenever a setlist is in fact selected, regardless
of whether the name has resolved yet.

**Confirmed gig card** — append a new Column child after the Time widget
in `ConfirmedGigCard.build` (the Time widget currently ends near
[confirmed_gig_card.dart:123](lib/features/home/widgets/confirmed_gig_card.dart#L123)):

```dart
// Time — unchanged
Text( /* ... */ ),

if (widget.gig.setlistId == null) ...[
  const SizedBox(height: 8),
  IntrinsicWidth(
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Spacing.chipRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        'No Setlist Selected',
        style: AppTextStyles.footnote.copyWith(
          color: Colors.white.withValues(alpha: 0.75),
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ),
],
```

**Potential gig card** — inside `PotentialGigCard.build`
([potential_gig_card.dart:300-462](lib/features/home/widgets/potential_gig_card.dart#L300-L462)),
insert a new `if (widget.gig.setlistId == null) ...[]` spread between the
centered venue+city `Row` and the `Spacer()` that anchors the button row.
Mirror the potential-rehearsal `Center`-wrapped pattern:

```dart
Row( // existing centered venue + city row, unchanged
  mainAxisAlignment: MainAxisAlignment.center,
  children: [ /* ... */ ],
),

if (widget.gig.setlistId == null) ...[
  const SizedBox(height: 12),
  Center(
    child: IntrinsicWidth(
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(Spacing.chipRadius),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          'No Setlist Selected',
          style: AppTextStyles.footnote.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  ),
],

const Spacer(), // unchanged
```

Gate exclusively on `widget.gig.setlistId == null` in both gig variants —
never on `gig.setlistName == null`. Reason: `delete_setlist` RPC nulls
`gigs.setlist_id` without touching `gigs.setlist_name`, so `setlistName`
can be stale while `setlistId` is null. The id is the authoritative "no
selection" signal in both gig variants.

**Do not extract a shared `_NoSetlistBadge` widget for Cycle 4.** The
Cycle 3 baseline explicitly chose inlined pill blocks over a shared
widget on the reasoning that two inlined insertions using the same
design-token primitives were proportional. Expanding to four inlined
insertions raises the duplication cost but does not clear the request's
higher bar: "avoid a shared abstraction unless concrete duplication
across all four variants justifies one under existing local patterns".
Evaluating that bar concretely: the pill is pure style with no logic;
every style value is either a design token (`Spacing.chipRadius`,
`AppTextStyles.footnote`) or a literal alpha (0.4, 0.75) also used in
other dashboard chrome; the four sites live in three files all under
`lib/features/home/widgets/`, so drift is easy to catch in review;
and extracting to either a new file or a public class in an existing
card file introduces a one-off cross-file coupling for a ~20-line
container. The line savings of extraction (~30–40 net) do not clear
that cost. If a future cycle expands the badge to non-dashboard
surfaces (view drawers, calendar cards), extraction should be revisited
then with the wider footprint as new justification.

### Cycle 4 Loading / Unknown-State Handling

**Confirmed rehearsal card render truth table (post-Cycle 4):**

| `rehearsal.setlistId` | `setlistName` prop | Renders |
| --------------------- | ------------------ | ------- |
| non-null | non-null | existing rose selected-setlist pill (unchanged) |
| non-null | `null` (loading / filtered / cascade race) | nothing (unchanged — preserved) |
| `null` | (any) | new muted "No Setlist Selected" pill |

**Potential rehearsal card render truth table (post-Cycle 4):**

| `rehearsal.setlistId` | `setlistName` prop | Renders (setlist slot) |
| --------------------- | ------------------ | ---------------------- |
| non-null | non-null | nothing (unchanged — potential branch has no existing selected-setlist affordance) |
| non-null | `null` (loading / filtered / cascade race) | nothing (loading-race preservation — identical rationale to confirmed) |
| `null` | (any) | new muted "No Setlist Selected" pill (centered) |

**Confirmed gig card render truth table (post-Cycle 4):**

| `gig.setlistId` | Renders |
| --------------- | ------- |
| non-null | nothing (unchanged — no existing setlist affordance on confirmed gig card) |
| `null` | new muted "No Setlist Selected" pill |

**Potential gig card render truth table (post-Cycle 4):**

| `gig.setlistId` | Renders (setlist slot) |
| --------------- | ---------------------- |
| non-null | nothing (unchanged — no existing setlist affordance on potential gig card) |
| `null` | new muted "No Setlist Selected" pill (centered) |

### Cycle 4 Database Impact

n/a. No column, RLS policy, RPC, trigger, grant, or index change.
`gigs.setlist_id`, `gigs.setlist_name`, `rehearsals.setlist_id`, and the
`setlistsProvider` query are all already in place. Cycle 4 adds no new
`SECURITY DEFINER` function, so no new `has_function_privilege` check is
required.

### Cycle 4 Flutter Architecture Changes

None. No new provider, controller, repository, model, service, or shared
widget file. Four additive inline UI blocks inside three existing dashboard
card widgets, plus one new widget-test file.

### Cycle 4 Files to Create

- [test/features/home/widgets/dashboard_no_setlist_badge_test.dart](test/features/home/widgets/dashboard_no_setlist_badge_test.dart)
  — new pure widget-test file with four top-level groups (one per
  variant); see Cycle 4 Engineer Task Breakdown, Task 5.

### Cycle 4 Files to Modify

- [lib/features/home/widgets/rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart)
  — two additive insertions in this file:
  1. Inside `_buildConfirmedCard`, extend the existing selected-pill
     `if (widget.rehearsal.setlistId != null && widget.setlistName !=
     null) ...[]` spread at
     [lines 665-694](lib/features/home/widgets/rehearsal_card.dart#L665-L694)
     with an `else if (widget.rehearsal.setlistId == null) ...[]` branch
     that renders the muted pill exactly as specified in Cycle 4
     Proposed Solution (left-aligned via `IntrinsicWidth` +
     `Alignment.centerLeft`, matching the existing rose pill). Do not
     touch the existing rose selected-pill branch, do not modify
     `_truncatedSetlistName` or any formatter, and do not reorder or
     rename any Column child.
  2. Inside `_buildPotentialCard`, insert a new `if
     (widget.rehearsal.setlistId == null) ...[]` spread between the
     centered Location `Text` (currently at [lines
     460-475](lib/features/home/widgets/rehearsal_card.dart#L460-L475))
     and the following `const Spacer()`. The spread must wrap the muted
     pill in `Center(child: IntrinsicWidth(...))` so it centers within
     the potential-card Column (matching the surrounding centered
     chip / date / time / location content). Do not modify chip label,
     `AnimatedDateLabel` widgets, Location, `Spacer`, or the button row.
  Do not add new imports (all required primitives are already imported).
- [lib/features/home/widgets/confirmed_gig_card.dart](lib/features/home/widgets/confirmed_gig_card.dart)
  — append a new `if (widget.gig.setlistId == null) ...[]` block as the
  final Column child, immediately after the existing Time widget ending
  near
  [line 123](lib/features/home/widgets/confirmed_gig_card.dart#L123),
  rendering the muted pill exactly as specified in Cycle 4 Proposed
  Solution (left-aligned via `IntrinsicWidth` + `Alignment.centerLeft`).
  Do not modify the existing Title / Location / Date / Time children, do
  not modify `_formatFullDate`, and do not add new imports (`Spacing`,
  `AppTextStyles`, and `IntrinsicWidth` are already available).
- [lib/features/home/widgets/potential_gig_card.dart](lib/features/home/widgets/potential_gig_card.dart)
  — inside `PotentialGigCard.build`, insert a new `if
  (widget.gig.setlistId == null) ...[]` spread between the centered venue
  + city `Row` (currently at [lines
  438-479](lib/features/home/widgets/potential_gig_card.dart#L438-L479),
  ending with the closing bracket of that `Row`'s children) and the
  following `const Spacer()`. Wrap the pill in `Center(child:
  IntrinsicWidth(...))` to center within the Column, exactly matching
  the potential-rehearsal insertion above. Do not modify chip label,
  `AnimatedDateLabel` widgets, venue+city Row, `Spacer`, button row,
  `_DateNavButton`, `PotentialChip`, or `AnimatedDateLabel`. Do not add
  new imports (`Spacing`, `AppTextStyles`, and `IntrinsicWidth` are
  already available).

### Cycle 4 Files Off-Limits

- [lib/features/home/home_screen.dart](lib/features/home/home_screen.dart)
  and [lib/features/home/home_tab_content.dart](lib/features/home/home_tab_content.dart)
  — call sites already pass every prop each card needs; Cycle 4 does
  not modify any call site.
- [lib/features/rehearsals/widgets/view_rehearsal_drawer.dart](lib/features/rehearsals/widgets/view_rehearsal_drawer.dart),
  [lib/features/gigs/widgets/view_gig_drawer.dart](lib/features/gigs/widgets/view_gig_drawer.dart),
  and [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
  — view/editor drawers, out of Cycle 4 scope per user constraint
  (dashboard-only).
- `lib/features/calendar/**` — not a dashboard surface.
- [lib/app/models/gig.dart](lib/app/models/gig.dart),
  [lib/app/models/rehearsal.dart](lib/app/models/rehearsal.dart),
  [lib/features/events/events_repository.dart](lib/features/events/events_repository.dart),
  [lib/features/events/models/event_form_data.dart](lib/features/events/models/event_form_data.dart)
  — no model / repository / form-data change. Cycle 4 uses props already
  flowing.
- Every method in
  [lib/features/home/widgets/rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart)
  other than the specific insertion points inside `_buildConfirmedCard`
  and `_buildPotentialCard` — no formatter, animation controller, focus
  node, response-handler, or unrelated child touched.
- Every method in
  [lib/features/home/widgets/potential_gig_card.dart](lib/features/home/widgets/potential_gig_card.dart)
  other than the specific insertion point inside `PotentialGigCard.build`
  — do not modify `_handleResponse`, `_handleKeyEvent`, `_formatFullDate`,
  `_DateNavButton`, `PotentialChip`, `AnimatedDateLabel`,
  `_FullWidthAvailabilityButton`, animation controller, or focus nodes.
- All Cycles 1–3 Files Off-Limits (see main Files Off-Limits section above).
- Every migration under `supabase/migrations/**`, every edge function under
  `supabase/functions/**`, all platform config, entitlements, `Podfile`,
  `AndroidManifest.xml`, and `main.dart` init order.
- [docs/features/add-setlist-to-rehearsal/QA_REPORT.md](docs/features/add-setlist-to-rehearsal/QA_REPORT.md)
  and [docs/features/add-setlist-to-rehearsal/PR_BODY.md](docs/features/add-setlist-to-rehearsal/PR_BODY.md)
  — Tony's uncommitted formatter-only edits must be preserved as-is;
  Cycle 4 does not overwrite them.

### Cycle 4 Change Budget

- [lib/features/home/widgets/rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart):
  +50 to +70 lines net (one `else if ...[]` spread in `_buildConfirmedCard`
  mirroring the existing selected-pill spread, plus one `if ...[]`
  spread in `_buildPotentialCard` wrapped in `Center` for the centered
  layout; no lines removed).
- [lib/features/home/widgets/confirmed_gig_card.dart](lib/features/home/widgets/confirmed_gig_card.dart):
  +25 to +35 lines net (one `if ...[]` spread appended inside the existing
  Column; no lines removed).
- [lib/features/home/widgets/potential_gig_card.dart](lib/features/home/widgets/potential_gig_card.dart):
  +25 to +35 lines net (one `if ...[]` spread inserted between venue+city
  Row and Spacer, wrapped in `Center`; no lines removed).
- [test/features/home/widgets/dashboard_no_setlist_badge_test.dart](test/features/home/widgets/dashboard_no_setlist_badge_test.dart):
  new file, expected +200 to +320 lines (four top-level groups — confirmed
  rehearsal, potential rehearsal, confirmed gig, potential gig — with
  private file-scoped fixture builders for `Rehearsal` (both
  `isPotential` values) and `Gig` (both `isPotential` values)).
- Cycle 4 net repo delta ≤ +460 lines.
- Expected new files: 1 (the widget test).
- Expected new public classes / methods: 0. Any fixture builder must be a
  private, file-scoped helper.
- Expected new dependencies: 0.

### Cycle 4 System Impact Map

| System | Status | Notes |
| ------ | ------ | ----- |
| Gigs | affected (dashboard render only) | Both `ConfirmedGigCard` and `PotentialGigCard` gain a "No Setlist Selected" pill when `gig.setlistId == null`. No repository / model / query change. View gig drawer and edit gig drawer unchanged. |
| Rehearsals | affected (dashboard render only) | `RehearsalCard._buildConfirmedCard` gains an `else if` branch for the "no selection" case (existing selected pill unchanged), and `RehearsalCard._buildPotentialCard` gains a new `if` branch for the same. View / edit drawers unchanged. |
| Setlists | unaffected | `setlistsProvider` and every setlist RPC/route unchanged. |
| Members | unaffected | No membership or role-gating changes. |
| Auth | unaffected | No auth, PKCE, deep link, or session touch. |
| Routing | unaffected | No route added, renamed, or reordered. |
| Notifications | unaffected | No notification type, payload, or scheduling change. |
| Platforms | unaffected | Pure Flutter widget code; iOS, Android, macOS, Web render identically. No platform-conditional branches involved. |

### Cycle 4 Regression Risk

**LOW.**

- Purely additive UI insertions inside three existing widgets (four total
  insertion points across three files).
- No touched code path shares state, session, routing, init order, RLS,
  RPCs, triggers, notifications, or platform-conditional code.
- The pre-existing rose selected-pill rendering (the only dashboard
  setlist affordance before Cycle 4) is left byte-identical; the new
  muted confirmed-rehearsal pill lives in a new `else if` branch that
  only activates when `setlistId == null`.
- The potential-variant insertions add a new centered pill between
  existing centered content and the `Spacer()` — they cannot displace
  the button row (Spacer absorbs the extra height while `AppCard` grows
  from `minHeight`) and cannot regress the RSVP surface, keyboard
  navigation, date navigation, or animation controllers.
- No provider, model, or repository change means every existing
  integration and widget test remains unaffected.
- Every gate uses `setlistId == null` — the authoritative signal in each
  model — so no dashboard variant ever regresses to showing a false
  "No Setlist Selected" while a name resolves (rehearsal side) or
  displays stale name after `delete_setlist` cascade (gig side).

### Cycle 4 Engineer Task Breakdown

1. **Confirmed rehearsal card production change** (single file:
   [lib/features/home/widgets/rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart)).
   Inside `_buildConfirmedCard`, locate the existing selected-setlist
   spread at
   [lines 665-694](lib/features/home/widgets/rehearsal_card.dart#L665-L694).
   Append an `else if (widget.rehearsal.setlistId == null) ...[]` spread
   immediately after that block (before the closing `]` of the enclosing
   Column's `children:` list), containing the muted "No Setlist Selected"
   pill exactly as specified in Cycle 4 Proposed Solution
   (left-aligned via `IntrinsicWidth` + `Alignment.centerLeft`). Do not
   modify the existing selected-pill branch, do not touch
   `_buildPotentialCard` (Task 2 covers it), and do not modify any
   formatter, animation controller, focus node, or unrelated child. Do
   not add new imports.

2. **Potential rehearsal card production change** (same file:
   [lib/features/home/widgets/rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart)).
   Inside `_buildPotentialCard`, locate the centered Location `Text`
   (currently at
   [lines 460-475](lib/features/home/widgets/rehearsal_card.dart#L460-L475))
   and the `const Spacer()` that immediately follows it. Insert an
   `if (widget.rehearsal.setlistId == null) ...[]` spread between the
   Location `Text` and the `Spacer()`, containing:
   - `const SizedBox(height: 12)`,
   - `Center(child: IntrinsicWidth(child: Container(...))` rendering the
     muted pill exactly as specified in Cycle 4 Proposed Solution.
   Do not modify the existing chip label, date/time `AnimatedDateLabel`
   widgets, Location `Text`, `Spacer`, availability button row,
   `_RehearsalDateNavButton`, `_FullWidthAvailabilityButton`, pulse
   controller, focus nodes, or the potential-branch `AnimatedBuilder`.
   Do not add new imports.

3. **Confirmed gig card production change** (single file:
   [lib/features/home/widgets/confirmed_gig_card.dart](lib/features/home/widgets/confirmed_gig_card.dart)).
   Inside `ConfirmedGigCard.build`, locate the Time widget (currently the
   last child of the Column ending near
   [line 123](lib/features/home/widgets/confirmed_gig_card.dart#L123)).
   Append an `if (widget.gig.setlistId == null) ...[]` spread as the
   final Column child (after Time, before the closing `]` of `children:`),
   containing the muted "No Setlist Selected" pill exactly as specified
   in Cycle 4 Proposed Solution (left-aligned via `IntrinsicWidth` +
   `Alignment.centerLeft`). Do not modify the existing Title, Location,
   Date, or Time children. Do not add new imports.

4. **Potential gig card production change** (single file:
   [lib/features/home/widgets/potential_gig_card.dart](lib/features/home/widgets/potential_gig_card.dart)).
   Inside `PotentialGigCard.build`, locate the centered venue+city `Row`
   (currently at
   [lines 438-479](lib/features/home/widgets/potential_gig_card.dart#L438-L479))
   and the `const Spacer()` that immediately follows it. Insert an
   `if (widget.gig.setlistId == null) ...[]` spread between the venue
   +city `Row` and the `Spacer()`, containing:
   - `const SizedBox(height: 12)`,
   - `Center(child: IntrinsicWidth(child: Container(...))` rendering the
     muted pill exactly as specified in Cycle 4 Proposed Solution.
   Do not modify the existing chip label, date/time `AnimatedDateLabel`
   widgets, venue+city Row, `Spacer`, availability button row,
   `_DateNavButton`, `_FullWidthAvailabilityButton`, pulse controller,
   focus nodes, or the `AnimatedBuilder`. Do not add new imports. Do not
   modify `PotentialChip` or `AnimatedDateLabel`.

5. **Widget test** (single new file:
   [test/features/home/widgets/dashboard_no_setlist_badge_test.dart](test/features/home/widgets/dashboard_no_setlist_badge_test.dart)).
   Create the file with:
   1. Private file-scoped fixture builders for `Rehearsal` and `Gig`.
      Each builder takes `isPotential`, `setlistId`, and (for `Gig`)
      `setlistName` as named parameters and populates every other
      required field with fixed test values:
      - `_buildRehearsal({required bool isPotential, String? setlistId})`
        — uses `additionalDates: const []` (Rehearsal model default),
        fixed `startTime` / `endTime` / `location` / `date` /
        `bandId` / `id`, `notes: null`, `isRecurring: false`.
      - `_buildGig({required bool isPotential, String? setlistId,
        String? setlistName})` — uses `additionalDates: const []`,
        `contacts: const []`, `requiredMemberIds: const <String>{}`,
        fixed `name` / `date` / `startTime` / `endTime` / `location` /
        `bandId` / `id`.
   2. `group('RehearsalCard confirmed No Setlist Selected badge',
      ...)` with three `testWidgets` cases, each pumping the card under
      `MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body:
      RehearsalCard(...)))` — no `ProviderScope` needed because the card
      takes `setlistName` as a prop:
      1. `renders "No Setlist Selected" when rehearsal.setlistId is
         null` — pump with `_buildRehearsal(isPotential: false,
         setlistId: null)` and `setlistName: null`; assert
         `find.text('No Setlist Selected')` finds one widget.
      2. `renders existing selected pill and no "No Setlist Selected"
         when both id and name are non-null` — pump with
         `_buildRehearsal(isPotential: false, setlistId: 'setlist-1')`
         and `setlistName: 'Road Set'`; assert `find.text('Road Set')`
         finds one widget and `find.text('No Setlist Selected')` finds
         zero.
      3. `renders neither pill when setlistId is non-null but
         setlistName is null (loading race)` — pump with
         `_buildRehearsal(isPotential: false, setlistId: 'setlist-1')`
         and `setlistName: null`; assert both
         `find.text('No Setlist Selected')` and `find.text('Road Set')`
         find zero widgets.
   3. `group('RehearsalCard potential No Setlist Selected badge',
      ...)` with three `testWidgets` cases pumping the same harness
      with `isPotential: true`. Use `await tester.pump()` after
      `pumpWidget` to let the pulse `AnimationController` initialize.
      Do not use `pumpAndSettle` — the potential-branch pulse controller
      repeats indefinitely and would time out `pumpAndSettle`.
      1. `renders "No Setlist Selected" when rehearsal.setlistId is
         null` — pump with `_buildRehearsal(isPotential: true,
         setlistId: null)` and `setlistName: null`; assert
         `find.text('No Setlist Selected')` finds one widget.
      2. `does not render "No Setlist Selected" when
         rehearsal.setlistId is non-null` — pump with
         `_buildRehearsal(isPotential: true, setlistId: 'setlist-1')`
         and `setlistName: 'Road Set'`; assert
         `find.text('No Setlist Selected')` finds zero widgets.
      3. `does not render "No Setlist Selected" when setlistId is
         non-null but setlistName is null (loading race)` — pump
         with `_buildRehearsal(isPotential: true, setlistId:
         'setlist-1')` and `setlistName: null`; assert
         `find.text('No Setlist Selected')` finds zero widgets.
   4. `group('ConfirmedGigCard No Setlist Selected badge', ...)` with
      two `testWidgets` cases pumping under `MaterialApp(theme:
      AppTheme.darkTheme, home: Scaffold(body: ConfirmedGigCard(...)))`:
      1. `renders "No Setlist Selected" when gig.setlistId is null` —
         pump with `_buildGig(isPotential: false, setlistId: null,
         setlistName: null)`; assert `find.text('No Setlist Selected')`
         finds one widget.
      2. `does not render "No Setlist Selected" when gig.setlistId
         is non-null` — pump with `_buildGig(isPotential: false,
         setlistId: 'setlist-1', setlistName: 'Road Set')`; assert
         `find.text('No Setlist Selected')` finds zero widgets.
   5. `group('PotentialGigCard No Setlist Selected badge', ...)` with
      three `testWidgets` cases pumping under `MaterialApp(theme:
      AppTheme.darkTheme, home: Scaffold(body: PotentialGigCard(...)))`
      (plus `await tester.pump()` after `pumpWidget`; same reasoning as
      the potential-rehearsal group — do not use `pumpAndSettle`).
      1. `renders "No Setlist Selected" when gig.setlistId is null` —
         pump with `_buildGig(isPotential: true, setlistId: null,
         setlistName: null)`; assert `find.text('No Setlist Selected')`
         finds one widget.
      2. `does not render "No Setlist Selected" when gig.setlistId is
         non-null` — pump with `_buildGig(isPotential: true,
         setlistId: 'setlist-1', setlistName: 'Road Set')`; assert
         `find.text('No Setlist Selected')` finds zero widgets.
      3. `does not render "No Setlist Selected" when gig.setlistId is
         null but setlistName is stale (delete_setlist cascade)` —
         pump with `_buildGig(isPotential: true, setlistId: null,
         setlistName: 'Old Set')`; assert
         `find.text('No Setlist Selected')` finds one widget (id is
         authoritative; stale name does not suppress the badge).
   Do not add golden files. Do not add integration tests. Do not
   extract any shared widget or helper into `lib/`. If any assertion
   would require a new `@visibleForTesting` member, callback, or public
   field on any production card, stop and report — do not expand the
   production surface just to make a test easier.

### Cycle 4 Verification Plan

#### Tier 1 — pre-deploy (QA-executable, no running app)

1. `flutter analyze` — no new warnings or errors introduced by Cycle 4.
2. `flutter test test/features/home/widgets/dashboard_no_setlist_badge_test.dart`
   — all four new groups pass every case. Specifically:
   - The confirmed-rehearsal group verifies the muted pill renders when
     `setlistId == null`, the existing rose pill renders when both id
     and name are non-null, and neither renders when `setlistId !=
     null && setlistName == null` (loading-race preservation).
   - The potential-rehearsal group verifies the centered muted pill
     renders when `setlistId == null`, does not render when `setlistId`
     is non-null, and does not render during the `setlistName`
     loading race (id-authoritative gate identical to confirmed).
   - The confirmed-gig group verifies the muted pill renders when
     `gig.setlistId == null` and does not render when `gig.setlistId`
     is non-null.
   - The potential-gig group verifies the centered muted pill renders
     when `gig.setlistId == null`, does not render when `gig.setlistId`
     is non-null, and still renders when `setlistId == null` but
     `setlistName` is a stale non-null string (the
     `delete_setlist`-cascade case; id is authoritative).
3. `flutter test test/features/events/widgets/event_dropdown_test.dart` —
   Cycle 1–3 coverage still passes unchanged. Cycle 4 does not modify
   this file.
4. `flutter test` full suite — every existing test passes unchanged. No
   home / rehearsal / gig widget tests existed before Cycle 4; the new
   file is the first `test/features/home/widgets/` test.
5. Static SQL / migration review — none required; Cycle 4 adds no
   migration.

#### Tier 2 — post-deploy

n/a. Cycle 4 has no migration, no RPC change, and no post-deploy step.

#### Cycle 4 owner-run punch list (Tony, at PR-test / apply time)

QA cannot exercise a running app; hand these to Tony verbatim. Run on at
least one native platform (macOS or iOS) plus Web to confirm platform
parity.

1. **Confirmed rehearsal card, no setlist.** Open Home. Ensure the
   "Upcoming Rehearsals" slot is a confirmed rehearsal with no setlist
   selected (create one via Add → Rehearsal with the setlist selector
   left on "None", save, reload Home).
   **Expected:** The confirmed rehearsal card renders an outlined pill
   below the Location row with the literal text `No Setlist Selected`
   in muted white (~75% alpha) with a 1.5px white 40%-alpha border,
   sized identically to the existing rose selected pill, left-aligned.
2. **Confirmed rehearsal card, setlist selected.** Open the same
   rehearsal, edit via View Rehearsal → Edit Rehearsal, pick any
   setlist, save. Reload Home.
   **Expected:** The card renders the existing rose-outlined selected
   pill with the setlist name (Cycle 1–3 behavior). The muted "No Setlist
   Selected" pill is not shown.
3. **Potential rehearsal card, no setlist.** Ensure a `POTENTIAL
   REHEARSAL` card is visible on Home without a setlist selected
   (create a rehearsal with `isPotential: true` — e.g. via the
   potential-rehearsal creation flow — and leave the setlist selector
   on "None", save, reload Home).
   **Expected:** The potential rehearsal card renders the same muted
   pill between the Location text and the YES/NO button row,
   horizontally centered within the card (matching the centered chip /
   date / time / location content above it). Text, color, border,
   height, and radius match steps 1's pill exactly.
4. **Potential rehearsal card, setlist selected.** Edit the same
   potential rehearsal via View Rehearsal → Edit Rehearsal, pick any
   setlist, save. Reload Home.
   **Expected:** The potential rehearsal card no longer shows the muted
   "No Setlist Selected" pill. The YES/NO button row remains anchored
   at the bottom of the card (Spacer absorbs the freed vertical
   space); card height may shrink slightly.
5. **Confirmed gig card, no setlist.** Open Home. Ensure a confirmed
   gig is visible in the "Upcoming Gigs" horizontal row without a
   setlist selected (create one via Add → Gig, leave the Show Details
   setlist selector on "None", save).
   **Expected:** The confirmed gig card renders an outlined `No Setlist
   Selected` pill below the Time row, using the same muted styling as
   step 1, left-aligned.
6. **Confirmed gig card, setlist selected.** Edit the gig via View Gig
   → Edit Gig, pick any setlist, save. Reload Home.
   **Expected:** The confirmed gig card no longer shows the muted "No
   Setlist Selected" pill. No new selected-setlist pill is added — Cycle
   4 intentionally leaves the "with setlist" confirmed-gig layout
   unchanged.
7. **Potential gig card, no setlist.** Ensure a `POTENTIAL GIG` card
   is visible on Home without a setlist selected (create a gig with
   `isPotential: true` and leave the setlist selector on "None", save,
   reload Home).
   **Expected:** The potential gig card renders the same muted pill
   between the venue+city row and the YES/NO button row, horizontally
   centered within the card. Text, color, border, height, and radius
   match step 3's pill exactly.
8. **Potential gig card, setlist selected.** Edit the same potential
   gig via View Gig → Edit Gig, pick any setlist, save. Reload Home.
   **Expected:** The potential gig card no longer shows the muted "No
   Setlist Selected" pill. YES/NO button row remains anchored at the
   bottom; card height may shrink slightly.
9. **Loading race — confirmed rehearsal card.** With a rehearsal that
   has a setlist selected, force a fresh cold start (kill and relaunch
   the app). Land on Home.
   **Expected:** While `setlistsProvider` is briefly loading, the
   rehearsal card renders neither the rose pill nor the muted "No
   Setlist Selected" pill. Once the provider populates, the rose pill
   appears. No transient "No Setlist Selected" flash.
10. **Loading race — potential rehearsal card.** With a potential
    rehearsal that has a setlist selected, force a fresh cold start.
    Land on Home.
    **Expected:** While `setlistsProvider` is briefly loading, the
    potential rehearsal card renders no muted "No Setlist Selected"
    pill (id is non-null, so the badge is suppressed regardless of
    name resolution state). No transient flash.
11. **Platform parity.** Repeat steps 1, 3, 5, and 7 on Web
    (bandroadie.com) or a second native platform.
    **Expected:** Identical visual result on every variant — the muted
    pill renders the same across surfaces.

### Cycle 4 QA Regression Areas

- **Rehearsal editor drawer, Setlist section**: Cycle 1–3 behavior; must
  still render unchanged. Cycle 4 does not touch
  `event_editor_drawer.dart` or `event_form_fields.dart`.
- **View Rehearsal drawer**: renders `setlistName` when non-null; Cycle 4
  does not touch this widget.
- **View Gig drawer**: renders
  `gig.setlistName ?? 'Unnamed Setlist'`
  ([view_gig_drawer.dart:598](lib/features/gigs/widgets/view_gig_drawer.dart#L598));
  Cycle 4 does not touch this widget.
- **Home tab wiring** (`home_screen.dart` and `home_tab_content.dart`):
  already pass `setlistName` correctly; Cycle 4 does not modify them.
- **Potential card variants**: both `PotentialGigCard` and
  `RehearsalCard._buildPotentialCard` gain a centered muted "No Setlist
  Selected" pill between existing centered content and the `Spacer()`.
  Chip label, date/time animated labels, Location/venue+city rows,
  `Spacer`, YES/NO buttons, date-navigation chevrons, keyboard focus
  order, and pulse animation controllers are unchanged. Multi-date
  navigation, RSVP submission, optimistic response handling, and
  keyboard shortcuts must all still pass unchanged.
- **`delete_setlist` RPC stale-name behavior**: pre-existing — RPC nulls
  `gigs.setlist_id` but leaves stale `gigs.setlist_name`. Cycle 4 gates
  on `setlistId == null` on both gig variants, so the muted pill
  correctly shows in this edge case on both surfaces; no new drift is
  introduced.
- **`setlistsProvider` loading race — rehearsal side**: pre-existing.
  Both rehearsal variants gate on `setlistId == null`, so a
  loading-race `setlistName == null` while `setlistId != null` never
  produces a false-negative badge on either variant.
- **Uncommitted QA_REPORT.md / PR_BODY.md formatter edits**: Cycle 4
  does not overwrite either file; Tony's alignment/trailing-newline
  changes are preserved.

### Cycle 4 Rollout Strategy

- Same PR #291 on the existing feature branch
  `feature/add-setlist-to-rehearsal` — no new branch, no new PR.
- No feature flag — additive UI behind the existing dashboard rendering
  paths.
- No migration to apply. Deploy is code-only.
- Rollback: revert the four Cycle 4 changes (three modified card files
  and the new widget-test file). Because no prop / provider / column
  shape changed, no data cleanup is required.

### Cycle 4 Out of Scope

- Any refactor extracting a shared `_NoSetlistBadge` widget — Cycle 4
  keeps all four pills inlined (decision rationale in Cycle 4 Proposed
  Solution).
- Any change to `Gig.setlistName` denormalization, `delete_setlist` RPC's
  handling of `gigs.setlist_name`, or any other stale-name data-integrity
  behavior. That is a separate concern outside Cycle 4.
- Any change to view drawers, editor drawer, calendar cards, or other
  non-dashboard event surfaces.
- Any wiring change to `home_screen.dart` / `home_tab_content.dart` —
  they already pass every prop each card needs.
- Adding a "selected setlist" pill to `ConfirmedGigCard`,
  `PotentialGigCard`, or `RehearsalCard._buildPotentialCard` for the
  `setlistId != null` case (Cycle 4 only adds the "No Setlist Selected"
  affordance to variants that lack any setlist rendering; the confirmed
  rehearsal card's existing rose pill is preserved untouched).
- Any layout change to the potential card RSVP surface — chip label,
  date/time animated labels, YES/NO buttons, date-navigation chevrons,
  keyboard focus order, and animation controllers all remain
  byte-identical to their pre-Cycle-4 behavior.
- Golden-file or integration coverage — Tier 1 widget tests are
  sufficient for this UI-only change.
- Any change to `QA_REPORT.md` or `PR_BODY.md` in Cycle 4 — those
  documents will be updated by QA and Manager respectively.
