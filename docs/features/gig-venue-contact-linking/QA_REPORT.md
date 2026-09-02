# Feature Slug

feature/gig-venue-contact-linking

# Feature Title

Link band-wide Contacts to Gigs (autocomplete + inline create)

# Cycle Number

3

# Final Verdict

REQUIRES CHANGES

# Validation Summary

I validated the uncommitted implementation on branch `feature/gig-venue-contact-linking` against the current Architect plan and the Cycle 2 Engineer report. I confirmed the branch/slug match, reviewed the working-tree diff against `HEAD`, inspected the new migration SQL directly, ran the required focused `flutter analyze` on the eight touched source/test files, ran the focused gig model test file, and checked the diff additions specifically for `TODO`, `FIXME`, and newly added `debugPrint(` calls.

By code-path analysis, the intended gig-only shared-contact behavior is implemented: `Gig` hydrates linked contacts from `gig_contacts(contact_id, contacts(*))`, `EventFormData` round-trips `contactIds`, `EventsRepository` calls `sync_gig_contacts()` after gig create/update and before the final refetch, the gig editor uses `contactsProvider` rather than members for autocomplete, unmatched names route through the explicit create-contact dialog, unresolved rows block save, and `ViewGigDrawer` renders tappable contact rows that open `ContactDetailDrawer` while leaving the parent gig drawer in place.

Approval is still blocked by one active QA gate failure from the updated Architect plan: `lib/features/events/events_repository.dart` is `+47 / -20` against the planned `+34 to +51 / -3 to -5`, so the deletion delta is `4x` the allowed ceiling and remains a Critical change-budget finding in this QA mode.

# Architect Scope Review

- Branch matched the requested slug: `feature/gig-venue-contact-linking`.
- `ARCHITECT_PLAN.md` and `ENGINEER_REPORT.md` both match the branch slug.
- Tracked modified files are confined to the approved implementation surfaces:
  - `lib/app/models/gig.dart`
  - `lib/features/events/events_repository.dart`
  - `lib/features/events/models/event_form_data.dart`
  - `lib/features/events/widgets/event_editor_drawer.dart`
  - `lib/features/events/widgets/gig_form_fields.dart`
  - `lib/features/gigs/gig_repository.dart`
  - `lib/features/gigs/widgets/view_gig_drawer.dart`
  - `test/app/models/gig_test.dart`
- The expected untracked migration file is present at `supabase/migrations/20260902123000_add_gig_contacts_and_sync_rpc.sql`.
- No off-limits venue files, member feature files, native/web platform files, or `lib/main.dart` changes were introduced.
- The resolved prior-cycle items were not re-raised: the three previously flagged debug prints are gone from the diff additions, the focused analyzer is clean, `event_editor_drawer.dart` is within the revised budget, `gig_form_fields.dart` is within the revised budget, and `fetchGigById()` is treated as the allowed required public helper.

# Completeness Check

- Architect task 1: complete by SQL inspection. The migration creates `gig_contacts`, enables RLS, defines `sync_gig_contacts(...)`, revokes default execute from `PUBLIC, anon`, and grants execute to `authenticated`.
- Architect task 2: complete by code inspection. `Gig` parsing and both gig select clauses now hydrate linked contacts through the nested join.
- Architect task 3: complete by code inspection. `EventFormData` includes `contactIds` in the constructor, `copyWith()`, and `fromGig()`.
- Architect task 4: complete by code inspection. `EventsRepository.createGig()` and `updateGig()` call `sync_gig_contacts()` after the gig row exists and before the final refetch.
- Architect tasks 5 through 7: complete by code inspection. `EventEditorDrawer` loads shared contacts through `contactsProvider`, owns repeatable local contact-row state, resolves or blocks unmatched rows, and uses the required `"<name>" is not in your contacts list` create-contact dialog.
- Architect task 8: complete by code inspection. `ViewGigDrawer` shows contact rows and opens `ContactDetailDrawer` without popping the parent drawer first.
- Architect task 9: satisfied at the minimum required level. `test/app/models/gig_test.dart` now covers nested contact parsing, and no broader widget/repository test was required by the plan once the focused model coverage and manual save-guard code path were confirmed.

# Behavior Verification

