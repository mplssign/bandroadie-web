# Band Members & Contacts A-Z Listing — Amendment 1: Drop Band Search/Sections, Add Contact Company Field

**Amendment Date:** 2026-07-25
**Amendment Author:** Architect
**Trigger:** Product scope change from Tony, confirmed after QA APPROVED the base feature (see `QA_REPORT.md`). Base feature is implemented on disk and QA-approved but **not yet committed or pushed** — this amendment lands before any of it ships, so it modifies the working tree directly rather than reopening a merged feature.

---

## What's Changing and Why

### 1. Band Members — drop search and section headers, keep the new card

The base plan (Task 11) gave Band Members a search bar, A-Z section headers, and the new simplified `BandMemberCard`, with no index column. Tony now wants the search bar and A-Z sectioning removed entirely: Band Members should render as a **plain, ungrouped, unsearchable scrollable list of `BandMemberCard`s**. The new card style (plain surface, name + musical-roles subtitle, admin kebab) stays — only the search/grouping chrome goes.

**Why:** Product decision — Band Members is typically a short list (a handful of people in one band), so search and alphabetical sectioning add UI weight without real navigational value there, unlike Venues/Contacts which can grow much longer. This was confirmed directly with Tony, not inferred.

### 2. Contacts — add a company field

The contact edit form needs a new `company` field, surfaced on the Contacts A-Z list card subtitle alongside the existing `title` field. The base plan's "Database Impact: Not applicable" no longer holds — `company` has no existing column on `contacts` and requires a migration.

**Why:** Standalone contacts (agents, promoters, sound techs) frequently have both a role (*"Booking Agent"*) and an affiliation (*"Venue Nation"*) that are meaningfully different pieces of information; today only the role is captured.

---

## Existing System State (post base-feature, pre-amendment)