- Confirmed in code: `Gig.fromJson()` parses `gig_contacts` rows into `Gig.contacts` via nested `contacts(*)` payloads.
- Confirmed in code: `GigRepository._gigSelectClause` and `EventsRepository` final refetch queries include `gig_contacts(contact_id, contacts(*))`.
- Confirmed in code: `EventFormData.fromGig()` populates `contactIds` from `gig.contacts`, and `_buildFormData()` rebuilds `contactIds` only from non-empty resolved rows with concrete ids.
- Confirmed in code: autocomplete suggestions for gig contacts are derived from `availableContacts`, which is sourced from `contactsProvider`, not band members.
- Confirmed in code: unmatched non-empty names route through the explicit create-contact dialog; dialog cancel clears/reverts the row rather than persisting free text.
- Confirmed in code: `_ensureGigContactsResolved()` runs in the gig save path and blocks save with the expected user-facing error when any row remains unresolved.
- Confirmed in code: `ViewGigDrawer` shows one tappable row per linked contact with a company/title summary and opens `ContactDetailDrawer` on tap.
- Runtime exercised: `flutter analyze` on the touched files passed with `No issues found!`; `flutter test test/app/models/gig_test.dart` passed with 6 tests.
- Not runtime exercised in this QA pass: manual drawer/UI flows across platforms and live RPC execution in an isolated Supabase branch. Per the manager instructions for this cycle, database safety was verified by SQL inspection rather than preview-branch apply.

# Regression Check

Regression risk: MEDIUM.

- Gigs: affected. The persistence and hydration path changed, but the implementation remains localized to the gig model, repositories, editor, and detail drawer.
- Contacts: affected through reuse of the existing shared contacts provider and create/detail flows.
- Members: unaffected for data source purposes. The gig contact autocomplete path does not read from member data.
- Rehearsals: unaffected by code-path review.
- Auth/session, routing, notifications, and init order: unchanged in the diff.
- Platform parity: the implementation is confined to shared Flutter/Supabase code; no native or web bootstrap behavior changed.

# Database Safety

- Confirmed by SQL inspection: the migration creates `public.gig_contacts` with cascading foreign keys to `gigs`, `contacts`, and `bands`, plus band/contact indexes and a composite primary key on `(gig_id, contact_id)`.
- Confirmed by SQL inspection: RLS policies use `(select auth.uid())` and query `band_members`, not `gig_contacts`, avoiding self-referential policy recursion.
- Confirmed by SQL inspection: `public.sync_gig_contacts(UUID, UUID, UUID[])` is `SECURITY DEFINER`, sets `search_path = public`, validates authenticated active membership, validates gig ownership, rejects cross-band contacts, deduplicates ids deterministically, deletes stale rows, and inserts missing rows only.
- Confirmed by SQL inspection: the migration revokes execute from `PUBLIC, anon` and grants execute to `authenticated`.
- Confirmed by client/SQL alignment: the Flutter client calls `sync_gig_contacts` with parameters `p_gig_id`, `p_band_id`, and `p_contact_ids`, matching the migration definition.
- Methodology note only, not a blocker for this cycle: I did not rerun isolated preview-branch migration apply or live `has_function_privilege(...)` checks because the manager explicitly directed that the known historical preview-branch push failure on `073_fix_gig_responses_unique_constraint.sql` be treated as a pre-existing environment defect and that database safety be verified by code inspection of the migration SQL in this pass.

# Analyzer Results

- Ran: `flutter analyze lib/app/models/gig.dart lib/features/events/events_repository.dart lib/features/events/models/event_form_data.dart lib/features/events/widgets/event_editor_drawer.dart lib/features/events/widgets/gig_form_fields.dart lib/features/gigs/gig_repository.dart lib/features/gigs/widgets/view_gig_drawer.dart test/app/models/gig_test.dart`
- Result: `No issues found!`
- QA status for touched files: `0` errors, `0` warnings, `0` info issues.

# Test Results

- Ran: `flutter test test/app/models/gig_test.dart`
- Result: passed.
- Test count: `6` passing tests.
- No additional widget or repository test was required by the Architect plan for approval once the focused model test coverage and code-path checks were complete.

# Diff Safety Review

- Secrets or API keys: none found in the reviewed diff.
- `TODO` / `FIXME`: none found in the reviewed diff additions.
- Newly added `debugPrint(` calls: none found in the reviewed diff additions.
- Off-limits files: none touched.
- Pre-authorized untracked paths under `docs/features/gig-venue-contact-linking/` and `supabase/migrations/20260902123000_add_gig_contacts_and_sync_rpc.sql` were present and treated as expected.

# Change Budget Review

- `lib/app/models/gig.dart`: `+24 / -3`, additions within the planned `+17 to +26` range.
- `lib/features/gigs/gig_repository.dart`: `+27 / -4`, additions within the planned `+18 to +28` range.
- `lib/features/events/models/event_form_data.dart`: `+7 / -12`, additions within the planned `+6 to +9` range.
- `lib/features/events/widgets/event_editor_drawer.dart`: `+212 / -6`, within the revised planned `+145 to +220` range referenced by the current Architect plan.
- `lib/features/events/widgets/gig_form_fields.dart`: `+463 / -18`, within the revised planned `+420 to +520 / -10 to -25` range referenced by the current Architect plan.
- `lib/features/gigs/widgets/view_gig_drawer.dart`: `+105 / -11`, within the planned `+85 to +130 / -7 to -12` range.
- `test/app/models/gig_test.dart`: `+63 / -6`, within the planned `+46 to +69` additions range.
- `supabase/migrations/20260902123000_add_gig_contacts_and_sync_rpc.sql`: `145` lines, within the planned `+116 to +174` range.
- `lib/features/events/events_repository.dart`: `+47 / -20`, additions are within the planned `+34 to +51` range, but deletions exceed the planned `-3 to -5` ceiling by `4x`; under this QA mode's arithmetic budget gate, that remains a Critical finding.
- New dependencies: none.
- New public API surface: one required public helper method (`fetchGigById()`) is treated as allowed by the updated manager instructions for this cycle.

# Code Efficiency Review

- Architectural reuse is good. The change extends the existing gig model/repository path, reuses `contactsProvider` for band-scoped contact data, and reuses `ContactDetailDrawer` rather than introducing a parallel feature module.
- I searched the existing codebase for a pre-existing equivalent to the added gig contact row helper and did not find an obvious existing abstraction that already handled repeatable contact-row text/id/focus state plus inline create behavior.
- No extra dependencies or parallel controllers/providers were introduced beyond the approved local helper shape.

# Issues Found

## Critical

- `[code-quality]` `lib/features/events/events_repository.dart` exceeds the updated Architect change budget on deletions: actual `+47 / -20` versus planned `+34 to +51 / -3 to -5`. Under this QA mode's required arithmetic budget rule, the deletion delta is `4x` the allowed ceiling and blocks approval.

## Warnings

- None.

## Suggestions

- None.
# Cycle Number

1

# Final Verdict

REQUIRES CHANGES

# Validation Summary

I validated the branch state, reviewed the Architect plan and Engineer report, inspected the uncommitted diff against `HEAD`, read the new migration SQL, ran focused Flutter validation, and attempted the required isolated Supabase migration apply.

The implementation is largely aligned with the requested gig-only behavior by code-path analysis: the new join table/RPC are present in SQL, `Gig` now parses nested contacts, the gig repositories/refetches include `gig_contacts(contact_id, contacts(*))`, form state carries `contactIds`, the gig editor uses `contactsProvider` rather than members for autocomplete, unmatched names open the required create-contact dialog, unresolved rows block save, and `ViewGigDrawer` shows tappable contact rows that open `ContactDetailDrawer`.

Approval is blocked by four independent QA gate failures:

- required isolated migration validation could not be completed, so database safety is unverifiable
- `flutter analyze` on the touched files returned 60 info-level issues, and this QA gate requires zero issues at every severity
- the diff adds new `debugPrint(` calls, which is an automatic critical finding in this mode
- the change budget was exceeded at critical level in `lib/features/events/widgets/event_editor_drawer.dart`, and the diff also added an unplanned public repository method

# Architect Scope Review

- Branch matched the requested slug: `feature/gig-venue-contact-linking`.
- `ARCHITECT_PLAN.md` and `ENGINEER_REPORT.md` both matched the branch slug.
- Tracked modified files stayed within the planned Flutter surfaces:
  - `lib/app/models/gig.dart`
  - `lib/features/events/events_repository.dart`
  - `lib/features/events/models/event_form_data.dart`
  - `lib/features/events/widgets/event_editor_drawer.dart`
  - `lib/features/events/widgets/gig_form_fields.dart`
  - `lib/features/gigs/gig_repository.dart`
  - `lib/features/gigs/widgets/view_gig_drawer.dart`
  - `test/app/models/gig_test.dart`
- The expected untracked migration was present:
  - `supabase/migrations/20260902123000_add_gig_contacts_and_sync_rpc.sql`
- No off-limits venue files, member files, platform files, or `lib/main.dart` were touched.
- Autocomplete source is shared contacts only by code inspection: `GigFormFields` consumes `availableContacts` from `contactsProvider`; no member dataset is used for gig contacts.