Confirmed by reading the current working-tree files (not the base plan's description of what *would* be built — the actual shipped-but-uncommitted code):

- `band_members_view.dart` is currently a `StatefulWidget` holding `TextEditingController`, `ItemScrollController`, `ItemPositionsListener`, `String _searchQuery`, `_groupingKey()`, `_filterMembers()`, `_calculateItemCount()`/`_buildItem()` flat-index branching, and a search-empty-state block — rendering via `ScrollablePositionedList.builder` with `AzSearchField` + `AzSectionHeader(rightPadding: Spacing.pagePadding)` + `BandMemberCard`. No `AzIndexColumn` (per the base plan's existing, unchanged product decision).
- `Contact` model (`models/contact.dart`) has `id`, `bandId`, `name`, `title`, `phone`, `email`, `notes`, `createdAt`, `updatedAt`. **No `company` field.**
- `contacts` table (`supabase/migrations/20260410000000_contacts_venues_tables.sql`) has columns `id, band_id, name, title, phone, email, notes, created_at, updated_at`. **No `company` column.**
- `ContactsRepository.fetchContacts()` uses `select('*')` — confirmed (not assumed) it will pick up a new `company` column automatically once it exists; no repository change needed for reads.
- `ContactsRepository.createContact({required bandId, required data})` and `updateContact({required id, required data})` both take a generic `Map<String, dynamic> data` and spread/pass it directly to Supabase `.insert()`/`.update()` — the repository itself never lists field names, so **no repository change is needed**. The map is built in exactly one place: `_save()` in `contact_form_screen.dart` (`lib/features/contacts/widgets/contact_form_screen.dart:107-119`), which is used for **both** create and update. This is the single call site that must add `'company'` explicitly — confirmed via `grep`, there is no second place that constructs a contacts write payload.
- `ContactCard` (`contact_card.dart`) renders the subtitle as `contact.title ?? ''` — a single field, always-rendered-even-if-blank (for uniform card height, per the established Venues/Contacts pattern).
- RLS on `contacts` (same migration file) is **row-level only** — every policy (`SELECT`/`INSERT`/`UPDATE`/`DELETE`) checks `band_members` membership/role via `EXISTS (...)`, none reference specific columns of `contacts`. Confirmed by reading all four policies: adding a nullable column has **zero RLS impact** — this is not an assumption, it's direct inspection of the migration.
- The `set_contacts_updated_at` trigger fires `BEFORE UPDATE ON contacts` for any column change — it will cover `company` automatically, no trigger change needed.
- Shared A-Z helpers (`az_list_helpers.dart`'s `groupByLetter`/`flatIndexForSection`/`resolveTargetLetter`, `az_search_field.dart`'s `AzSearchField`, `az_section_header.dart`'s `AzSectionHeader`) are confirmed via `grep` to be consumed by **Venues and Contacts only** for `AzSectionHeader`/the grouping helpers once Band Members' usage is removed, and by **Venues and Contacts** for `AzSearchField`. `az_index_column.dart`'s `AzIndexColumn` was already Venues/Contacts-only before this amendment (Band Members never instantiated it). **None of the four shared helper files change** — confirmed by usage audit, not assumed.

---

## Proposed Solution

### Change 1: Band Members simplification

Revert `band_members_view.dart` from `StatefulWidget` back to `StatelessWidget`, rendering a fixed title row (unchanged "Band Members" + Add button) followed by a flat `CustomScrollView` → `SliverList` of `BandMemberCard`s inside `SliverPadding`, wrapped in the existing `RefreshIndicator`. This is deliberately **not** a novel design — it's the same shape the pre-feature `band_members_view.dart` used (documented in the base `ARCHITECT_PLAN.md`'s "Band Members (current)" section), just with `BandMemberCard` in place of the old `MemberCard`. Reusing an already-proven-correct pattern from this exact codebase is the smallest possible change, and it removes an entire class of risk (flat-index arithmetic, `ScrollablePositionedList` wiring) rather than modifying it.

Dropped entirely: `TextEditingController`, `ItemScrollController`, `ItemPositionsListener`, `_searchQuery` state, `_groupingKey()`, `_filterMembers()`, `_calculateItemCount()`/`_buildItem()`, the `AzSearchField` instantiation, the `AzSectionHeader` instantiation, `groupByLetter()` usage, and the "No members found" search-empty-state block (unreachable once there's no search). `dispose()` is no longer needed (no controllers owned).

Kept, unchanged: `BandMemberCard` itself (admin kebab → `onManageRole` → `RoleManagementSheet` wiring untouched), the fixed title row + "Add" button, `_buildLoadingState()`, `_buildErrorState()`, `MembersEmptyState` (zero-members state), `RefreshIndicator`/`onRefresh`. `membersProvider`/`MembersState`/`MembersRepository`/`MemberVM` remain untouched, as in the base plan.

**Side benefit, confirmed by inspection of what's being removed:** this sheds roughly 150+ lines of search/grouping-specific code (two controllers + a listener, the flat-index `_calculateItemCount`/`_buildItem` branching, and the search-empty-state UI block) from a file QA flagged at 415 lines against the Guardrails §8 400-line feature-widget target. The reverted file is expected to land well under that target — smaller than even the pre-feature version, since `BandMemberCard` itself is simpler than the old `MemberCard`-based rendering it replaced.

**Also resolves, by removal, a QA suggestion:** QA's report noted `band_members_view.dart` passes `AzSectionHeader(rightPadding: Spacing.pagePadding)` where the base plan's Task 11 specified `rightPadding: 0` (a no-op deviation, per QA — visually identical either way). Since `AzSectionHeader` is removed from Band Members entirely in this amendment, that discrepancy is moot going forward.

### Change 2: Contacts company field

**Model:** Add `company` (nullable `String`) to `Contact` — same shape as `title`/`phone`/`email`/`notes`: constructor param, `fromJson` (`json['company'] as String?`), `toJson` (`'company': company`).

**Migration:** `ALTER TABLE public.contacts ADD COLUMN company TEXT;` — nullable, no default, matching every other optional column on this table. No RLS policy changes (confirmed above — row-level only). No trigger changes (the existing `updated_at` trigger already fires on any column change).

**Form (`contact_form_screen.dart`):** Add a `TextEditingController _companyController`, initialized from `c?.company ?? ''` and disposed alongside the others. Add a plain `TextField` (not a pill selector like `TitlePillSelector` — there is no fixed, reusable set of company names the way there is for role titles like "Booking Agent"/"Sound"/"Owner"/"Manager", so a free-text field is the correct, minimal UI, matching how `phone`/`email`/`notes` are already handled). Placed directly after the "Title" section and before "Phone", so the form reads Name → Title → Company → Phone → Email → Notes — role and affiliation grouped together, ahead of contact-method fields. In `_save()`, add `'company': _companyController.text.trim().isEmpty ? null : _companyController.text.trim()` to the `data` map — the single call site used by both create and update, per the audit above.

**Card subtitle (`contact_card.dart`) — design decision on combining `title` and `company`:** Currently the subtitle line is `contact.title ?? ''`. With two optional fields to show on one line, the plan is to concatenate them, comma-separated, title first: `"Booking Agent, Venue Nation"`. If only one is present, show that one alone; if neither, render an empty string (preserving the existing always-rendered-blank-line-for-uniform-height behavior).

```dart
String _subtitle(Contact contact) {
  final title = contact.title?.trim();
  final company = contact.company?.trim();
  final hasTitle = title != null && title.isNotEmpty;
  final hasCompany = company != null && company.isNotEmpty;
  if (hasTitle && hasCompany) return '$title, $company';
  if (hasTitle) return title;
  if (hasCompany) return company;
  return '';
}
```

**Why comma-concatenation, not a priority order or a documented "pick one" rule:** this isn't a new visual convention — it's the exact same mechanical pattern already shipped in this codebase for combining two optional fields on one subtitle line: `VenueCard`'s `_formatCityState()` (Venues Amendment 2), which joins city/state with a comma and gracefully omits whichever side is missing. Applying the identical pattern to title/company keeps the three segments' subtitle-formatting logic consistent in kind, and "Title, Company" (e.g. "Booking Agent, Venue Nation") reads naturally in the same way a business card or contact-app subtitle does. No new shared helper is introduced for this — `_formatCityState()` wasn't extracted into `az_list_helpers.dart` either, since it's a two-field, single-widget concern, not shared arithmetic like grouping/flat-indexing.

---

## Database Impact

**Required — one migration.**

New file: `supabase/migrations/20260725000000_add_company_to_contacts.sql`

```sql
-- ============================================================================
-- Migration: add_company_to_contacts
-- Adds an optional company/affiliation field to standalone contacts.
-- ============================================================================

ALTER TABLE public.contacts ADD COLUMN company TEXT;
```

- **RLS:** Unaffected. Confirmed by reading all four existing policies on `contacts` (`SELECT`/`INSERT`/`UPDATE`/`DELETE`) — every one is row-level (`EXISTS (... band_members ...)`), none reference specific column names. No new policy needed.
- **Triggers:** Unaffected. `set_contacts_updated_at` (`BEFORE UPDATE ON contacts`) already fires on any column update.
- **RPCs:** None exist for `contacts` writes — reads/writes go through direct PostgREST `select`/`insert`/`update` calls via `ContactsRepository`, so there is no RPC signature to version or break (Guardrails §4's "never call an RPC with partial parameters" concern doesn't apply here; the equivalent risk — silently omitting `company` from the map at the one call site that builds it — is addressed above by auditing that single call site).
- **Indexes:** None needed — `company` is not a filter/sort target anywhere in this amendment (search remains name-only, per the base plan's existing, unchanged scope).

---

## Flutter Architecture Changes

### Modified widgets/models

- `band_members_view.dart` — `StatefulWidget` → `StatelessWidget`; drops all search/grouping/scroll-controller state; `CustomScrollView`/`SliverList` replaces `ScrollablePositionedList.builder`; renders `BandMemberCard` directly with no `AzSearchField`/`AzSectionHeader`/`AzIndexColumn`.
- `models/contact.dart` — add `company` field, `fromJson`/`toJson` entries.
- `contact_form_screen.dart` — add `_companyController` + `TextField`; add `'company'` to the `_save()` data map.
- `contact_card.dart` — replace the single-field subtitle with the `_subtitle()` title+company combiner above.

### Unchanged

- `contacts_view.dart` — no edit needed. It doesn't construct the subtitle itself (`ContactCard` does), and its search/grouping/index-column logic is untouched by this amendment.
- `contacts_controller.dart` — no edit needed. `load()`/`refresh()` re-fetch full `Contact` objects (now including `company` once the model/migration land), so the new field flows through existing state management automatically.
- `contacts_repository.dart` — no edit needed, per the audit above (generic `data` map pass-through).
- `az_list_helpers.dart`, `az_search_field.dart`, `az_section_header.dart`, `az_index_column.dart` — no edits. Confirmed still needed, unchanged, by Venues and/or Contacts per the usage audit above.
- `band_member_card.dart` — no edits. Still the card `BandMembersView` renders; its admin-kebab wiring is untouched.
- `venues_view.dart`, `venue_card.dart`, and all Venues files — completely untouched by this amendment.

---

## Files to Create

| File | Justification |
|---|---|
| `supabase/migrations/20260725000000_add_company_to_contacts.sql` | Adds the `company` column required by Change 2. No suitable existing column. |

---

## Files to Modify

| File | What changes |
|---|---|
| `lib/features/contacts/widgets/band_members_view.dart` | Revert `StatefulWidget` → `StatelessWidget`; remove search/grouping/`ScrollablePositionedList` machinery; render `CustomScrollView`/`SliverList` of `BandMemberCard`s (same shape as the pre-feature implementation). No `AzSearchField`, `AzSectionHeader`, or `AzIndexColumn`. |
| `lib/features/contacts/models/contact.dart` | Add `company` (nullable `String`) field, `fromJson`, `toJson`. |
| `lib/features/contacts/widgets/contact_form_screen.dart` | Add `_companyController` (TextField, placed after Title, before Phone); include `'company'` in the `_save()` data map for both create and update. |
| `lib/features/contacts/widgets/contact_card.dart` | Replace `contact.title ?? ''` subtitle with the title+company comma-combiner (`_subtitle()`). |

---

## Files Off-Limits

| File | Reason |
|---|---|
| `lib/features/contacts/widgets/az_list_helpers.dart` | Still consumed by Venues + Contacts, unchanged usage. Not touched. |
| `lib/features/contacts/widgets/az_search_field.dart` | Still consumed by Venues + Contacts. Not touched. |
| `lib/features/contacts/widgets/az_section_header.dart` | Still consumed by Venues + Contacts. Not touched. |
| `lib/features/contacts/widgets/az_index_column.dart` | Already Venues/Contacts-only before this amendment; unaffected. |
| `lib/features/contacts/widgets/band_member_card.dart` | Card itself unchanged — only its container view (`band_members_view.dart`) changes. |
| `lib/features/contacts/widgets/contacts_view.dart` | Subtitle construction lives in `ContactCard`, not here; search/grouping/index-column logic unaffected by the company field. |
| `lib/features/contacts/contacts_controller.dart` | No state-shape change needed; `company` flows through existing `load()`/`refresh()`. |
| `lib/features/contacts/contacts_repository.dart` | Generic `data` map pass-through already supports arbitrary new keys; confirmed via audit. |
| `lib/features/contacts/widgets/venues_view.dart`, `venue_card.dart`, `venue_detail_screen.dart`, `venue_form_screen.dart`, `venues_controller.dart`, `venues_repository.dart`, `models/venue.dart` | Out of scope — Venues untouched by this amendment. |
| `lib/features/members/members_controller.dart`, `members_repository.dart`, `member_vm.dart`, `widgets/member_card.dart`, `widgets/role_management_sheet.dart` | `membersProvider` and its shared state remain untouched; Band Members' simplification is view-layer only. |
| `lib/features/contacts/widgets/title_pill_selector.dart` | Reused as-is for the existing Title field; not extended to Company (Company is free-text, no predefined set — see Proposed Solution). |
| `lib/main.dart` | No routing/init changes. |

---

## Migration Policy

**Required.** See Database Impact above.

---

## Edge Function Deploy

**Not required.** No backend function changes — direct PostgREST insert/update against `contacts`, unchanged call pattern.

---

## New Dependencies

**None.**

---

## Regression Risk

**Level:** LOW (down from the base plan's MEDIUM, which was driven by the now-already-shipped-and-QA-approved `venues_view.dart` retrofit — untouched by this amendment)

**Rationale:**

- Band Members change is a net **removal** of code and state (two controllers, a listener, flat-index branching) in favor of a simpler, already-proven-in-this-codebase pattern (`CustomScrollView`/`SliverList`) — this reduces surface area rather than adding to it. No shared helper files change, so Venues and Contacts are provably unaffected by this half of the amendment (confirmed via usage audit, not assumed).
- Contacts change is additive-only at the schema level (one nullable column, no RLS/trigger/RPC changes) and touches exactly three files in a narrow, well-understood way (model field, one form field + one map key, one subtitle formatter) — no new widgets, no new state shape, no change to search/grouping/index-column behavior.
- The one place elevated risk could hide is the `_save()` call site in `contact_form_screen.dart`, since it's shared by both create and update — this is exactly why it's called out explicitly as the single audited call site above, and is a dedicated Verification Plan item below.

---

## Engineer Task Breakdown

Continuing from the base plan's Task 12. Execute in strict order. This section covers only the amendment delta — do not re-do Tasks 1–12.

### Task 13: Simplify BandMembersView — drop search/sectioning

- Edit `band_members_view.dart`: convert `_BandMembersViewState`/`StatefulWidget` back to a plain `StatelessWidget` (`BandMembersView` directly implements `build()`, no local state class).
- Remove: `TextEditingController _searchController`, `ItemScrollController _itemScrollController`, `ItemPositionsListener _itemPositionsListener`, `String _searchQuery`, `dispose()`, `_groupingKey()`, `_filterMembers()`, `_calculateItemCount()`, `_buildItem()`, `_buildSearchBar()`, the `AzSearchField` instantiation, the `AzSectionHeader` instantiation, the `groupByLetter()` call, and the isSearching/empty-search-results branch (including its `CustomScrollView`/`SliverFillRemaining` "No members found" block — unreachable once search is gone).
- Remove now-unused imports: `scrollable_positioned_list`, `az_list_helpers.dart`, `az_search_field.dart`, `az_section_header.dart`.
- Rebuild `build()`: keep the existing loading/error/zero-members early returns (`_buildLoadingState()`, `_buildErrorState()`, `MembersEmptyState`) unchanged. For the populated case, render `RefreshIndicator(onRefresh: widget.onRefresh, child: CustomScrollView(slivers: [SliverToBoxAdapter(<fixed title row, unchanged>), SliverPadding(padding: EdgeInsets.all(Spacing.pagePadding), sliver: SliverList.separated(...))]))` — a `SliverList` of `BandMemberCard(member: member, showAdminActions: membersState.isCurrentUserAdmin, onManageRole: () => widget.onManageRole(member))` built directly from `membersState.members` (no filtering, no grouping), each card full list width (`Spacing.pagePadding` both sides, no right-padding reservation — unchanged from before).
- Keep `_buildLoadingState()` and `_buildErrorState()` exactly as they are today.

### Task 14: Add company column migration

- Create `supabase/migrations/20260725000000_add_company_to_contacts.sql` with the exact SQL specified in Database Impact above (`ALTER TABLE public.contacts ADD COLUMN company TEXT;`).
- Do not add any RLS policy, trigger, or index — confirmed not needed.

### Task 15: Add `company` to Contact model

- Edit `models/contact.dart`: add `final String? company;` to the class, the constructor (optional named param), `fromJson` (`company: json['company'] as String?`), and `toJson` (`'company': company`).

### Task 16: Add company field to ContactFormScreen

- Edit `contact_form_screen.dart`: add `late TextEditingController _companyController;`, initialize in `initState()` from `c?.company ?? ''`, dispose in `dispose()`. Add a `TextField` using the existing `_inputDecoration('Company')` pattern, placed after the Title section (`TitlePillSelector`) and before the Phone field. In `_save()`, add `'company': _companyController.text.trim().isEmpty ? null : _companyController.text.trim()` to the `data` map — this single map is used for both `_repository.updateContact(...)` (edit mode) and `_repository.createContact(...)` (create mode), so one edit covers both write paths.

### Task 17: Combine title+company on ContactCard subtitle

- Edit `contact_card.dart`: replace the subtitle `Text(contact.title ?? '', ...)` with `Text(_subtitle(contact), ...)`, adding the private `_subtitle(Contact contact)` helper exactly as specified in Proposed Solution above (comma-join when both present, single field when only one present, empty string when neither — preserving the always-rendered-blank-line-for-uniform-height behavior).

### Task 18: Cross-platform manual verification

- Web (at minimum, per the base feature's precedent — QA's `QA_REPORT.md` used a static `flutter build web` release build against a real Supabase demo account after the debug web-server device hung on the Dart Debug Extension handshake). iOS/Android/macOS if available.
- Exercise both changes per the Verification Plan Addendum below.

---

## Verification Plan Addendum

These are in addition to (not a replacement for) the base plan's Verification Plan / QA Regression Areas, which remain in force for everything not touched by this amendment (Venues, Contacts search/sectioning/index-column, admin kebab flow, etc. — all already QA-approved and unaffected here).

### Test AM1: Band Members — Search/Sections Fully Removed

1. Navigate to Contacts tab → Band segment.
2. Confirm **no search bar** is rendered.
3. Confirm **no A-Z section headers** are rendered anywhere in the list.
4. Confirm **no index column** (already true pre-amendment, must remain true).
5. Confirm cards render full list width with no dead space, in a single flat scrollable list (server order — last-name-first, per `MembersRepository`'s existing sort — with no client-side re-sorting or re-grouping).
6. Confirm each `BandMemberCard` still shows name + musical-roles subtitle at uniform height, exactly as before this amendment.
7. As an admin: confirm the kebab (⋮) still appears and still opens `RoleManagementSheet`; a role change still persists and the list still reloads correctly (no crash, no duplication) — this flow was the base feature's highest-risk item and must not regress from a view-layer-only refactor.
8. As a non-admin: confirm the kebab does not appear.
9. Confirm tapping a card body (not the kebab) is still a no-op.
10. Pull to refresh → confirm still works.
11. Confirm the zero-members empty state (`MembersEmptyState`) still renders correctly for a band with no members.

### Test AM2: Contacts — Company Field Round-Trip

1. Navigate to Contacts tab → Contacts segment → tap "Add".
2. Enter a name, a title (e.g. "Booking Agent"), and a company (e.g. "Venue Nation"). Save.
3. Confirm the new contact's list card subtitle shows `"Booking Agent, Venue Nation"`.
4. Tap the card to re-open it in edit mode → confirm both Title and Company fields are pre-filled correctly (confirms the read path — `select('*')` — picks up the new column).
5. Clear the Title field only, leaving Company set. Save. Confirm the subtitle now shows only the company (no leading comma/stray punctuation).
6. Clear the Company field only (restore Title). Save. Confirm the subtitle shows only the title — matches pre-amendment behavior exactly.
7. Clear both Title and Company. Save. Confirm the subtitle line renders blank (not missing/collapsed) — card height stays uniform with siblings.
8. Edit an **existing** contact created before this amendment (one with a `title` but no `company`, i.e. `company` is `NULL` from before the column existed): confirm it opens without error, Company field is blank, and saving with a new company value persists correctly.
9. Confirm search (by name only) is unaffected — company is not a searchable field, matching the base plan's existing, unchanged scope.

---

## QA Regression Areas Addendum

### Primary (this amendment's changes)

1. Band Members: search bar absent, section headers absent, full-width cards, correct (last-name-first server) order preserved.
2. Band Members: admin kebab → `RoleManagementSheet` still works after the `StatefulWidget` → `StatelessWidget` reversion (highest-risk item — a working admin flow surviving a structural widget-type change).
3. Contacts: company field saves and loads correctly on both create and edit.
4. Contacts: subtitle combiner renders all four states correctly (both fields, title-only, company-only, neither).
5. Contacts: pre-existing contacts (created before the migration, `company IS NULL`) open and edit without error.

### Regression (existing functionality touched by this amendment)

6. Band Members loading/error/zero-members states — unchanged code paths, but re-verify no regression since the surrounding `build()` method was rewritten.
7. Other `membersProvider` consumers (financials, events forms, home, profile) — unaffected in theory since `membersProvider`/`MemberVM` are untouched by this amendment; spot-check per the base plan's existing regression area.
8. Contacts search, A-Z sectioning, `#` bucket, index column, tap→`ContactFormScreen` edit flow — should be fully unaffected (no changes to `contacts_view.dart`), but worth a quick smoke-test given `contact_card.dart` did change.
9. Venues — **fully unaffected**, zero files touched by this amendment; no re-test needed beyond what QA already did for the base feature.

---

## System Impact Map (Amendment Delta)

| System | Impact |
|---|---|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | affected — `band_members_view.dart` rendering simplified; `membersProvider`/`MembersState`/`MembersRepository`/`MemberVM` untouched; admin role-management preserved |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Database | affected — new nullable column on `contacts`, no RLS/trigger/RPC changes |
| Platform (iOS / Android / Web / macOS) | affected — UI-only changes, no platform-specific code paths |

---

## Out of Scope

1. **Any change to Venues** — not touched by this amendment.
2. **Any change to Contacts search, sectioning, or index-column behavior** — company is not a searchable/groupable field.
3. **A predefined/pill-style selector for Company** — free-text `TextField`, matching `phone`/`email`/`notes`, not `title`'s pill selector (no fixed set of company values exists or is being defined).
4. **Retroactively backfilling `company` for existing contacts** — new column is nullable with no default; existing rows simply have `company IS NULL` until a user edits them.
5. **Any change to `az_list_helpers.dart`, `az_search_field.dart`, `az_section_header.dart`, or `az_index_column.dart`** — confirmed still correctly shared by Venues/Contacts as-is.
6. **Re-adding an index column or search to Band Members** — this amendment removes those, it does not relocate them.
7. **Any change to `BandMemberCard`, `member_card.dart`, `role_management_sheet.dart`, or `membersProvider`/`MembersRepository`/`MemberVM`** — Band Members' simplification is confined to its container view.
8. **Company field validation (format, length limits, uniqueness)** — same lightweight-record treatment as the other free-text contact fields; no validation exists for `phone`/`email`/`notes` today either.

---

## Amendment Summary

This amendment makes two independent, narrow changes to the already-implemented, QA-approved (but not yet committed) `feature/band-contacts-az-listing` branch. **Band Members** reverts from the base feature's search/A-Z-sectioned `ScrollablePositionedList` implementation back to a plain `StatelessWidget`/`CustomScrollView`/`SliverList` rendering of `BandMemberCard`s — a net code reduction that reuses this exact codebase's pre-feature pattern, keeps the admin-kebab flow intact, and is expected to bring `band_members_view.dart` back under the Guardrails §8 400-line target QA had flagged. **Contacts** gains a nullable `company` column (one small migration, RLS/trigger-unaffected), threaded through the `Contact` model, the single form call site that builds create/update payloads, and a new comma-based title+company subtitle combiner on `ContactCard` that mirrors the already-shipped `VenueCard` city/state pattern. Neither change touches Venues, the shared A-Z helper files, or `membersProvider` — confirmed by direct usage audit, not assumed. Regression risk for this amendment is LOW.