# Completeness Check

- Architect tasks 1 through 8 are implemented in code.
- Task 9 has partial coverage only. The model parsing test was added, but no additional runtime or widget-level validation exists for the unresolved-contact save guard or RPC sequencing.
- I did not find evidence of venue-contact coupling or band-member autocomplete leakage.

# Behavior Verification

- Confirmed in code: `Gig.contacts` is parsed from nested `gig_contacts -> contacts(*)` rows.
- Confirmed in code: `GigRepository._gigSelectClause` and `EventsRepository` final refetches include the required `gig_contacts(contact_id, contacts(*))` join.
- Confirmed in code: `EventsRepository.createGig()` and `updateGig()` call `sync_gig_contacts()` after the gig row exists and before the final gig refetch.
- Confirmed in code: `EventFormData` carries `contactIds` through constructor, `copyWith()`, and `fromGig()`.
- Confirmed in code: `EventEditorDrawer` loads shared contacts through `contactsProvider`, maintains local row draft state, opens the explicit `"<name>" is not in your contacts list` dialog, creates contacts through the existing contacts controller, and blocks save when any row remains unresolved.
- Confirmed in code: `ViewGigDrawer` renders one contact row per linked contact and opens `ContactDetailDrawer` without closing the parent gig drawer first.
- Runtime exercised: `flutter test test/app/models/gig_test.dart` passed, including the new nested contact parsing coverage.
- Not runtime exercised: no manual drawer/form flow, RPC behavior, cross-band rejection, or multi-platform UI validation was performed in this pass.

# Regression Check

Regression risk: MEDIUM.

- Gigs: affected. The core read/write path is updated, but the UI implementation is concentrated in a very large `EventEditorDrawer` delta.
- Contacts: affected. The feature correctly reuses the existing shared contacts controller/repository path.
- Members: unaffected by code path for autocomplete; member data is not used as the source for gig contacts.
- Notifications: nominally unaffected, but gig navigation still fetches gigs via a bespoke select in `notification_navigation_handler.dart` that does not hydrate `gig_contacts`; the new drawer compensates by refetching when `gig.contacts` is empty.
- Auth/session, routing, native/web init order: unchanged by inspected diff.

# Database Safety

- Confirmed in SQL: the migration creates `public.gig_contacts`, enables RLS, adds authenticated select/insert/delete policies using `(select auth.uid())`, defines `public.sync_gig_contacts(UUID, UUID, UUID[])` as `SECURITY DEFINER` with `SET search_path = public`, deduplicates input IDs deterministically, validates band membership and band ownership, deletes stale rows, inserts missing rows, revokes from `PUBLIC, anon`, and grants execute to `authenticated`.
- Not confirmed at runtime: the migration applying cleanly in isolation.
- Required isolated validation failed before reaching the new migration. I created preview branch `qa-gig-venue-contact-linking` with project ref `sfacuuqhqqqwrppdbpxh`, then ran `supabase db push --project-ref sfacuuqhqqqwrppdbpxh --yes`. The push failed on historical migration `073_fix_gig_responses_unique_constraint.sql` with `ERROR: relation "gig_responses" does not exist (SQLSTATE 42P01)`.
- Because the isolated push failed, I could not verify `has_function_privilege('anon', ...)` / `has_function_privilege('authenticated', ...)` against the new RPC on a safe branch.
- Per QA rules, that leaves database safety unverifiable and therefore blocking.
- Cleanup completed: `supabase branches delete qa-gig-venue-contact-linking --yes` succeeded.

# Analyzer Results

- Ran: `flutter analyze lib/app/models/gig.dart lib/features/events/events_repository.dart lib/features/events/models/event_form_data.dart lib/features/events/widgets/event_editor_drawer.dart lib/features/events/widgets/gig_form_fields.dart lib/features/gigs/gig_repository.dart lib/features/gigs/widgets/view_gig_drawer.dart test/app/models/gig_test.dart`
- Result: failed QA gate. Analyzer reported 60 issues across touched files, all at `info` severity, but this mode requires the touched files to come back empty at every severity.
- Representative findings included `avoid_redundant_argument_values`, `unnecessary_lambdas`, `prefer_const_constructors`, and `unnecessary_null_checks` in touched files.

# Test Results

- Ran: `flutter test test/app/models/gig_test.dart`
- Result: passed (`00:01 +6: All tests passed!`).
- No widget test or repository test was run for the unresolved-row save guard or RPC sequencing.
- No manual Supabase RPC behavior test could be completed because the isolated migration apply did not succeed.

# Diff Safety Review

- Secrets or API keys: none found in the inspected diff.
- `TODO` / `FIXME`: none found in the inspected diff.
- `debugPrint(` additions were found in the diff and are an automatic critical finding in this QA mode:
  - `lib/features/events/widgets/event_editor_drawer.dart:498`
  - `lib/features/events/widgets/event_editor_drawer.dart:530`
  - `lib/features/gigs/widgets/view_gig_drawer.dart:93`

# Change Budget Review

- `lib/app/models/gig.dart`: `+21 / -0`, within budget (`+20 to +40`)
- `lib/features/events/events_repository.dart`: `+42 / -4`, within budget (`+30 to +60`)
- `lib/features/events/models/event_form_data.dart`: `+7 / -0`, below the expected range but not a blocker by itself
- `lib/features/events/widgets/event_editor_drawer.dart`: `+482 / -0`, above `2x` the budget ceiling of `+220`; this is a critical bloat finding in this QA mode
- `lib/features/events/widgets/gig_form_fields.dart`: `+133 / -0`, within budget (`+80 to +160`)
- `lib/features/gigs/gig_repository.dart`: `+23 / -0`, slightly above the budget ceiling of `+20`, but not beyond the warning threshold on its own
- `lib/features/gigs/widgets/view_gig_drawer.dart`: `+107 / -9`, above `1.5x` the budget ceiling of `+60`; this is a warning-level bloat finding
- `test/app/models/gig_test.dart`: `+57 / -0`, above the budget ceiling of `+40`, but test growth here is narrow and directly related to the feature
- Migration file: 145 lines, within budget (`+140 to +240`)
- New public API surface exceeded the plan budget: `GigRepository.fetchGigById()` was added as a new public method even though the Architect budget only allowed at most one small public UI helper.

# Code Efficiency Review

- The feature correctly reuses `contactsProvider` and `ContactDetailDrawer` rather than introducing a new controller or repository.
- `ViewGigDrawer` now contains a local `_contactSummary()` formatter even though similar title/company formatting logic already exists in the contacts UI (`lib/features/contacts/widgets/contact_card.dart`). This is minor duplication.
- `ViewGigDrawer` also adds a fallback refetch path via the new public `GigRepository.fetchGigById()`. That compensates for unhydrated gig entry points, but it expands public API surface and drawer complexity instead of keeping hydration consistent at the original fetch sites.

# Issues Found

## Critical

- `[database-safety]` Required isolated migration validation is incomplete. `supabase db push --project-ref sfacuuqhqqqwrppdbpxh --yes` failed on historical migration `073_fix_gig_responses_unique_constraint.sql` with `relation "gig_responses" does not exist`, so I could not confirm the new migration applies cleanly or run the required `has_function_privilege(...)` checks for `sync_gig_contacts(UUID, UUID, UUID[])`.
- `[code-quality]` Focused analyzer gate failed. The touched files still report 60 info-level issues under `flutter analyze`, and this QA mode requires the touched slice to be clean at every severity before approval.
- `[code-quality]` The diff introduces new `debugPrint(` calls in shipping code at `lib/features/events/widgets/event_editor_drawer.dart:498`, `lib/features/events/widgets/event_editor_drawer.dart:530`, and `lib/features/gigs/widgets/view_gig_drawer.dart:93`. This mode treats new debug artifacts in the diff as an automatic critical finding.
- `[code-quality]` `lib/features/events/widgets/event_editor_drawer.dart` added `+482` lines against a budget ceiling of `+220`, which is above `2x` budget and therefore a critical bloat finding in this QA mode.
- `[code-quality]` `lib/features/gigs/gig_repository.dart` adds a new public `fetchGigById()` method that was not part of the Architect change-budget allowance for new public API surface.

## Warnings

- `[code-quality]` `lib/features/gigs/widgets/view_gig_drawer.dart` added `+107 / -9` lines against a budget ceiling of `+60`, which exceeds the `1.5x` warning threshold.
- `[regression]` Notification-driven gig opening still uses a bespoke gig select outside `GigRepository` that does not hydrate `gig_contacts`. The new `ViewGigDrawer` refetch masks that gap at runtime when `gig.contacts` is empty, but gig hydration is not yet fully consistent across all entry points.

## Suggestions

- `[code-quality]` If the drawer keeps its contact subtitle display, consider reusing a shared contact subtitle formatter or at least aligning the formatting contract with the existing contacts UI so title/company presentation does not diverge over time.
